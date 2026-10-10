#!/usr/bin/env bash
# Renders docs/screenshots/ out of the sources, by hand after a visible change.
# VERSION is what the pages show, so the next release can be pictured before it
# exists. Needs chromium, imagemagick, python-pyte, python-yaml,
# ttf-firacode-nerd, and systemd as PID 1 for localectl and timedatectl.
#
#   docs/screenshots.sh [VERSION]
set -euo pipefail
cd "$(dirname "$0")/.."

make dev ${1:+VERSION="$1"}
python3 docs/screenshots.py --product .dev
