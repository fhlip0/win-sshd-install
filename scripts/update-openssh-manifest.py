#!/usr/bin/env python3
"""Refresh config/openssh.json from PowerShell/Win32-OpenSSH latest release."""
from __future__ import annotations

import json
import re
import sys
import urllib.request
from pathlib import Path

API = "https://api.github.com/repos/PowerShell/Win32-OpenSSH/releases/latest"


def arch_key(name: str) -> str | None:
    if "Win64" in name:
        return "AMD64"
    if "ARM64" in name:
        return "ARM64"
    if "Win32" in name:
        return "x86"
    return None


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    manifest_path = root / "config" / "openssh.json"

    repo_base = ""
    if manifest_path.exists():
        repo_base = json.loads(manifest_path.read_text()).get("repoBaseUrl", "")

    with urllib.request.urlopen(API, timeout=60) as resp:
        release = json.load(resp)

    tag = release["tag_name"]
    packages: dict[str, dict[str, str]] = {}
    for asset in release.get("assets", []):
        name = asset.get("name", "")
        if not name.endswith(".msi") or "Symbol" in name:
            continue
        key = arch_key(name)
        if not key:
            continue
        digest = asset.get("digest", "")
        sha = digest.removeprefix("sha256:") if digest else ""
        packages[key] = {"fileName": name, "sha256": sha}

    manifest = {
        "version": re.split(r"[p-]", tag)[0],
        "releaseTag": tag,
        "upstreamBaseUrl": f"https://github.com/PowerShell/Win32-OpenSSH/releases/download/{tag}",
        "repoBaseUrl": repo_base,
        "packages": packages,
    }

    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Updated {manifest_path} for release {tag}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
