#!/bin/bash
# Builds the Recovery image from `baseline` and the ISO from `releng`, each
# patched to boot into Arch OS, out of the program `make build` left. See
# README.md.
#
#   [ISO_RECOVERY=true|false] build.sh <arch-os> <dist-dir>
set -eu

# ////////////////////////////////////////////////////////////////////////////
# CONFIGURATION
# ////////////////////////////////////////////////////////////////////////////

# Resolved before the cd: everything below is relative to this script.
[ "$#" -eq 2 ] || {
    echo "usage: $0 <arch-os> <dist-dir>" >&2
    exit 1
}
BIN="$(realpath -m "$1")"
DIST_DIR="$(realpath -m "$2")"
cd "$(dirname "$0")"

# The program says what it is, so neither image can end up named after anything
# else than what it ships.
VERSION="$("$BIN" --version 2>/dev/null | awk '$1 == "arch-os" { print $2 }')"
[ -n "$VERSION" ] || {
    echo "Error: ${BIN} reports no version. Run 'make build' first." >&2
    exit 1
}
RECOVERY_DIR="${DIST_DIR}/arch-os-${VERSION}-recovery"

# mkarchiso runs as root. Empty where this already is, as in CI.
SUDO=""
[ "$(id -u)" -eq 0 ] || SUDO="sudo"

DOWNLOAD_DIR="./download"

# Both profiles, patched here and built from here.
PROFILES_DIR="./archiso"
RECOVERY_PROFILE="${PROFILES_DIR}/recovery"
ISO_PROFILE="${PROFILES_DIR}/iso"

# Outside the repository: a desktop indexer walking it holds pacstrap's mounts
# open and fails the build.
WORK_DIR="$(realpath -m "${WORK_DIR:-/var/tmp/arch-os-iso-work}")"

# Pinned, so a desk and CI build the same images. Raised by hand.
PLYMOUTH_THEME_REPO="https://github.com/murkl/plymouth-theme-arch-os"
PLYMOUTH_THEME_REF="147e3c97d710db4606025b3829f076ca5d8ecc3b"

# The console's palette, slot by slot, and why each boot argument is there:
# README.md#the-console.
CONSOLE_RED=46,191,163,235,94,180,136,216,174,191,163,235,69,180,143,236
CONSOLE_GRN=52,97,190,203,129,142,192,222,181,97,190,203,169,142,188,239
CONSOLE_BLU=64,106,140,139,172,173,208,233,195,106,140,139,218,173,187,244
CONSOLE_ARGS="fbcon=nodefer vt.default_red=${CONSOLE_RED} vt.default_grn=${CONSOLE_GRN} vt.default_blu=${CONSOLE_BLU}"
BOOT_ARGS="quiet splash loglevel=3 rd.udev.log_level=3 vt.global_cursor_default=0 systemd.show_status=auto plymouth.ignore-serial-consoles ${CONSOLE_ARGS}"

TEMP_DIR="$(mktemp -d)"

# ////////////////////////////////////////////////////////////////////////////
# CLEANUP
# ////////////////////////////////////////////////////////////////////////////

# What an interrupted run left mounted fails every later one. Deepest first.
unmount_leftovers() {
    findmnt -rno TARGET | grep "^$(realpath -m "$1")/" | sort -r | while read -r target; do
        echo "unmounting leftover: ${target}"
        ${SUDO} umount -l "$target"
    done
}

# Nothing root-owned stays in the checkout. A failed build keeps its profiles to
# read, handed back. The key the Recovery was signed with goes either way.
cleanup() {
    status=$?
    set +e
    rm -rf "${TEMP_DIR}"
    unmount_leftovers "${WORK_DIR}"
    ${SUDO} rm -rf "${WORK_DIR}"
    if [ "$status" -eq 0 ]; then
        ${SUDO} rm -rf "${PROFILES_DIR}"
    elif [ -d "${PROFILES_DIR}" ]; then
        echo "build failed, the profiles are left at ${PROFILES_DIR}"
        ${SUDO} chown -R "$(id -u):$(id -g)" "${PROFILES_DIR}"
    fi
    exit "$status"
}
trap cleanup EXIT

# ////////////////////////////////////////////////////////////////////////////
# WHAT BOTH IMAGES GET
# ////////////////////////////////////////////////////////////////////////////

# Each takes the profile it patches as its first argument.

