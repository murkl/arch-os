#!/bin/bash
# Turns a built release into a bootable ISO: stock Arch `releng`, patched so it
# boots straight into the installer.
#
# RELEASE_DIR points at the release to ship, DIST_DIR at where the download goes,
# SNAPSHOT_VERSION names the build. The defaults are what the root Makefile uses.
# The finished image and its checksum land in DIST_DIR.
set -e

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# CONFIGURATION
# ////////////////////////////////////////////////////////////////////////////////////////////////////

# mkarchiso has to run as root. Empty when there is nothing to elevate, which is
# the case in CI.
SUDO=""
[ "$(id -u)" -eq 0 ] || SUDO="sudo"

RELEASE_DIR="${RELEASE_DIR:-../release}"
DIST_DIR="${DIST_DIR:-../dist}"
DOWNLOAD_DIR="./download"
ISO_DIR="./archiso"
ISO_CONFIG="releng" # baseline or releng

# mkarchiso's scratch space, outside the repository: pacstrap mounts /proc and
# /sys inside it, and anything on the desktop that walks a project folder holds
# those open long enough for the unmount, and the build, to fail.
WORK_DIR="$(realpath -m "${WORK_DIR:-/var/tmp/arch-os-iso-work}")"

AIRFS_OPT="${ISO_DIR}/airootfs/opt/arch-os"

# The bootsplash theme, vendored into the ISO. A checkout beside this repo is
# used when there is one; CI has none and fetches it instead.
PLYMOUTH_THEME_REPO="https://github.com/murkl/plymouth-theme-arch-os"
: "${PLYMOUTH_THEME_SRC:=../../plymouth-theme-arch-os/src}"

# The short commit SHA of HEAD, or "dev" outside a repository.
: "${SNAPSHOT_VERSION:=$(git -C .. rev-parse --short HEAD 2>/dev/null || echo dev)}"

TEMP_DIR="$(mktemp -d)"

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# CLEANUP
# ////////////////////////////////////////////////////////////////////////////////////////////////////

# A run interrupted between pacstrap's mounts and its teardown leaves them
# behind, and every later run then fails on those. Deepest first, and lazily.
unmount_leftovers() {
    findmnt -rno TARGET | grep "^$(realpath -m "$1")/" | sort -r | while read -r target; do
        echo "unmounting leftover: ${target}"
        ${SUDO} umount -l "$target"
    done
}

# What a build leaves behind, and what it does not.
#
# mkarchiso writes as root, and a root-owned file inside a checkout breaks
# everything that walks it afterwards, so nothing root-owned survives this
# script. ISO_DIR is a fresh copy of the stock profile every run, so a build that
# worked takes it with it; a build that failed keeps it - there is nothing else
# to read a failure out of - but hands it back. DOWNLOAD_DIR stays either way.
cleanup() {
    status=$?
    set +e
    rm -rf "${TEMP_DIR}"
    unmount_leftovers "${WORK_DIR}"
    ${SUDO} rm -rf "${WORK_DIR}"
    if [ "$status" -eq 0 ]; then
        ${SUDO} rm -rf "${ISO_DIR}"
    elif [ -d "${ISO_DIR}" ]; then
        echo "build failed - the profile is left at ${ISO_DIR}"
        ${SUDO} chown -R "$(id -u):$(id -g)" "${ISO_DIR}"
    fi
    exit "$status"
}
trap cleanup EXIT

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# BUILD
# ////////////////////////////////////////////////////////////////////////////////////////////////////

echo "### Initialize Build"
[ -x "${RELEASE_DIR}/runtime" ] || { echo "Error: ${RELEASE_DIR}/runtime not found - run 'make build' first" >&2 && exit 1; }
[ -f "${RELEASE_DIR}/runtime.yaml" ] || { echo "Error: ${RELEASE_DIR}/runtime.yaml not found - run 'make build' first" >&2 && exit 1; }
[ -f "${RELEASE_DIR}/modules/installer/installer.yaml" ] || { echo "Error: ${RELEASE_DIR}/modules/installer/installer.yaml not found - run 'make build' first" >&2 && exit 1; }
[ -f "${RELEASE_DIR}/modules/recovery/recovery.yaml" ] || { echo "Error: ${RELEASE_DIR}/modules/recovery/recovery.yaml not found - run 'make build' first" >&2 && exit 1; }
mkdir -p "$DOWNLOAD_DIR"
unmount_leftovers "${WORK_DIR}"
unmount_leftovers "${ISO_DIR}"
${SUDO} rm -rf "${ISO_DIR}" "${WORK_DIR}"
mkdir -p "${ISO_DIR}"
mkdir -p "${RELEASE_DIR}"

