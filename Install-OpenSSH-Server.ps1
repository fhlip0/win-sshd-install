#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
  Fast OpenSSH Server install using Win32-OpenSSH MSI (not DISM / Optional Features).

.EXAMPLE
  .\Install-OpenSSH-Server.ps1

.EXAMPLE
  .\Install-OpenSSH-Server.ps1 -Both -Port 2222

.EXAMPLE
  # Use MSIs hosted on your repo's GitHub release (set repoBaseUrl in config/openssh.json)
  .\Install-OpenSSH-Server.ps1 -RepoBaseUrl "https://github.com/you/windows-ssh-server/releases/download/v1.0.0"
#>

[CmdletBinding()]
param(
    [switch] $Client,
    [switch] $Both,
    [int] $Port = 22,
    [switch] $SkipFirewall,
    [switch] $Quiet,
    [switch] $SkipAuthorizedKeyPrompt,
    [string] $AuthorizedKey,
    [string] $AuthorizedKeyPath,
    [string] $MsiPath,
    [string] $RepoBaseUrl
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$installer = Join-Path $scriptDir 'scripts/Install-OpenSSH.ps1'

$params = @{
    Port                       = $Port
    SkipFirewall               = $SkipFirewall
    Quiet                      = $Quiet
    SkipAuthorizedKeyPrompt    = $SkipAuthorizedKeyPrompt
    AuthorizedKey              = $AuthorizedKey
    AuthorizedKeyPath            = $AuthorizedKeyPath
    RepoRoot                   = $scriptDir
    MsiPath                    = $MsiPath
    RepoBaseUrl                = $RepoBaseUrl
}

if ($Both) {
    & $installer @params -Both
} elseif ($Client) {
    & $installer @params -Client
} else {
    & $installer @params -Server
}