# mkarchiso sources profiledef.sh, so an appended line wins over the stock one.
profiledef() {
    local profile="$1"
    shift
    printf '\n%s' "$@" >>"${profile}/profiledef.sh"
    echo >>"${profile}/profiledef.sh"
}

# The program is the whole product, its modules inside it. It keeps its answers
# and its log beside itself, in /opt/arch-os.
install_arch_os() {
    local profile="$1"
    cp -rf src/* "${profile}/airootfs/"
    ./font.sh "${profile}/airootfs/usr/share/kbd/consolefonts"
    install -D -m 755 "$BIN" "${profile}/airootfs/opt/arch-os/arch-os"
}

# mkarchiso copies the profile without its modes. Run once every program is in.
make_executable() {
    local file
    for file in "$1/airootfs/opt/arch-os/arch-os" "$1/airootfs/usr/local/bin/"* "$1/airootfs/usr/local/lib/arch-os/"*; do
        [ -e "$file" ] || continue
        profiledef "$1" "file_permissions+=([\"${file#"$1/airootfs"}\"]=\"0:0:755\")"
    done
}

# Vendored rather than built from the AUR, which needs makepkg and a build user
# for a folder of PNGs. An earlier checkout is reused while it is that commit.
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
    local theme="$1/airootfs/usr/share/plymouth/themes/arch-os"
    grep -qxF "plymouth" "${profile}/packages.x86_64" || echo "plymouth" >>"${profile}/packages.x86_64"

    mkdir -p "${profile}/airootfs/usr/share/plymouth/themes"
    cp -rT "${PLYMOUTH_THEME_SRC}" "$theme"

    # What is starting, as a line under the spinner: two-step draws the SubTitle
    # at TitleVerticalAlignment, which only a progress bar, never shown here, uses.
    sed -i -e 's/^TitleVerticalAlignment=.*/TitleVerticalAlignment=.8/' \
        -e "/^\[boot-up\]$/a SubTitle=$2" "${theme}/arch-os.plymouth"
    if ! grep -qxF "SubTitle=$2" "${theme}/arch-os.plymouth" || ! grep -qxF "TitleVerticalAlignment=.8" "${theme}/arch-os.plymouth"; then
        echo "Error: the theme's arch-os.plymouth has no [boot-up] or TitleVerticalAlignment to put the line under the spinner" >&2
        exit 1
    fi

    # plymouth-set-default-theme would theme the build host, so the config is
    # written and the hook added by hand, which is all that command does.
    mkdir -p "${profile}/airootfs/etc/plymouth"
    printf '[Daemon]\nTheme=arch-os\n' >"${profile}/airootfs/etc/plymouth/plymouthd.conf"

    # The hook goes after `base udev`, which is where plymouth needs to be to own
    # the console before anything else prints to it.
    [ -f "$hooks" ] || { echo "Error: archiso mkinitcpio config not found at '${hooks}'" && exit 1; }
    grep -q 'plymouth' "$hooks" || sed -i 's/^HOOKS=(\(base [a-z]*\)/HOOKS=(\1 plymouth/' "$hooks"
    grep -q 'plymouth' "$hooks" || { echo "Error: no HOOKS=(base ...) line in '${hooks}' to add plymouth to" && exit 1; }

    # On a live image every boot is the first, and systemd-firstboot resets the
    # console under the splash. The image comes configured, so it asks nothing.
    mkdir -p "${profile}/airootfs/etc/systemd/system"
    ln -sf /dev/null "${profile}/airootfs/etc/systemd/system/systemd-firstboot.service"
}

# One systemd unit on tty1 replaces autologin, a shell profile and a menu script:
# there is exactly one thing this machine booted to do.
start_on_tty1() {
    mkdir -p "$1/airootfs/etc/systemd/system/multi-user.target.wants"
    ln -sf /etc/systemd/system/arch-os.service \
        "$1/airootfs/etc/systemd/system/multi-user.target.wants/arch-os.service"
}

# The name and the version the image goes by, which its os-release carries as
# well.
name_image() { profiledef "$1" "iso_name=\"$2\"" "iso_version=\"${VERSION}\""; }

# ////////////////////////////////////////////////////////////////////////////
# BUILD
# ////////////////////////////////////////////////////////////////////////////

echo "### Initialize Build"

