#!/usr/bin/env bash
# Renders docs/banner.png out of two screenshots, so after docs/screenshots.sh.
#
#   docs/banner.sh
set -euo pipefail
cd "$(dirname "$0")/.."

# The README's tagline, so the banner cannot come to say something else.
tagline="$(sed -n 's|^<h3>\(.*\)</h3>$|\1|p' docs/README.md)"
if [ -z "$tagline" ] || [ "$(printf '%s\n' "$tagline" | wc -l)" -ne 1 ]; then
    echo "docs/README.md: no single <h3> line to take the tagline from" >&2
    exit 1
fi

python3 docs/banner.py \
    --product oak.yaml \
    --logo docs/logo.svg \
    --card docs/screenshots/installer.png \
    --card docs/screenshots/installing.png \
    --tagline "$tagline" \
    --cell 9
