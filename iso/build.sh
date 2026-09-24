#!/bin/bash
# A built release turned into the two images Arch OS starts from, each a stock
# Arch profile patched so it boots straight into the interface:
#
#   the Recovery   `baseline` and what recovery/ adds to it: the smallest Arch
#                  there is, with nothing on it but the Recovery. Two files,
#                  which the Installer writes to the disk it installs to
#   the ISO        `releng`, the Arch live image, with every module on it and
#                  the Recovery beside them
#
#   build.sh <release-dir>
#
# Both land beside that release, and what they are called is read out of the
# release itself.
set -eu

# ////////////////////////////////////////////////////////////////////////////
# CONFIGURATION
# ////////////////////////////////////////////////////////////////////////////

# Resolved before anything moves, because everything below is relative to this
# script rather than to wherever it was started from.
[ "$#" -eq 1 ] || {
    echo "usage: $0 <release-dir>" >&2
    exit 1
}
RELEASE_DIR="$(realpath -m "$1")"
DIST_DIR="$(dirname "$RELEASE_DIR")"
RECOVERY_DIR="${RELEASE_DIR}-recovery"
cd "$(dirname "$0")"

# mkarchiso has to run as root. Empty when there is nothing to elevate, which is
# the case in CI.
SUDO=""
[ "$(id -u)" -eq 0 ] || SUDO="sudo"

DOWNLOAD_DIR="./download"

# Both profiles, patched here and built from here.
PROFILES_DIR="./archiso"
RECOVERY_PROFILE="${PROFILES_DIR}/recovery"
ISO_PROFILE="${PROFILES_DIR}/iso"

# mkarchiso's scratch space, outside the repository: pacstrap mounts /proc and
# /sys inside it, and anything on the desktop that walks a project folder holds
# those open long enough for the unmount, and the build, to fail.
WORK_DIR="$(realpath -m "${WORK_DIR:-/var/tmp/arch-os-iso-work}")"

# The bootsplash theme, vendored into both images at the commit named here
# rather than at whatever its default branch holds on the day of the build, so a
# desk and CI build the same images. Raised by hand, like OAK_VERSION in the
# Makefile. PLYMOUTH_THEME_SRC points at a theme folder of one's own instead,
# for working on the theme itself.
PLYMOUTH_THEME_REPO="https://github.com/murkl/plymouth-theme-arch-os"
PLYMOUTH_THEME_REF="17edba09e8e62b7e77b282e238fe4426f9d2d1e2"

# `splash` tells plymouth to show itself; the rest is the boot log getting out of
# its way. https://wiki.archlinux.org/title/Silent_boot
#
# Plymouth forces its text plugin the moment it finds a serial console and never
# looks for a screen again, and a virtual machine is handed one without asking -
# the installed system's kernel_args says the same. Measured under QEMU: without
# it the Recovery boots as a wall of text.
BOOT_ARGS='quiet splash loglevel=3 rd.udev.log_level=3 vt.global_cursor_default=0 systemd.show_status=auto plymouth.ignore-serial-consoles'

TEMP_DIR="$(mktemp -d)"

# ////////////////////////////////////////////////////////////////////////////
# CLEANUP
# ////////////////////////////////////////////////////////////////////////////

# A run interrupted between pacstrap's mounts and its teardown leaves them
# behind, and every later run then fails on those. Deepest first, and lazily.
unmount_leftovers() {
    findmnt -rno TARGET | grep "^$(realpath -m "$1")/" | sort -r | while read -r target; do
        echo "unmounting leftover: ${target}"
        ${SUDO} umount -l "$target"
    done
}

# mkarchiso writes as root, and a root-owned file inside a checkout breaks
# everything that walks it afterwards, so nothing root-owned survives this
# script. A build that worked takes the profiles with it; one that failed keeps
# them - there is nothing else to read a failure out of - but hands them back.
# The temporary folder goes either way, and with it the key the Recovery was
# signed with.
cleanup() {
    status=$?
    set +e
    rm -rf "${TEMP_DIR}"
    unmount_leftovers "${WORK_DIR}"
    ${SUDO} rm -rf "${WORK_DIR}"
    if [ "$status" -eq 0 ]; then
        ${SUDO} rm -rf "${PROFILES_DIR}"
    elif [ -d "${PROFILES_DIR}" ]; then
        echo "build failed - the profiles are left at ${PROFILES_DIR}"
        ${SUDO} chown -R "$(id -u):$(id -g)" "${PROFILES_DIR}"
    fi
    exit "$status"
}
trap cleanup EXIT