# The Recovery inside the ISO, or left for the Installer to fetch from the
# release page: a pre-release has no release page, and a release's ISO stays
# under GitHub's 2 GiB a file. ISO_RECOVERY decides by hand.
case "$VERSION" in
*-*) ISO_RECOVERY="${ISO_RECOVERY:-true}" ;;
*) ISO_RECOVERY="${ISO_RECOVERY:-false}" ;;
esac
[[ $ISO_RECOVERY =~ ^(true|false)$ ]] || {
    echo "Error: ISO_RECOVERY is '${ISO_RECOVERY}', not true or false" >&2
    exit 1
}

# The tools are packages rather than something to install behind somebody's
# back: a build that would change the machine it runs on says so instead.
for tool in mkarchiso:archiso ukify:systemd-ukify mkfs.erofs:erofs-utils fsck.erofs:erofs-utils diff:diffutils modinfo:kmod; do
    command -v "${tool%%:*}" >/dev/null || {
        echo "Error: ${tool%%:*} not found: install the ${tool#*:} package" >&2
        exit 1
    }
done

echo "building Arch OS ${VERSION} from ${BIN}"
mkdir -p "$DOWNLOAD_DIR"
unmount_leftovers "${WORK_DIR}"
unmount_leftovers "${PROFILES_DIR}"
${SUDO} rm -rf "${PROFILES_DIR}" "${WORK_DIR}"
# mkarchiso resolves where it works and where it writes before it makes either,
# so what lies above both has to be there.
mkdir -p "${PROFILES_DIR}/out" "${WORK_DIR}"

fetch_theme
[ -d "${PLYMOUTH_THEME_SRC}" ] || { echo "Error: plymouth theme not found in '${PLYMOUTH_THEME_SRC}'" && exit 1; }
# The .plymouth file names the theme. Without it plymouthd has nothing to load.
[ -f "${PLYMOUTH_THEME_SRC}/arch-os.plymouth" ] || { echo "Error: '${PLYMOUTH_THEME_SRC}' is not a plymouth theme" && exit 1; }

# ////////////////////////////////////////////////////////////////////////////
# THE RECOVERY
# ////////////////////////////////////////////////////////////////////////////

# First, because the ISO carries it. How it boots and why it is built this way:
# the Recovery Partition in docs/REFERENCE.md
echo "### Build the Recovery"
cp -r /usr/share/archiso/configs/baseline/. "$RECOVERY_PROFILE"

# baseline is a cloud guest that starts ssh, cloud-init and four hypervisors'
# agents. All of it goes, recovery/ starts the Recovery and a cable's network.
rm -rf "${RECOVERY_PROFILE}/airootfs/etc/systemd/system" \
    "${RECOVERY_PROFILE}/airootfs/etc/systemd/network" \
    "${RECOVERY_PROFILE}/airootfs/etc/systemd/networkd.conf.d" \
    "${RECOVERY_PROFILE}/airootfs/etc/systemd/resolved.conf.d" \
    "${RECOVERY_PROFILE}/airootfs/etc/ssh"

# Its packages, and what makes it a kiosk: the Recovery on tty1, started again
# whenever it ends, with what the Installer left it and no login anywhere.
cp -r recovery/. "$RECOVERY_PROFILE"

install_arch_os "$RECOVERY_PROFILE"

# The seed gives the system's boot entries their tries back with the script
# every installed system has, as many as lib.sh gives them.
install -D -m 755 ../recovery/data/boot/boot-tries.sh "${RECOVERY_PROFILE}/airootfs/usr/local/lib/arch-os/boot-tries.sh"
tries="$(. ../lib.sh && printf '%s' "$BOOT_TRIES")"
mkdir -p "${RECOVERY_PROFILE}/airootfs/etc/systemd/system/arch-os-seed.service.d"
printf '[Service]\nEnvironment=BOOT_TRIES=%s\n' "$tries" >"${RECOVERY_PROFILE}/airootfs/etc/systemd/system/arch-os-seed.service.d/tries.conf"
make_executable "$RECOVERY_PROFILE"
install_bootsplash "$RECOVERY_PROFILE" "Booting Recovery..."
start_on_tty1 "$RECOVERY_PROFILE"
name_image "$RECOVERY_PROFILE" arch-os-recovery

# Without ztailpacking: erofs-utils 1.9.4 wrote ten of linux 7.2.9's modules
# corrupt with it, as the read-back below found.
profiledef "$RECOVERY_PROFILE" 'airootfs_image_type="erofs"' "airootfs_image_tool_options=('-zlzma,109')"

