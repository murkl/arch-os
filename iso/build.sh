#!/bin/bash
# Turns a built release (the runtime binary and the installer tree beside it,
# already assembled by `make build` at the repo root) into a bootable ISO:
# stock Arch `releng`, patched so it boots straight into the installer.
#
# Takes no arguments. RELEASE_DIR points at the release to ship, DIST_DIR at
# where a download goes (defaults ../release and ../dist, which is where the
# root Makefile puts them), and SNAPSHOT_VERSION names the build (default: the
# short commit SHA, like everything else here). The finished image and its
# checksum land in DIST_DIR.
set -e

RELEASE_DIR="${RELEASE_DIR:-../release}"
DIST_DIR="${DIST_DIR:-../dist}"
DOWNLOAD_DIR="./download"
ISO_DIR="./archiso"
ISO_CONFIG="releng" # baseline or releng

# mkarchiso's scratch space, kept outside the repository. pacstrap mounts /proc
# and /sys inside it, and anything on the desktop that walks a project folder —
# an editor's file watcher, a background grep — holds those open long enough for
# the unmount to fail. The build then dies cleaning up after itself. Absolute,
# because it is passed to mkarchiso from inside ISO_DIR.
WORK_DIR="$(realpath -m "${WORK_DIR:-/var/tmp/archos-iso-work}")"

AIRFS_OPT="${ISO_DIR}/airootfs/opt/installer"

# The bootsplash theme, vendored into the ISO. A checkout beside this repo is
# used when there is one, so working on the theme needs no round trip through
# GitHub; CI has no such checkout and fetches it instead.
PLYMOUTH_THEME_REPO="https://github.com/murkl/plymouth-theme-arch-os"
: "${PLYMOUTH_THEME_SRC:=../../plymouth-theme-arch-os/src}"

# VERSION (single source of truth: the short commit SHA of HEAD, or "dev"
# outside a repository — the same scheme runtime/Makefile uses)
: "${SNAPSHOT_VERSION:=$(git -C .. rev-parse --short HEAD 2>/dev/null || echo dev)}"

TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TEMP_DIR}"' EXIT

# A run interrupted between pacstrap's mounts and its teardown leaves them
# behind, and every later run then fails on those rather than on anything it did
# itself. Deepest first, and lazily: whatever was holding them is long gone, but
# an open handle on the desktop can still be in the way.
unmount_leftovers() {
    findmnt -rno TARGET | grep "^$(realpath -m "$1")/" | sort -r | while read -r target; do
        echo "unmounting leftover: ${target}"
        sudo umount -l "$target"
    done
}

echo "### Initialize Build"
[ -x "${RELEASE_DIR}/installer" ] || { echo "Error: ${RELEASE_DIR}/installer not found — run 'make build' first" >&2 && exit 1; }
[ -f "${RELEASE_DIR}/installer.yaml" ] || { echo "Error: ${RELEASE_DIR}/installer.yaml not found — run 'make build' first" >&2 && exit 1; }
mkdir -p "$DOWNLOAD_DIR"
unmount_leftovers "${WORK_DIR}"
unmount_leftovers "${ISO_DIR}"
sudo rm -rf "${ISO_DIR}" "${WORK_DIR}"
mkdir -p "${ISO_DIR}"
mkdir -p "${RELEASE_DIR}"

# Install dependencies
! command -v /usr/bin/mkarchiso &>/dev/null && sudo pacman -S --noconfirm archiso

# Generate ISO (baseline/releng)
cp -r "/usr/share/archiso/configs/${ISO_CONFIG}/"* "${ISO_DIR}"