# ////////////////////////////////////////////////////////////////////////////
# WHAT BOTH IMAGES GET
# ////////////////////////////////////////////////////////////////////////////

# Each takes the profile it patches as its first argument.

set_key_value() { grep -q "^$2=" "$1" && sed -i "s|^$2=.*|$2=\"$3\"|" "$1" || echo "$2=$3" >>"$1"; }

# The Oak binary with oak.yaml, oak.sh and the modules handed over beside it -
# the only place it looks. /opt/arch-os is what the systemd unit in src/
# starts, and what the launchers on the path beside it run out of.
install_arch_os() {
    local profile="$1" opt="$1/airootfs/opt/arch-os"
    shift
    cp -rf src/* "${profile}/airootfs/"
    mkdir -p "${opt}/modules"
    cp "${RELEASE_DIR}/oak" "${RELEASE_DIR}/oak.yaml" "${RELEASE_DIR}/oak.sh" "$opt"
    cp -r "$@" "${opt}/modules/"
}

# mkarchiso copies the profile without its modes, so everything that has to be
# executable in the image is named in profiledef.sh: the Oak binary and every
# launcher on the path. Run once the profile holds all of them.
make_executable() {
    local file path
    for file in "$1/airootfs/opt/arch-os/oak" "$1/airootfs/usr/local/bin/"*; do
        path="${file#"$1/airootfs"}"
        grep -q "\[\"${path}\"\]" "$1/profiledef.sh" ||
            sed -i "/^file_permissions=(/a\\  [\"${path}\"]=\"0:0:755\"" "$1/profiledef.sh"
    done
}

# The theme is vendored rather than taken from the AUR: building an AUR package
# needs makepkg, a build user and a network, none of which an image build should
# need for a folder of PNGs. That one commit and nothing around it, fetched once
# for both images. A checkout left in download/ by an earlier build is reused
# only while it is still that commit.
fetch_theme() {
    [ -z "${PLYMOUTH_THEME_SRC:-}" ] || return 0
    local theme="${DOWNLOAD_DIR}/plymouth-theme"
    if [ "$(git -C "$theme" rev-parse HEAD 2>/dev/null)" != "$PLYMOUTH_THEME_REF" ]; then
        echo "### Fetching Plymouth theme ${PLYMOUTH_THEME_REF}"
        rm -rf "$theme"
        git init -q "$theme"
        git -C "$theme" fetch -q --depth 1 "$PLYMOUTH_THEME_REPO" "$PLYMOUTH_THEME_REF"
        git -C "$theme" checkout -q --detach FETCH_HEAD
    fi
    PLYMOUTH_THEME_SRC="${theme}/src"
}

install_bootsplash() {
    local profile="$1" hooks="$1/airootfs/etc/mkinitcpio.conf.d/archiso.conf"
    grep -qxF "plymouth" "${profile}/packages.x86_64" || echo "plymouth" >>"${profile}/packages.x86_64"

    mkdir -p "${profile}/airootfs/usr/share/plymouth/themes"
    cp -rT "${PLYMOUTH_THEME_SRC}" "${profile}/airootfs/usr/share/plymouth/themes/arch-os"

    # plymouth-set-default-theme would theme the build host, so the config is
    # written and the hook added by hand - which is all that command does.
    mkdir -p "${profile}/airootfs/etc/plymouth"
    printf '[Daemon]\nTheme=arch-os\n' >"${profile}/airootfs/etc/plymouth/plymouthd.conf"

    # The hook goes after `base udev`, which is where plymouth needs to be to own
    # the console before anything else prints to it.
    [ -f "$hooks" ] || { echo "Error: archiso mkinitcpio config not found at '${hooks}'" && exit 1; }
    grep -q 'plymouth' "$hooks" || sed -i 's/^HOOKS=(\(base [a-z]*\)/HOOKS=(\1 plymouth/' "$hooks"
}

# One systemd unit on tty1 replaces autologin, a shell profile and a menu script:
# there is exactly one thing this machine booted to do, and which module that
# turns out to be is a page of the interface's own.
start_on_tty1() {
    mkdir -p "$1/airootfs/etc/systemd/system/multi-user.target.wants"
    ln -sf /etc/systemd/system/arch-os.service \
        "$1/airootfs/etc/systemd/system/multi-user.target.wants/arch-os.service"
}

# The name and the version the image goes by, which its os-release carries as
# well.
name_image() {
    set_key_value "$1/profiledef.sh" iso_name "$2"
    set_key_value "$1/profiledef.sh" iso_version "$VERSION"
}

# ////////////////////////////////////////////////////////////////////////////
# BUILD
# ////////////////////////////////////////////////////////////////////////////

echo "### Initialize Build"

# What a release is, checked before an hour of mkarchiso finds out. The modules
# are not named here: which ones there are is whatever the release holds.
for part in oak oak.yaml oak.sh modules modules/recovery; do
    [ -e "${RELEASE_DIR}/${part}" ] || {
        echo "Error: ${RELEASE_DIR} holds no ${part} - run 'make build' first" >&2
        exit 1
    }
done

# The tools are packages rather than something to install behind somebody's
# back: a build that would change the machine it runs on says so instead.
for tool in mkarchiso:archiso ukify:systemd-ukify mkfs.erofs:erofs-utils; do
    command -v "${tool%%:*}" >/dev/null || {
        echo "Error: ${tool%%:*} not found - install the ${tool#*:} package" >&2
        exit 1
    }
done

# The release says what it is, so neither image can end up named after anything
# else than what it ships.
VERSION="$(sed -n 's/^version:[[:space:]]*//p' "${RELEASE_DIR}/oak.yaml")"
echo "building Arch OS ${VERSION} from ${RELEASE_DIR}"
mkdir -p "$DOWNLOAD_DIR"
unmount_leftovers "${WORK_DIR}"
unmount_leftovers "${PROFILES_DIR}"
${SUDO} rm -rf "${PROFILES_DIR}" "${WORK_DIR}"
# mkarchiso resolves where it works and where it writes before it makes either,
# so what lies above both has to be there.
mkdir -p "${PROFILES_DIR}/out" "${WORK_DIR}"

fetch_theme
[ -d "${PLYMOUTH_THEME_SRC}" ] || { echo "Error: plymouth theme not found in '${PLYMOUTH_THEME_SRC}'" && exit 1; }
# The .plymouth file names the theme; without it plymouthd has nothing to load.
[ -f "${PLYMOUTH_THEME_SRC}/arch-os.plymouth" ] || { echo "Error: '${PLYMOUTH_THEME_SRC}' is not a plymouth theme" && exit 1; }

# ////////////////////////////////////////////////////////////////////////////
# THE RECOVERY
# ////////////////////////////////////////////////////////////////////////////

# First, because the ISO carries it. How it boots and why it is built this way:
# the Recovery Partition in docs/REFERENCE.md
echo "### Build the Recovery"
cp -r /usr/share/archiso/configs/baseline/. "$RECOVERY_PROFILE"

# baseline is made to be a guest in somebody's cloud, and switches on ssh, a
# network and the agents of four hypervisors. The Recovery goes near a network
# only when somebody asks it to - the network may be what broke - so everything
# baseline starts goes, and it starts nothing but itself. What it brings up on
# request is in recovery/.
rm -rf "${RECOVERY_PROFILE}/airootfs/etc/systemd/system" \
    "${RECOVERY_PROFILE}/airootfs/etc/systemd/network" \
    "${RECOVERY_PROFILE}/airootfs/etc/systemd/networkd.conf.d" \
    "${RECOVERY_PROFILE}/airootfs/etc/systemd/resolved.conf.d" \
    "${RECOVERY_PROFILE}/airootfs/etc/ssh"

# Its packages, and what makes it a kiosk: the Recovery on tty1, started again
# whenever it ends, with what the Installer left it and no login anywhere.
cp -r recovery/. "$RECOVERY_PROFILE"

install_arch_os "$RECOVERY_PROFILE" "${RELEASE_DIR}/modules/recovery"
# The Installer is not on this image, so neither is the command that opens it.
rm "${RECOVERY_PROFILE}/airootfs/usr/local/bin/installer"
make_executable "$RECOVERY_PROFILE"
install_bootsplash "$RECOVERY_PROFILE"
start_on_tty1 "$RECOVERY_PROFILE"
name_image "$RECOVERY_PROFILE" arch-os-recovery

# The root file system is signed with a key made for this build and thrown away
# with it, and the certificate goes into the ram disk - which the boot loader
# starts as one image with the kernel and the command line, signed with the
# machine's own keys where Secure Boot is on. So nothing on the partition starts
# that this build did not make. From 1970 to 9999, because openssl holds a
# signature to the clock, and a machine whose clock battery died is still one
# to be repaired.
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes \
    -subj "/CN=Arch OS Recovery ${VERSION}" \
    -not_before 19700101000000Z -not_after 99991231235959Z \
    -keyout "${TEMP_DIR}/recovery.key" -out "${TEMP_DIR}/recovery.crt"

# netboot rather than iso: the kernel, the ram disk and the root file system as
# three files, without an ISO around them to be taken apart again.
${SUDO} mkarchiso -v -m netboot -c "${TEMP_DIR}/recovery.crt ${TEMP_DIR}/recovery.key" \
    -w "${WORK_DIR}/recovery" -o "${PROFILES_DIR}/out/recovery" "$RECOVERY_PROFILE"
netboot="${PROFILES_DIR}/out/recovery/arch"

# The partition: a read-only file system holding the root file system and its
# signature where the ram disk looks for them, found by a UUID made for this
# build - so no other disk's partition can be taken for it.
uuid="$(cat /proc/sys/kernel/random/uuid)"
mkdir -p "${TEMP_DIR}/partition/arch/x86_64"
cp "${netboot}/x86_64/airootfs.erofs" "${netboot}/x86_64/airootfs.erofs.cms.sig" "${TEMP_DIR}/partition/arch/x86_64/"
rm -rf "$RECOVERY_DIR"
mkdir -p "$RECOVERY_DIR"
mkfs.erofs --quiet --all-root -U "$uuid" "${RECOVERY_DIR}/recovery.img" "${TEMP_DIR}/partition"

# The image the boot loader starts it with. copytoram, so nothing of the disk is
# held while the Recovery works on it. nomodeset, so the screen the firmware set
# up is the one it draws on: no graphics driver, and no firmware on the image
# for one to need - and plymouth draws on that screen at once, where it would
# otherwise wait for a driver that never comes. What the boot menu calls it is
# its os-release.
cat >"${TEMP_DIR}/os-release" <<EOF
NAME="Arch OS Recovery"
PRETTY_NAME="Arch OS Recovery"
ID=arch-os-recovery
IMAGE_VERSION=${VERSION}
EOF
ukify build \
    --linux="${netboot}/boot/x86_64/vmlinuz-linux" \
    --initrd="${netboot}/boot/x86_64/initramfs-linux.img" \
    --cmdline="archisobasedir=arch archisodevice=UUID=${uuid} copytoram=y cms_verify=y nomodeset ${BOOT_ARGS}" \
    --os-release="@${TEMP_DIR}/os-release" \
    --output="${RECOVERY_DIR}/recovery.efi"

du -h "${RECOVERY_DIR}/"*

# ////////////////////////////////////////////////////////////////////////////
# THE ISO
# ////////////////////////////////////////////////////////////////////////////

echo "### Build the ISO"
cp -r /usr/share/archiso/configs/releng/. "$ISO_PROFILE"

# The stock package list outlives the repositories it names, and pacstrap
# refuses the whole list over the one name it cannot find. What is gone is taken
# out here and said out loud, so the image is one package short rather than
# missing.
echo "### Check Packages"
ISO_PACKAGES="${ISO_PROFILE}/packages.x86_64"
DROPPED="$(comm -23 \
    <(grep -v '^[[:space:]]*\(#\|$\)' "$ISO_PACKAGES" | sort -u) \
    <({ pacman -Slq && pacman -Sgq; } | sort -u))"
if [ -n "$DROPPED" ]; then
    echo "not in the repositories, dropped: $(tr '\n' ' ' <<<"$DROPPED")"
    grep -vxF "$DROPPED" "$ISO_PACKAGES" >"${TEMP_DIR}/packages" && mv "${TEMP_DIR}/packages" "$ISO_PACKAGES"
fi

# Every module the release holds, and the Recovery beside them as the Installer
# writes it - see RECOVERY_IMAGE in modules/installer/module.sh.
install_arch_os "$ISO_PROFILE" "${RELEASE_DIR}/modules/"*
mkdir -p "${ISO_PROFILE}/airootfs/opt/arch-os-recovery"
cp "${RECOVERY_DIR}/recovery.img" "${RECOVERY_DIR}/recovery.efi" "${ISO_PROFILE}/airootfs/opt/arch-os-recovery/"
make_executable "$ISO_PROFILE"
install_bootsplash "$ISO_PROFILE"
start_on_tty1 "$ISO_PROFILE"

# Networking is left as the Arch ISO ships it: iwd and systemd-networkd, already
# enabled. A machine with no link is refused by the installer's own preflight
# check, which says to use iwctl.

for entry in "${ISO_PROFILE}"/efiboot/loader/entries/01-archiso-linux*.conf; do
    grep -q 'splash' "$entry" || sed -i "/^options / s/\$/ ${BOOT_ARGS}/" "$entry"
done
sed -i 's/^timeout.*/timeout 0/' "${ISO_PROFILE}/efiboot/loader/loader.conf"

# A prompt on this image is reached by leaving Arch OS or by it failing, and
# either way the first question is how to get back to it. Both files, because
# they are shown at different moments: /etc/issue before the login, /etc/motd
# after it.
cat >"${ISO_PROFILE}/airootfs/etc/issue" <<'EOF'
Arch OS live environment. Type installer or recovery to start again.

EOF

cat >"${ISO_PROFILE}/airootfs/etc/motd" <<'EOF'
Arch OS live environment

  installer    install Arch Linux on this machine
  recovery     repair an Arch Linux system already on a disk
  iwctl        join a wireless network

Add --debug to either for a run that changes nothing, and --language=de to
skip the first page.

Both keep their answers in /opt/arch-os, so starting either again picks up where
it left off. What they did is in /opt/arch-os/installer.log and
/opt/arch-os/recovery.log.

Reaching this prompt without asking for it means Arch OS stopped on its own:
journalctl -b -u arch-os says why.

EOF

name_image "$ISO_PROFILE" arch-os
set_key_value "${ISO_PROFILE}/profiledef.sh" iso_application "Arch OS ISO"

# zstd instead of xz: xz squeezes out a little more and spends minutes of build
# time and seconds of every boot doing it.
set_key_value "${ISO_PROFILE}/profiledef.sh" airootfs_image_type "squashfs"
sed -i "s|^airootfs_image_tool_options=.*|airootfs_image_tool_options=('-comp' 'zstd' '-Xcompression-level' '19' '-b' '1M')|" \
    "${ISO_PROFILE}/profiledef.sh"

# UEFI only: the installer's preflight refuses anything else, so a BIOS boot path
# would only offer a boot that ends in a refusal.
#
# bootmodes is a multi-line array in the stock profile, so the whole block is
# replaced - rewriting its first line leaves the rest behind as a syntax error.
sed -i "/^bootmodes=(/,/)$/c\\bootmodes=('uefi.systemd-boot')" "${ISO_PROFILE}/profiledef.sh"

# How the kernel finds the medium it booted from. A volume identifier is upper
# case letters, digits and underscores, at most 32 of them, so anything else in
# the version becomes an underscore.
ISO_LABEL="$(printf 'ARCH_OS_%s' "$VERSION" | tr -c '[:alnum:]' '_' | tr '[:lower:]' '[:upper:]' | cut -c1-32)"
set_key_value "${ISO_PROFILE}/profiledef.sh" iso_label "$ISO_LABEL"

echo "### Make Arch OS ISO"
${SUDO} mkarchiso -v -w "${WORK_DIR}/iso" -o "${PROFILES_DIR}/out/iso" "$ISO_PROFILE"

# ////////////////////////////////////////////////////////////////////////////
# SHIP
# ////////////////////////////////////////////////////////////////////////////

# The image goes to DIST_DIR, beside the tarball and the Recovery.
echo "### Move ISO to Dist"
mkdir -p "${DIST_DIR}"
cp -f "${PROFILES_DIR}/out/iso/"*.iso "${DIST_DIR}/"
