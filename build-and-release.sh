#!/usr/bin/env bash
# Refresh config/openssh.json from the latest Win32-OpenSSH GitHub release.
# Optional: download MSIs into packages/ for offline use or GitHub release assets.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
MANIFEST="$ROOT/config/openssh.json"
DOWNLOAD="${DOWNLOAD_MSIS:-0}"

python3 "$ROOT/scripts/update-openssh-manifest.py"

if [[ "$DOWNLOAD" == "1" ]]; then
  mkdir -p "$ROOT/packages"
  base_url="$(python3 -c "import json; print(json.load(open('$MANIFEST'))['upstreamBaseUrl'])")"
  python3 -c "
import json
from pathlib import Path
m = json.loads(Path('$MANIFEST').read_text())
for pkg in m['packages'].values():
    print(pkg['fileName'])
" | while read -r file; do
    url="${base_url}/${file}"
    echo "Downloading $url"
    curl -fsSL -o "$ROOT/packages/$file" "$url"
  done
  echo "MSIs saved under packages/"
fi

tag="$(python3 -c "import json; print(json.load(open('$MANIFEST'))['releaseTag'])")"
echo "Release tag: $tag"