# Copy sources (the systemd unit and the console theme)
cp -rf src/* "${ISO_DIR}/airootfs/"

# The stock package list outlives the repositories it names: a package dropped
# from Arch stays in the profile until the next archiso release, and pacstrap
# refuses the whole list over the one name it cannot find — which is a build
# that fails on somebody else's packaging decision. Whatever is no longer in the
# repositories is taken out here and said out loud, so the image is one package
# short instead of missing entirely.
echo "### Check Packages"
ISO_PACKAGES="${ISO_DIR}/packages.x86_64"
DROPPED="$(comm -23 \
    <(grep -v '^[[:space:]]*\(#\|$\)' "$ISO_PACKAGES" | sort -u) \
    <({ pacman -Slq && pacman -Sgq; } | sort -u))"
if [ -n "$DROPPED" ]; then
    echo "not in the repositories, dropped: $(tr '\n' ' ' <<<"$DROPPED")"
    grep -vxF "$DROPPED" "$ISO_PACKAGES" >"${TEMP_DIR}/packages" && mv "${TEMP_DIR}/packages" "$ISO_PACKAGES"
fi

# Install the release: the runtime binary next to its tree, which is the only
# place the runtime looks for one — see runtime/README.md. /opt/installer is
# what the systemd unit below starts.
echo "### Install Arch OS Installer"
mkdir -p "${AIRFS_OPT}"
cp -r "${RELEASE_DIR}/." "${AIRFS_OPT}/"
chmod +x "${AIRFS_OPT}/installer"

# Set permissions
add_permission() { grep -q "\[\"$1\"\]" "${ISO_DIR}/profiledef.sh" || sed -i "/^file_permissions=(/a\\  [\"$1\"]=\"0:0:755\"" "${ISO_DIR}/profiledef.sh"; }
add_permission /opt/installer/installer
add_permission /usr/local/bin/installer
add_permission /usr/local/bin/installer-console-theme

# PLYMOUTH
#
# The theme is vendored out of the plymouth-theme-arch-os checkout rather than
# taken from the AUR: building an AUR package needs makepkg, a build user and
# a network, none of which an ISO build should need for a folder of PNGs.
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

# Point plymouth at it. plymouth-set-default-theme cannot run here — it would
# theme the build host — so the config is written and the hook added by hand,
# which is all that command does anyway.
mkdir -p "${ISO_DIR}/airootfs/etc/plymouth"
{
    echo "[Daemon]"
    echo "Theme=arch-os"
} >"${ISO_DIR}/airootfs/etc/plymouth/plymouthd.conf"

# archiso builds its initramfs from its own mkinitcpio.conf. The hook goes
# after `base udev`/`systemd`, which is where plymouth needs to be to own the
# console before anything else prints to it.
ISO_MKINITCPIO="${ISO_DIR}/airootfs/etc/mkinitcpio.conf.d/archiso.conf"
if [ -f "${ISO_MKINITCPIO}" ]; then
    grep -q 'plymouth' "${ISO_MKINITCPIO}" || sed -i 's/^HOOKS=(\(base [a-z]*\)/HOOKS=(\1 plymouth/' "${ISO_MKINITCPIO}"
else
    echo "Error: archiso mkinitcpio config not found at '${ISO_MKINITCPIO}'" && exit 1
fi

# Start the installer directly. One systemd unit on tty1 replaces autologin,
# a shell profile and a menu script: there is exactly one thing this machine
# booted to do.
mkdir -p "${ISO_DIR}/airootfs/etc/systemd/system/multi-user.target.wants"
ln -sf /etc/systemd/system/installer.service \
    "${ISO_DIR}/airootfs/etc/systemd/system/multi-user.target.wants/installer.service"

# Networking is left exactly as the Arch ISO ships it: iwd and
# systemd-networkd, already enabled. A machine with no link is refused by the
# installer's own preflight check, which says to use iwctl — there is nothing
# for this build to add.

# Bootloader config. `splash` is what tells plymouth to show itself; the rest
# is the boot log getting out of its way.
# https://wiki.archlinux.org/title/Silent_boot
BOOT_ARGS='quiet splash loglevel=3 rd.udev.log_level=3 vt.global_cursor_default=0 systemd.show_status=auto'
for entry in "${ISO_DIR}"/efiboot/loader/entries/01-archiso-linux*.conf; do
    grep -q 'splash' "$entry" || sed -i "/^options / s/\$/ ${BOOT_ARGS}/" "$entry"
done
sed -i 's/^timeout.*/timeout 0/' "${ISO_DIR}/efiboot/loader/loader.conf"

# What the console says, in the two places a console says anything.
#
# Arch's own motd is a wall of text about an installation guide this image does
# not need — and it is shown at exactly the moment it matters most here: a
# prompt on this image is reached by leaving the installer, or by the installer
# failing, and either way the first question is how to get back to it.
#
# Both are written rather than one, because they are shown at different moments:
# /etc/issue before the login, /etc/motd after it. Neither may be the one that
# happens to be missing.
cat >"${ISO_DIR}/airootfs/etc/issue" <<'EOF'
Arch OS live environment. Type installer to start the installer.

EOF

cat >"${ISO_DIR}/airootfs/etc/motd" <<'EOF'
Arch OS live environment

  installer    start the installer
  iwctl        join a wireless network

The installer keeps its answers in /opt/installer, so starting it again picks
up where it left off. Everything it did is in /opt/installer/installer.log.

EOF

# Set ISO config
set_key_value() { grep -q "^$2=" "$1" && sed -i "s|^$2=.*|$2=\"$3\"|" "$1" || echo "$2=$3" >>"$1"; }
# zstd instead of xz. xz squeezes out a little more, and spends minutes of
# build time and seconds of every boot doing it — on a medium that is written
# once and read once, that is the wrong trade.
set_key_value "${ISO_DIR}/profiledef.sh" airootfs_image_type "squashfs"
sed -i "s|^airootfs_image_tool_options=.*|airootfs_image_tool_options=('-comp' 'zstd' '-Xcompression-level' '19' '-b' '1M')|" \
    "${ISO_DIR}/profiledef.sh"

# UEFI only. The installer's preflight refuses anything else, so shipping a
# BIOS boot path would only offer a boot that ends in a refusal.
#
# bootmodes is a multi-line array in the stock profile, so the whole block is
# replaced — rewriting only its first line leaves the rest behind as a syntax
# error, which mkarchiso reports as something else entirely.
sed -i "/^bootmodes=(/,/)$/c\\bootmodes=('uefi.systemd-boot')" "${ISO_DIR}/profiledef.sh"

set_key_value "${ISO_DIR}/profiledef.sh" iso_name "archos"
set_key_value "${ISO_DIR}/profiledef.sh" iso_version "$SNAPSHOT_VERSION"
set_key_value "${ISO_DIR}/profiledef.sh" iso_label "ARCH_OS_${SNAPSHOT_VERSION}"
set_key_value "${ISO_DIR}/profiledef.sh" iso_application "Arch OS Installer ISO"

# Make ISO
echo "### Make Arch OS ISO"
cd "${ISO_DIR}"
sudo rm -rf out
sudo mkarchiso -v -w "${WORK_DIR}" .
cd ..
sudo rm -rf "${WORK_DIR}"

# The image and its checksum go to DIST_DIR, beside the tarball: the release is
# the installer as a machine runs it, and both of these are downloaded instead.
echo "### Move ISO to Dist"
mkdir -p "${DIST_DIR}"
cp -f "${ISO_DIR}/out/"*.iso "${DIST_DIR}/"
echo "### Generate ISO Checksum"
(cd "${DIST_DIR}" && for iso in *.iso; do sha256sum "$iso" >"${iso}.sha256"; done)