# Install dependencies
! command -v /usr/bin/mkarchiso &>/dev/null && ${SUDO} pacman -S --noconfirm archiso

# Generate ISO (baseline/releng)
cp -r "/usr/share/archiso/configs/${ISO_CONFIG}/"* "${ISO_DIR}"

# Copy sources (the systemd unit and the console theme)
cp -rf src/* "${ISO_DIR}/airootfs/"

# The stock package list outlives the repositories it names: a package dropped
# from Arch stays in the profile until the next archiso release, and pacstrap
# refuses the whole list over the one name it cannot find. What is gone is taken
# out here and said out loud, so the image is one package short rather than
# missing.
echo "### Check Packages"
ISO_PACKAGES="${ISO_DIR}/packages.x86_64"
DROPPED="$(comm -23 \
    <(grep -v '^[[:space:]]*\(#\|$\)' "$ISO_PACKAGES" | sort -u) \
    <({ pacman -Slq && pacman -Sgq; } | sort -u))"
if [ -n "$DROPPED" ]; then
    echo "not in the repositories, dropped: $(tr '\n' ' ' <<<"$DROPPED")"
    grep -vxF "$DROPPED" "$ISO_PACKAGES" >"${TEMP_DIR}/packages" && mv "${TEMP_DIR}/packages" "$ISO_PACKAGES"
fi

# The runtime binary with runtime.yaml and the modules folder beside it - the
# only place the runtime looks. /opt/arch-os is what the systemd unit
# below starts, and what the three launchers on the path run out of.
echo "### Install Arch OS"
mkdir -p "${AIRFS_OPT}"
cp -r "${RELEASE_DIR}/." "${AIRFS_OPT}/"
chmod +x "${AIRFS_OPT}/runtime"

# Set permissions
add_permission() { grep -q "\[\"$1\"\]" "${ISO_DIR}/profiledef.sh" || sed -i "/^file_permissions=(/a\\  [\"$1\"]=\"0:0:755\"" "${ISO_DIR}/profiledef.sh"; }
add_permission /opt/arch-os/runtime
add_permission /usr/local/bin/arch-os
add_permission /usr/local/bin/installer
add_permission /usr/local/bin/recovery
add_permission /usr/local/bin/arch-os-console-theme

# The theme is vendored rather than taken from the AUR: building an AUR package
# needs makepkg, a build user and a network, none of which an ISO build should
# need for a folder of PNGs.
echo "### Install Plymouth"
grep -qxF "plymouth" "${ISO_DIR}/packages.x86_64" || echo "plymouth" >>"${ISO_DIR}/packages.x86_64"

if [ ! -d "${PLYMOUTH_THEME_SRC}" ]; then
    echo "### Fetching Plymouth theme"
    rm -rf "${DOWNLOAD_DIR}/plymouth-theme"
    git clone --depth 1 "${PLYMOUTH_THEME_REPO}" "${DOWNLOAD_DIR}/plymouth-theme"
    PLYMOUTH_THEME_SRC="${DOWNLOAD_DIR}/plymouth-theme/src"
fi
[ -d "${PLYMOUTH_THEME_SRC}" ] || { echo "Error: plymouth theme not found in '${PLYMOUTH_THEME_SRC}'" && exit 1; }
# The .plymouth file names the theme; without it plymouthd has nothing to load.
[ -f "${PLYMOUTH_THEME_SRC}/arch-os.plymouth" ] || { echo "Error: '${PLYMOUTH_THEME_SRC}' is not a plymouth theme" && exit 1; }

mkdir -p "${ISO_DIR}/airootfs/usr/share/plymouth/themes"
cp -rT "${PLYMOUTH_THEME_SRC}" "${ISO_DIR}/airootfs/usr/share/plymouth/themes/arch-os"

# plymouth-set-default-theme would theme the build host, so the config is written
# and the hook added by hand - which is all that command does.
mkdir -p "${ISO_DIR}/airootfs/etc/plymouth"
{
    echo "[Daemon]"
    echo "Theme=arch-os"
} >"${ISO_DIR}/airootfs/etc/plymouth/plymouthd.conf"

# The hook goes after `base udev`/`systemd`, which is where plymouth needs to be
# to own the console before anything else prints to it.
ISO_MKINITCPIO="${ISO_DIR}/airootfs/etc/mkinitcpio.conf.d/archiso.conf"
if [ -f "${ISO_MKINITCPIO}" ]; then
    grep -q 'plymouth' "${ISO_MKINITCPIO}" || sed -i 's/^HOOKS=(\(base [a-z]*\)/HOOKS=(\1 plymouth/' "${ISO_MKINITCPIO}"
else
    echo "Error: archiso mkinitcpio config not found at '${ISO_MKINITCPIO}'" && exit 1
fi

# One systemd unit on tty1 replaces autologin, a shell profile and a menu script:
# there is exactly one thing this machine booted to do, and which of the two
# modules that turns out to be is a page of the interface's own.
mkdir -p "${ISO_DIR}/airootfs/etc/systemd/system/multi-user.target.wants"
ln -sf /etc/systemd/system/arch-os.service \
    "${ISO_DIR}/airootfs/etc/systemd/system/multi-user.target.wants/arch-os.service"

# Networking is left as the Arch ISO ships it: iwd and systemd-networkd, already
# enabled. A machine with no link is refused by the installer's own preflight
# check, which says to use iwctl.

# `splash` tells plymouth to show itself; the rest is the boot log getting out of
# its way.
# https://wiki.archlinux.org/title/Silent_boot
BOOT_ARGS='quiet splash loglevel=3 rd.udev.log_level=3 vt.global_cursor_default=0 systemd.show_status=auto'
for entry in "${ISO_DIR}"/efiboot/loader/entries/01-archiso-linux*.conf; do
    grep -q 'splash' "$entry" || sed -i "/^options / s/\$/ ${BOOT_ARGS}/" "$entry"
done
sed -i 's/^timeout.*/timeout 0/' "${ISO_DIR}/efiboot/loader/loader.conf"

