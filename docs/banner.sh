#!/usr/bin/env bash
# Renders docs/banner.png out of two screenshots, so after docs/screenshots.sh.
#
#   docs/banner.sh
set -euo pipefail
cd "$(dirname "$0")/.."

# The README's tagline, the paragraph under its banner, so the banner cannot
# come to say something else. Its bold stays the README's.
tagline="$(awk '/src="banner\.png"/ { found = 1; next } found && NF { print; exit }' docs/README.md)"
case "$tagline" in
"<p>"*"</p>")
    tagline="${tagline#<p>}"
    tagline="${tagline%</p>}"
    ;;
*)
    echo "docs/README.md: no <p> line under the banner to take the tagline from" >&2
    exit 1
    ;;
esac
tagline="${tagline//<b>/}"
tagline="${tagline//<\/b>/}"

python3 docs/banner.py \
    --product product.yaml \
    --logo docs/logo.svg \
    --card docs/screenshots/installer.png \
    --card docs/screenshots/installing.png \
    --tagline "$tagline" \
    --cell 9
