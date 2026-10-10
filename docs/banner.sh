#!/usr/bin/env bash
# Renders docs/banner.png out of two screenshots, so after docs/screenshots.sh.
#
#   docs/banner.sh
set -euo pipefail
cd "$(dirname "$0")/.."

python3 docs/banner.py \
    --product oak.yaml \
    --logo docs/logo.svg \
    --card docs/screenshots/installer.png \
    --card docs/screenshots/installing.png \
    --tagline "Install Arch Linux with ease - as a desktop or a TTY system. Installer and Recovery on one image." \
    --cell 9
