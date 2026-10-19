# windows-ssh-server

Install OpenSSH on Windows in **seconds** using the [Win32-OpenSSH MSI](https://github.com/PowerShell/Win32-OpenSSH/wiki/Install-Win32-OpenSSH-Using-MSI), instead of **Optional Features / DISM** (often 15–20+ minutes).

This repo holds a pinned manifest (`config/openssh.json`), optional offline MSIs (`packages/`), and a PowerShell installer that downloads from **your repo first** (if configured), then upstream GitHub.

## Quick start (on the Windows machine)

1. Clone or copy this repo to the server.
2. Open **PowerShell as Administrator**.
3. Run:

```powershell
cd C:\path\to\windows-ssh-server
Set-ExecutionPolicy -Scope Process Bypass
.\Install-OpenSSH-Server.ps1
```

Server only is the default. Other options:

```powershell
.\Install-OpenSSH-Server.ps1 -Both              # client + server
.\Install-OpenSSH-Server.ps1 -Client            # client only
.\Install-OpenSSH-Server.ps1 -Port 2222         # custom SSH port (firewall rule)
.\Install-OpenSSH-Server.ps1 -Quiet             # silent MSI (/qn)
.\Install-OpenSSH-Server.ps1 -SkipFirewall      # no firewall rule
.\Install-OpenSSH-Server.ps1 -SkipAuthorizedKeyPrompt   # no post-install key prompt
.\Install-OpenSSH-Server.ps1 -AuthorizedKeyPath $env:USERPROFILE\.ssh\id_ed25519.pub
```

After a **server** install, the script sets `sshd` to **Automatic**, **starts the service**, opens the firewall (unless skipped), then prompts to add an SSH public key to `C:\ProgramData\ssh\administrators_authorized_keys` (required for **Administrator** / admin-group logins on Windows OpenSSH—not `authorized_hosts`).
```

## Download order

1. `-MsiPath` if you pass a local MSI path
2. `packages\<file>` from this repo (offline / air-gapped)
3. `repoBaseUrl` in `config/openssh.json` (your GitHub release mirror)
4. `-RepoBaseUrl` parameter (one-off override)
5. `upstreamBaseUrl` in the manifest (PowerShell/Win32-OpenSSH on GitHub)

SHA256 from the manifest is verified after download.

## Host MSIs on your repo (faster / internal mirror)

1. Run `./build-and-release.sh` on a dev machine (macOS/Linux) to refresh the manifest.
2. Run `DOWNLOAD_MSIS=1 ./build-and-release.sh` to fetch MSIs into `packages/`.
3. Create a GitHub release and upload the three MSIs (or only the architectures you use).
4. Set `repoBaseUrl` in `config/openssh.json`, for example:

```json
"repoBaseUrl": "https://github.com/YOUR_USER/windows-ssh-server/releases/download/v1.0.0"
```

Clients then pull MSIs from your release URL before hitting GitHub.

## Why not DISM?

```powershell
# Slow — Windows Update / FoD pipeline
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
```

The MSI installs to `C:\Program Files\OpenSSH`, registers `sshd`, and is the same bits Microsoft publishes on GitHub—without the Optional Features install path.

## Updating OpenSSH version

On macOS/Linux (or anywhere with `curl` and Python 3):

```bash
./build-and-release.sh
```

Commit the updated `config/openssh.json`. Optionally publish new MSIs on your release.

## Requirements

- Windows 10 / 11 / Server 2016+
- Administrator PowerShell
- Network access for download (unless using `packages/`)

## License

MIT — OpenSSH binaries are subject to [Win32-OpenSSH](https://github.com/PowerShell/Win32-OpenSSH) licensing.
