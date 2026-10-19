#Requires -Version 5.1
#Requires -RunAsAdministrator

[CmdletBinding(DefaultParameterSetName = 'Server')]
param(
    [Parameter(ParameterSetName = 'Server')]
    [Parameter(ParameterSetName = 'Client')]
    [Parameter(ParameterSetName = 'Both')]
    [switch] $Server,

    [Parameter(ParameterSetName = 'Client')]
    [switch] $Client,

    [Parameter(ParameterSetName = 'Both')]
    [switch] $Both,

    [int] $Port = 22,
    [switch] $SkipFirewall,
    [switch] $Quiet,
    [switch] $SkipAuthorizedKeyPrompt,
    [string] $AuthorizedKey,
    [string] $AuthorizedKeyPath,
    [string] $RepoRoot,
    [string] $MsiPath,
    [string] $RepoBaseUrl
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step {
    param([string] $Message)
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Get-RepoRoot {
    param([string] $Start)
    if ($Start) {
        return (Resolve-Path -LiteralPath $Start).Path
    }
    $here = $PSScriptRoot
    if ($here -match '[\\/]scripts$') {
        return (Resolve-Path -LiteralPath (Join-Path $here '..')).Path
    }
    return $here
}

function Get-ProcessorArchitecture {
    $cpu = Get-CimInstance -ClassName Win32_Processor | Select-Object -First 1
    switch ($cpu.Architecture) {
        0 { return 'x86' }
        5 { return 'ARM64' }
        9 { return 'AMD64' }
        12 { return 'ARM64' }
        default {
            if ([Environment]::Is64BitOperatingSystem) {
                return 'AMD64'
            }
            return 'x86'
        }
    }
}

function Get-FileSha256 {
    param([string] $Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-OpenSshManifest {
    param([string] $Root)
    $manifestPath = Join-Path $Root 'config/openssh.json'
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        throw "Missing manifest: $manifestPath"
    }
    return Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
}

function Test-PackageHash {
    param(
        [string] $Path,
        [string] $ExpectedSha256,
        [string] $Label
    )
    if (-not $ExpectedSha256) {
        return
    }
    $hash = Get-FileSha256 -Path $Path
    $expected = $ExpectedSha256.ToLowerInvariant()
    if ($hash -ne $expected) {
        throw "SHA256 mismatch for $Label. Expected $expected, got $hash"
    }
}

function Resolve-OpenSshMsi {
    param(
        [object] $Manifest,
        [string] $Architecture,
        [string] $Root,
        [string] $ExplicitMsiPath,
        [string] $BaseUrlOverride
    )

    $pkg = $Manifest.packages.$Architecture
    if (-not $pkg) {
        throw "No package entry for architecture '$Architecture' in config/openssh.json"
    }

    if ($ExplicitMsiPath) {
        if (-not (Test-Path -LiteralPath $ExplicitMsiPath)) {
            throw "MSI not found: $ExplicitMsiPath"
        }
        return (Resolve-Path -LiteralPath $ExplicitMsiPath).Path
    }

    $localPath = Join-Path $Root (Join-Path 'packages' $pkg.fileName)
    if (Test-Path -LiteralPath $localPath) {
        Write-Step "Using local package: $localPath"
        Test-PackageHash -Path $localPath -ExpectedSha256 $pkg.sha256 -Label $pkg.fileName
        return (Resolve-Path -LiteralPath $localPath).Path
    }

    if ($pkg.zipFileName) {
        $localZip = Join-Path $Root (Join-Path 'packages' $pkg.zipFileName)
        if (Test-Path -LiteralPath $localZip) {
            Write-Step "Using local ZIP package: $localZip"
            Test-PackageHash -Path $localZip -ExpectedSha256 $pkg.zipSha256 -Label $pkg.zipFileName
            return (Install-OpenSshFromZip -ZipPath $localZip)
        }
    }

    $bases = @()
    if ($BaseUrlOverride) { $bases += $BaseUrlOverride.TrimEnd('/') }
    if ($Manifest.repoBaseUrl) { $bases += $Manifest.repoBaseUrl.TrimEnd('/') }
    $bases += $Manifest.upstreamBaseUrl.TrimEnd('/')

    $tempDir = Join-Path $env:TEMP ("openssh-install-{0}" -f [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    $dest = Join-Path $tempDir $pkg.fileName

    $downloaded = $false
    foreach ($base in ($bases | Select-Object -Unique)) {
        $url = "{0}/{1}" -f $base, $pkg.fileName
        Write-Step "Downloading $url"
        try {
            Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
            $downloaded = $true
            break
        } catch {
            Write-Warning "Download failed from ${url}: $($_.Exception.Message)"
        }
    }

    if (-not $downloaded) {
        throw "Could not download $($pkg.fileName). Place the MSI in packages\ or set -RepoBaseUrl."
    }

    Test-PackageHash -Path $dest -ExpectedSha256 $pkg.sha256 -Label $pkg.fileName

    return $dest
}

function Install-OpenSshFromZip {
    param([string] $ZipPath)

    $installDir = Join-Path $env:ProgramFiles 'OpenSSH'
    if (Test-Path -LiteralPath (Join-Path $installDir 'sshd.exe')) {
        Write-Step "OpenSSH already present at $installDir (ZIP install skipped)"
        return '__ZIP_ALREADY_INSTALLED__'
    }

    Write-Step "Extracting ZIP to $installDir"
    New-Item -ItemType Directory -Path $installDir -Force | Out-Null
    $stage = Join-Path $env:TEMP ("openssh-zip-{0}" -f [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $stage -Force | Out-Null
    try {
        Expand-Archive -LiteralPath $ZipPath -DestinationPath $stage -Force
        $extracted = Get-ChildItem -Path $stage -Directory | Where-Object { $_.Name -like 'OpenSSH-*' } | Select-Object -First 1
        if (-not $extracted) {
            throw "Could not find OpenSSH-* folder inside $ZipPath"
        }
        Copy-Item -Path (Join-Path $extracted.FullName '*') -Destination $installDir -Recurse -Force
    } finally {
        Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
    }

    return '__ZIP_ALREADY_INSTALLED__'
}

function Get-AddLocalArg {
    param(
        [string] $ParameterSetName
    )
    switch ($ParameterSetName) {
        'Server' { return 'Server' }
        'Client' { return 'Client' }
        'Both' { return 'Client,Server' }
        default {
            throw "Unhandled parameter set: $ParameterSetName"
        }
    }
}

function Install-OpenSshMsi {
    param(
        [string] $Msi,
        [string] $AddLocal,
        [switch] $QuietInstall
    )

    $logPath = Join-Path $env:TEMP ("openssh-msi-{0}.log" -f (Get-Date -Format 'yyyyMMddHHmmss'))
    $args = @(
        '/i', "`"$Msi`"",
        "ADDLOCAL=$AddLocal",
        '/norestart',
        '/L*v', "`"$logPath`""
    )
    if ($QuietInstall) {
        $args += '/qn'
    } else {
        $args += '/passive'
    }

    Write-Step "Installing OpenSSH ($AddLocal) via MSI"
    $proc = Start-Process -FilePath 'msiexec.exe' -ArgumentList $args -Wait -PassThru
    if ($proc.ExitCode -ne 0) {
        throw "msiexec failed with exit code $($proc.ExitCode). Log: $logPath"
    }
}

function Get-OpenSshInstallDir {
    $candidates = @(
        "${env:ProgramFiles}\OpenSSH",
        "${env:ProgramFiles}\OpenSSH-Win64"
    )
    foreach ($dir in $candidates) {
        if (Test-Path -LiteralPath (Join-Path $dir 'sshd.exe')) {
            return $dir
        }
    }
    return $null
}

function Ensure-SshdService {
    param([string] $InstallDir)

    $service = Get-Service -Name sshd -ErrorAction SilentlyContinue
    if ($service) {
        return
    }

    $script = Join-Path $InstallDir 'install-sshd.ps1'
    if (-not (Test-Path -LiteralPath $script)) {
        throw "sshd service missing and install-sshd.ps1 not found at $script"
    }

    Write-Step "Registering sshd service"
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script
}

function Ensure-FirewallRule {
    param(
        [int] $SshPort,
        [string] $InstallDir
    )

    $ruleName = 'OpenSSH-Server-In-TCP'
    $existing = Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Step "Firewall rule '$ruleName' already exists"
        return
    }

    $sshd = Join-Path $InstallDir 'sshd.exe'
    Write-Step "Creating firewall rule for TCP $SshPort"
    New-NetFirewallRule -Name $ruleName `
        -DisplayName 'OpenSSH SSH Server (sshd)' `
        -Enabled True `
        -Direction Inbound `
        -Protocol TCP `
        -Action Allow `
        -LocalPort $SshPort `
        -Program $sshd | Out-Null
}

function Set-SshdListenPort {
    param([int] $SshPort)

    if ($SshPort -eq 22) {
        return
    }

    $configPath = Join-Path $env:ProgramData 'ssh\sshd_config'
    if (-not (Test-Path -LiteralPath $configPath)) {
        Write-Warning "sshd_config not found at $configPath; firewall uses port $SshPort but sshd may still listen on 22"
        return
    }

    Write-Step "Setting sshd_config Port to $SshPort"
    $lines = Get-Content -LiteralPath $configPath
    $found = $false
    $updated = foreach ($line in $lines) {
        if ($line -match '^\s*#?\s*Port\s+\d+') {
            $found = $true
            "Port $SshPort"
        } else {
            $line
        }
    }
    if (-not $found) {
        $updated = @("Port $SshPort") + $updated
    }
    Set-Content -LiteralPath $configPath -Value $updated -Encoding ascii
}

function Start-Sshd {
    Write-Step "Starting sshd and setting startup type to Automatic"
    Set-Service -Name sshd -StartupType Automatic
    Restart-Service -Name sshd -ErrorAction SilentlyContinue
    Start-Service -Name sshd
}

function Test-SshPublicKeyLine {
    param([string] $Line)
    $trimmed = $Line.Trim()
    if (-not $trimmed) {
        return $false
    }
    return $trimmed -match '^(ssh-(rsa|ed25519|dss)|ecdsa-sha2-)\s+\S+'
}

function Read-SshPublicKeyContent {
    param(
        [string] $Key,
        [string] $KeyPath
    )

    if ($KeyPath) {
        if (-not (Test-Path -LiteralPath $KeyPath)) {
            throw "Public key file not found: $KeyPath"
        }
        $Key = (Get-Content -LiteralPath $KeyPath -Raw).Trim()
    }

    if (-not $Key) {
        return $null
    }

    $line = ($Key -split "`n" | Where-Object { $_ -match '\S' } | Select-Object -First 1).Trim()
    if (-not (Test-SshPublicKeyLine -Line $line)) {
        throw 'Invalid public key. Expected one line starting with ssh-ed25519, ssh-rsa, ecdsa-sha2-*, or ssh-dss.'
    }
    return $line
}

function Set-AdministratorsAuthorizedKeysAcl {
    param([string] $Path)

    $proc = Start-Process -FilePath 'icacls.exe' -ArgumentList @(
        "`"$Path`"",
        '/inheritance:r',
        '/grant', '*S-1-5-32-544:F',
        '/grant', 'SYSTEM:F'
    ) -Wait -PassThru -NoNewWindow

    if ($proc.ExitCode -ne 0) {
        throw "icacls failed with exit code $($proc.ExitCode) for $Path"
    }
}

function Add-AdministratorAuthorizedKey {
    param(
        [string] $PublicKeyLine,
        [string] $InstallDir
    )

    $sshDir = Join-Path $env:ProgramData 'ssh'
    $authKeysPath = Join-Path $sshDir 'administrators_authorized_keys'

    if (-not (Test-Path -LiteralPath $sshDir)) {
        New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
    }

    if (Test-Path -LiteralPath $authKeysPath) {
        $existing = Get-Content -LiteralPath $authKeysPath -ErrorAction SilentlyContinue |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -and -not $_.StartsWith('#') }
        if ($existing -contains $PublicKeyLine) {
            Write-Step "Public key already present in administrators_authorized_keys"
            Set-AdministratorsAuthorizedKeysAcl -Path $authKeysPath
            return
        }
    }

    Write-Step "Adding public key to $authKeysPath"
    Add-Content -LiteralPath $authKeysPath -Value $PublicKeyLine -Encoding ascii
    Set-AdministratorsAuthorizedKeysAcl -Path $authKeysPath

    $fixScript = Join-Path $InstallDir 'FixUserFilePermissions.ps1'
    if (Test-Path -LiteralPath $fixScript) {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $fixScript | Out-Null
    }
}

function Offer-AdministratorAuthorizedKey {
    param(
        [string] $InstallDir,
        [string] $Key,
        [string] $KeyPath,
        [switch] $SkipPrompt,
        [switch] $QuietInstall
    )

    if ($SkipPrompt -or $QuietInstall) {
        if ($Key -or $KeyPath) {
            $content = Read-SshPublicKeyContent -Key $Key -KeyPath $KeyPath
            Add-AdministratorAuthorizedKey -PublicKeyLine $content -InstallDir $InstallDir
        }
        return
    }

    if ($Key -or $KeyPath) {
        $content = Read-SshPublicKeyContent -Key $Key -KeyPath $KeyPath
        Add-AdministratorAuthorizedKey -PublicKeyLine $content -InstallDir $InstallDir
        return
    }

    Write-Host ''
    Write-Host 'Administrator SSH keys use:' -ForegroundColor Yellow
    Write-Host "  $env:ProgramData\ssh\administrators_authorized_keys"
    Write-Host '(Not the user profile .ssh\authorized_keys file.)'
    Write-Host ''
    $answer = Read-Host 'Add a public key for administrator login now? [Y/n]'
    if ($answer -match '^[Nn]') {
        return
    }

    $input = Read-Host 'Path to .pub file, or paste one line of public key'
    $input = $input.Trim().Trim('"')
    $content = if (Test-Path -LiteralPath $input) {
        Read-SshPublicKeyContent -KeyPath $input
    } else {
        Read-SshPublicKeyContent -Key $input
    }

    Add-AdministratorAuthorizedKey -PublicKeyLine $content -InstallDir $InstallDir
    Write-Host 'Public key added. Try: ssh Administrator@this-host' -ForegroundColor Green
}

$root = Get-RepoRoot -Start $RepoRoot
$manifest = Get-OpenSshManifest -Root $root
$arch = Get-ProcessorArchitecture
$addLocal = Get-AddLocalArg -ParameterSetName $PSCmdlet.ParameterSetName

$msi = Resolve-OpenSshMsi `
    -Manifest $manifest `
    -Architecture $arch `
    -Root $root `
    -ExplicitMsiPath $MsiPath `
    -BaseUrlOverride $RepoBaseUrl

if ($msi -ne '__ZIP_ALREADY_INSTALLED__') {
    Install-OpenSshMsi -Msi $msi -AddLocal $addLocal -QuietInstall:$Quiet
} elseif ($addLocal -match 'Client' -and $addLocal -notmatch 'Server') {
    throw 'ZIP layout installs full OpenSSH; use -Server or -Both, not -Client alone.'
}

$installDir = Get-OpenSshInstallDir
if (-not $installDir) {
    throw 'OpenSSH install directory not found after MSI install'
}

if ($addLocal -match 'Server') {
    Ensure-SshdService -InstallDir $installDir
    Set-SshdListenPort -SshPort $Port
    if (-not $SkipFirewall) {
        Ensure-FirewallRule -SshPort $Port -InstallDir $installDir
    }
    Start-Sshd
    Offer-AdministratorAuthorizedKey `
        -InstallDir $installDir `
        -Key $AuthorizedKey `
        -KeyPath $AuthorizedKeyPath `
        -SkipPrompt:$SkipAuthorizedKeyPrompt `
        -QuietInstall:$Quiet
}

Write-Step "Done. OpenSSH $($manifest.version) ($arch) installed to $installDir"
if ($addLocal -match 'Server') {
    $svc = Get-Service -Name sshd
    Write-Host "sshd is $($svc.Status) (startup: Automatic). SSH port $Port." -ForegroundColor Green
}
