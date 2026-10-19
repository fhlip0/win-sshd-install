#!/usr/bin/env bash
# Verify MSIs/ZIPs in packages/ against config/openssh.json (run on Mac/Linux before pushing).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="$ROOT/config/openssh.json"
PKG_DIR="$ROOT/packages"

python3 <<PY
import hashlib
import json
from pathlib import Path

manifest = json.loads(Path("$MANIFEST").read_text())
pkg_dir = Path("$PKG_DIR")
errors = []

def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

for arch, pkg in manifest["packages"].items():
    for key, label in (("fileName", "msi"), ("zipFileName", "zip")):
        name = pkg.get(key)
        if not name:
            continue
        path = pkg_dir / name
        if not path.exists():
            print(f"  missing  {name} ({arch})")
            continue
        expected = (pkg.get("sha256") if label == "msi" else pkg.get("zipSha256")) or ""
        digest = sha256(path)
        if expected and digest != expected.lower():
            errors.append(f"{name}: expected {expected}, got {digest}")
        else:
            print(f"  ok       {name} ({arch})")

if errors:
    print("\nFAILED:")
    for e in errors:
        print(f"  - {e}")
    raise SystemExit(1)
print("\nAll present packages verified.")
PY