# A key for this build alone, so nothing on the partition starts that it did
# not make. Valid from 1970, for a machine whose clock battery died.
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes \
    -subj "/CN=Arch OS Recovery ${VERSION}" \
    -not_before 19700101000000Z -not_after 99991231235959Z \
    -keyout "${TEMP_DIR}/recovery.key" -out "${TEMP_DIR}/recovery.crt"

# netboot rather than iso: the kernel, the ram disk and the root file system as
# three files, without an ISO around them to be taken apart again.
${SUDO} mkarchiso -v -m netboot -c "${TEMP_DIR}/recovery.crt ${TEMP_DIR}/recovery.key" \
    -w "${WORK_DIR}/recovery" -o "${PROFILES_DIR}/out/recovery" "$RECOVERY_PROFILE"
netboot="${PROFILES_DIR}/out/recovery/arch"

# The Recovery as it ships, before anything is made of it. Its erofs reads back
# as what went in: the signature signs whatever mkfs.erofs wrote.
recovery_root="${WORK_DIR}/recovery/x86_64/airootfs"
[ -d "${recovery_root}/usr/lib/modules" ] || { echo "Error: mkarchiso left no root file system at ${recovery_root}" >&2 && exit 1; }
readback="${WORK_DIR}/recovery-readback"
${SUDO} fsck.erofs --extract="$readback" "${netboot}/x86_64/airootfs.erofs" >/dev/null
compared=0
differs="$(${SUDO} diff -rq --no-dereference "$recovery_root" "$readback")" || compared=$?
case "$compared" in
0) ;;
1)
    printf "Error: the Recovery's erofs does not read back as what was put into it:\n%s\n" "$differs" >&2
    exit 1
    ;;
*)
    echo "Error: diff could not compare the Recovery's erofs with what was put into it" >&2
    exit 1
    ;;
esac
${SUDO} rm -rf "$readback"

# Every command its scripts call is on it, and recovery/pacman.conf took no
# module a repair may load.
for command in arch-chroot blkid blockdev btrfs cryptsetup curl fuser ip iwctl loadkeys localectl lsblk mount mountpoint setfont sha256sum swapoff tar umount; do
    [ -x "${recovery_root}/usr/bin/${command}" ] || { echo "Error: the Recovery has no ${command}" >&2 && exit 1; }
done
# What it starts by itself, as systemd reads the links: the Recovery, a cable's
# network, and the clock HTTPS needs, which a dead battery sets years back.
for unit in arch-os.service systemd-networkd.service systemd-resolved.service systemd-timesyncd.service; do
    ${SUDO} systemctl --root="$recovery_root" is-enabled -q "$unit" || { echo "Error: the Recovery does not start ${unit}" >&2 && exit 1; }
done
modules="$(find "${recovery_root}/usr/lib/modules" -name '*.ko*')"
deps="$(while read -r module; do
    depends="$(modinfo -F depends "$module")" || { echo "Error: modinfo cannot read ${module}" >&2 && exit 1; }
    printf '%s\t%s\n' "$module" "$depends"