# A prompt on this image is reached by leaving Arch OS or by it failing, and
# either way the first question is how to get back to it, which Arch's own motd,
# a wall of text about an installation guide, does not answer.
#
# Both files, because they are shown at different moments: /etc/issue before the
# login, /etc/motd after it.
cat >"${ISO_DIR}/airootfs/etc/issue" <<'EOF'
Arch OS live environment. Type installer or recovery to start again.

EOF

cat >"${ISO_DIR}/airootfs/etc/motd" <<'EOF'
Arch OS live environment

  installer    install Arch Linux on this machine
  recovery     repair an Arch Linux system already on a disk
  iwctl        join a wireless network

Add --help to either for what it takes on the command line, --debug for a run
that changes nothing.

Both keep their answers in /opt/arch-os, so starting either again picks up where
it left off. What they did is in /opt/arch-os/installer.log and
/opt/arch-os/recovery.log.

EOF

# Set ISO config
set_key_value() { grep -q "^$2=" "$1" && sed -i "s|^$2=.*|$2=\"$3\"|" "$1" || echo "$2=$3" >>"$1"; }
# zstd instead of xz: xz squeezes out a little more and spends minutes of build
# time and seconds of every boot doing it.
set_key_value "${ISO_DIR}/profiledef.sh" airootfs_image_type "squashfs"
sed -i "s|^airootfs_image_tool_options=.*|airootfs_image_tool_options=('-comp' 'zstd' '-Xcompression-level' '19' '-b' '1M')|" \
    "${ISO_DIR}/profiledef.sh"

# UEFI only: the installer's preflight refuses anything else, so a BIOS boot path
# would only offer a boot that ends in a refusal.
#
# bootmodes is a multi-line array in the stock profile, so the whole block is
# replaced - rewriting its first line leaves the rest behind as a syntax error.
sed -i "/^bootmodes=(/,/)$/c\\bootmodes=('uefi.systemd-boot')" "${ISO_DIR}/profiledef.sh"

set_key_value "${ISO_DIR}/profiledef.sh" iso_name "arch-os"
set_key_value "${ISO_DIR}/profiledef.sh" iso_version "$SNAPSHOT_VERSION"
set_key_value "${ISO_DIR}/profiledef.sh" iso_label "ARCH_OS_${SNAPSHOT_VERSION}"
set_key_value "${ISO_DIR}/profiledef.sh" iso_application "Arch OS ISO"

# Make ISO
echo "### Make Arch OS ISO"
${SUDO} mkarchiso -v -w "${WORK_DIR}" -o "${ISO_DIR}/out" "${ISO_DIR}"

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# SHIP
# ////////////////////////////////////////////////////////////////////////////////////////////////////

# The image and its checksum go to DIST_DIR, beside the tarball.
echo "### Move ISO to Dist"
mkdir -p "${DIST_DIR}"
cp -f "${ISO_DIR}/out/"*.iso "${DIST_DIR}/"
echo "### Generate ISO Checksum"
(cd "${DIST_DIR}" && for iso in *.iso; do sha256sum "$iso" >"${iso}.sha256"; done)
