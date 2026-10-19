# Offline / repo-hosted packages

Drop files here to skip download during install. **MSI is preferred** (supports client-only); **ZIP** works as a fallback (full bundle, server install).

| Architecture | MSI (preferred) | ZIP (fallback) |
|--------------|-----------------|----------------|
| AMD64 | `OpenSSH-Win64-v10.0.0.0.msi` | `OpenSSH-Win64.zip` |
| ARM64 | `OpenSSH-ARM64-v10.0.0.0.msi` | `OpenSSH-ARM64.zip` |
| x86 | `OpenSSH-Win32-v10.0.0.0.msi` | `OpenSSH-Win32.zip` |

Filenames and hashes must match `config/openssh.json`. Verify before push:

```bash
./scripts/verify-packages.sh
```

MSIs/ZIPs are gitignored by default. To vendor them in git: `git add -f packages/*`. Or upload to a GitHub release and set `repoBaseUrl` in the manifest.