done <<<"$modules")"
grep -q $'\t.' <<<"$deps" || { echo "Error: modinfo read no dependencies off ${recovery_root}" >&2 && exit 1; }
lost="$(awk -F'\t' '
    NR == FNR { have[$1] = 1; next }
    {
        n = split($2, dep, ",")
        for (i = 1; i <= n; i++) {
            name = dep[i]; gsub(/-/, "_", name)
            if (name != "" && !(name in have)) { sub(/.*\/kernel\//, "kernel/", $1); print $1 " needs " dep[i]; break }
        }
    }' <(printf '%s\n' "$modules" | sed 's|.*/||; s/\.ko.*//; s/-/_/g') <(printf '%s\n' "$deps"))"
unexpected="$(grep -vE '^kernel/drivers/(accel|media|vfio)/' <<<"$lost" || true)"
if [ -n "$unexpected" ]; then
    printf 'Error: recovery/pacman.conf leaves out what these need:\n%s\n' "$unexpected" >&2
    exit 1
fi

# Found by a UUID made for this build, so no other partition is taken for it.
uuid="$(cat /proc/sys/kernel/random/uuid)"
mkdir -p "${TEMP_DIR}/partition/arch/x86_64"
cp "${netboot}/x86_64/airootfs.erofs" "${netboot}/x86_64/airootfs.erofs.cms.sig" "${TEMP_DIR}/partition/arch/x86_64/"
rm -rf "$RECOVERY_DIR"
mkdir -p "$RECOVERY_DIR"
mkfs.erofs --quiet --all-root -U "$uuid" "${RECOVERY_DIR}/recovery.img" "${TEMP_DIR}/partition"

# Read back as what went into it, as the update writes it to the partition.
fsck.erofs --extract="${TEMP_DIR}/partition-readback" --no-preserve "${RECOVERY_DIR}/recovery.img" >/dev/null
diff -r "${TEMP_DIR}/partition" "${TEMP_DIR}/partition-readback" || {
    echo "Error: recovery.img does not read back as what was put into it" >&2
    exit 1
}

# copytoram frees the disk for the repair. nomodeset draws on the firmware's
# screen, which needs no graphics driver. The boot menu shows its os-release.
cat >"${TEMP_DIR}/os-release" <<EOF
NAME="Arch OS Recovery"
PRETTY_NAME="Arch OS Recovery"
ID=arch-os-recovery
IMAGE_VERSION=${VERSION}
EOF
printf '%s' "archisobasedir=arch archisodevice=UUID=${uuid} copytoram=y cms_verify=y nomodeset ${BOOT_ARGS}" >"${TEMP_DIR}/cmdline"
ukify build \
    --linux="${netboot}/boot/x86_64/vmlinuz-linux" \
    --initrd="${netboot}/boot/x86_64/initramfs-linux.img" \
    --cmdline="@${TEMP_DIR}/cmdline" \
    --os-release="@${TEMP_DIR}/os-release" \
    --output="${RECOVERY_DIR}/recovery.efi"

# Each of its sections read back by its checksum, through ukify's own JSON.
inspected="$(ukify inspect "${RECOVERY_DIR}/recovery.efi" --json=short)"
for pair in ".linux:${netboot}/boot/x86_64/vmlinuz-linux" ".initrd:${netboot}/boot/x86_64/initramfs-linux.img" \
    ".cmdline:${TEMP_DIR}/cmdline" ".osrel:${TEMP_DIR}/os-release"; do
    section="${pair%%:*}" source="${pair#*:}"
    have="$(python3 -c 'import json, sys; print(json.load(sys.stdin)[sys.argv[1]]["sha256"])' "$section" <<<"$inspected")"
    [ "$have" = "$(sha256sum <"$source" | cut -d' ' -f1)" ] || {
        echo "Error: the section ${section} of recovery.efi does not read back as ${source}" >&2
        exit 1
    }
done

du -h "${RECOVERY_DIR}/"*

# ////////////////////////////////////////////////////////////////////////////
# THE ISO
# ////////////////////////////////////////////////////////////////////////////

echo "### Build the ISO"
cp -r /usr/share/archiso/configs/releng/. "$ISO_PROFILE"

# pacstrap refuses the whole list over one name the repositories dropped, so
# that name goes, said out loud.
echo "### Check Packages"
ISO_PACKAGES="${ISO_PROFILE}/packages.x86_64"
DROPPED="$(comm -23 \
    <(grep -v '^[[:space:]]*\(#\|$\)' "$ISO_PACKAGES" | sort -u) \
    <({ pacman -Slq && pacman -Sgq; } | sort -u))"
if [ -n "$DROPPED" ]; then
    echo "not in the repositories, dropped: $(tr '\n' ' ' <<<"$DROPPED")"
    grep -vxF "$DROPPED" "$ISO_PACKAGES" >"${TEMP_DIR}/packages" && mv "${TEMP_DIR}/packages" "$ISO_PACKAGES"
fi

# Without the Recovery beside it, the Installer fetches it: recovery_image in
# lib.sh.
install_arch_os "$ISO_PROFILE"
if [ "$ISO_RECOVERY" = "true" ]; then
    mkdir -p "${ISO_PROFILE}/airootfs/opt/arch-os-recovery"
    cp "${RECOVERY_DIR}/recovery.img" "${RECOVERY_DIR}/recovery.efi" "${ISO_PROFILE}/airootfs/opt/arch-os-recovery/"
fi
make_executable "$ISO_PROFILE"
install_bootsplash "$ISO_PROFILE" "Booting Installer..."
start_on_tty1 "$ISO_PROFILE"

# Networking stays as the Arch ISO ships it.

# The splash and a quiet boot on the entry that starts by itself, the console's
# palette and font on every entry that starts Linux, the screen reader's too.
entries="${ISO_PROFILE}/efiboot/loader/entries"
grep -qs '^linux ' "$entries"/01-archiso-linux*.conf || { echo "Error: releng has no boot entry 01-archiso-linux*.conf to add the boot arguments to" && exit 1; }
for entry in "$entries"/*.conf; do
    grep -q '^linux ' "$entry" || continue
    args="$CONSOLE_ARGS"
    case "${entry##*/}" in 01-archiso-linux*) args="$BOOT_ARGS" ;; esac
    grep -q 'fbcon=nodefer' "$entry" || sed -i "/^options / s/\$/ ${args}/" "$entry"
    grep -q 'fbcon=nodefer' "$entry" || { echo "Error: ${entry} has no options line to add the boot arguments to" && exit 1; }
done
loader="${ISO_PROFILE}/efiboot/loader/loader.conf"
sed -i '/^timeout/d' "$loader"
printf '\ntimeout 0\n' >>"$loader"

# Both say how to get back, before the login and after it. The issue shows the
# cursor again, which the boot hides on every console.
cat >"${ISO_PROFILE}/airootfs/etc/issue" <<'EOF'
\e[?25hArch OS live environment. Type arch-os installer or arch-os recovery to start again.

EOF

cat >"${ISO_PROFILE}/airootfs/etc/motd" <<'EOF'
Arch OS live environment

  arch-os installer    install Arch OS on this machine
  arch-os recovery     repair an Arch OS installation
  iwctl                connect to a wireless network

Add --dry-run to either for a run that changes nothing.

Both keep their answers in /opt/arch-os, so a second run resumes. Their logs
are /opt/arch-os/installer.log and /opt/arch-os/recovery.log.

Reaching this prompt without asking for it means Arch OS stopped on its own:
journalctl -b -u arch-os says why.

EOF

name_image "$ISO_PROFILE" arch-os
profiledef "$ISO_PROFILE" 'iso_application="Arch OS ISO"'

# zstd instead of xz: xz squeezes out a little more and spends minutes of build
# time and seconds of every boot doing it.
profiledef "$ISO_PROFILE" 'airootfs_image_type="squashfs"' \
    "airootfs_image_tool_options=('-comp' 'zstd' '-Xcompression-level' '19' '-b' '1M')"

# UEFI only: the installer's preflight refuses anything else, so a BIOS boot path
# would only offer a boot that ends in a refusal.
profiledef "$ISO_PROFILE" "bootmodes=('uefi.systemd-boot')"

# A volume identifier is at most 32 upper case letters, digits and underscores.
ISO_LABEL="$(printf 'ARCH_OS_%s' "$VERSION" | tr -c '[:alnum:]' '_' | tr '[:lower:]' '[:upper:]' | cut -c1-32)"
profiledef "$ISO_PROFILE" "iso_label=\"${ISO_LABEL}\""

echo "### Make Arch OS ISO"
${SUDO} mkarchiso -v -w "${WORK_DIR}/iso" -o "${PROFILES_DIR}/out/iso" "$ISO_PROFILE"

# ////////////////////////////////////////////////////////////////////////////
# SHIP
# ////////////////////////////////////////////////////////////////////////////

# The ISO goes to DIST_DIR, beside the Recovery, which also becomes one file
# for the release page.
echo "### Ship"
mkdir -p "${DIST_DIR}"
cp -f "${PROFILES_DIR}/out/iso/"*.iso "${DIST_DIR}/"
tar -cf "${RECOVERY_DIR}-x86_64.tar" --owner=0 --group=0 --sort=name -C "${DIST_DIR}" "${RECOVERY_DIR##*/}"

# The tar read back file by file, by the names an update extracts. Not with
# --verify, which flags the owners --owner sets apart (tar 1.35).
for file in recovery.img recovery.efi; do
    tar -xOf "${RECOVERY_DIR}-x86_64.tar" "${RECOVERY_DIR##*/}/${file}" | cmp - "${RECOVERY_DIR}/${file}" || {
        echo "Error: ${RECOVERY_DIR##*/}-x86_64.tar does not read back ${file}" >&2
        exit 1
    }
done
