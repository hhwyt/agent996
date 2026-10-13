#!/bin/bash
# Build a macOS .icns from DeepSeek's official vector logo (the whale mark in
# deepseek-ai/DeepSeek-V2 figures/logo.svg), downloaded at install time so the
# skill itself ships no third-party logo file. Uses only built-in tools.
#
# Usage: make_deepseek_icon.sh <output.icns>
set -euo pipefail

OUTPUT_ICNS="$1"
LOGO_URL="https://raw.githubusercontent.com/deepseek-ai/DeepSeek-V2/da42dcd40b41803c68a712ddd210eeb10e71e598/figures/logo.svg"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

curl -fsSL --max-time 30 -o "$WORK_DIR/logo.svg" "$LOGO_URL"

# logo.svg = whale mark + "deepseek" wordmark; the whale is the longest path.
python3 -I - "$WORK_DIR/logo.svg" "$WORK_DIR/icon.svg" <<'PY'
import re, sys
paths = re.findall(r'<path[^>]*\bd="([^"]+)"', open(sys.argv[1]).read())
if not paths:
    sys.exit("no paths in logo.svg")
whale = max(paths, key=len)
# macOS icon grid: 824px plate inset 100px in a 1024px canvas; whale (~56x41 units) ~66% of the plate.
open(sys.argv[2], "w").write(
    '<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">'
    '<rect x="100" y="100" width="824" height="824" rx="185" fill="#fff"/>'
    '<g transform="translate(512 520) scale(9.7) translate(-28 -20.7)">'
    f'<path d="{whale}" fill="#4D6BFE"/></g></svg>')
PY

sips -s format png "$WORK_DIR/icon.svg" --out "$WORK_DIR/icon_1024.png" >/dev/null
mkdir "$WORK_DIR/icon.iconset"
for spec in 16:16x16 32:16x16@2x 32:32x32 64:32x32@2x 128:128x128 256:128x128@2x 256:256x256 512:256x256@2x 512:512x512 1024:512x512@2x; do
  sips -z "${spec%%:*}" "${spec%%:*}" "$WORK_DIR/icon_1024.png" --out "$WORK_DIR/icon.iconset/icon_${spec#*:}.png" >/dev/null
done
iconutil -c icns "$WORK_DIR/icon.iconset" -o "$OUTPUT_ICNS"
echo "Built $OUTPUT_ICNS from DeepSeek's official logo"
