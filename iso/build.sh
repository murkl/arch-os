#!/bin/bash
# Builds the Recovery image from `baseline` and the ISO from `releng` around the
# program `make build` built. See README.md.
#
#   build.sh <arch-os> <dist-dir>
set -eu

# ////////////////////////////////////////////////////////////////////////////
# CONFIGURATION
# ////////////////////////////////////////////////////////////////////////////

# Resolved before the cd. Later paths are relative to this script.
[ "$#" -eq 2 ] || {
    echo "usage: $0 <arch-os> <dist-dir>" >&2
    exit 1
}
BIN="$(realpath -m "$1")"
DIST_DIR="$(realpath -m "$2")"
cd "$(dirname "$0")"

# The program's own version, so each image is named after what it ships.
VERSION="$("$BIN" --version 2>/dev/null | awk '$1 == "arch-os" { print $2 }')"
[ -n "$VERSION" ] || {
    echo "Error: ${BIN} reports no version. Run 'make build' first." >&2
    exit 1
}
RECOVERY_DIR="${DIST_DIR}/arch-os-${VERSION}-recovery"

# mkarchiso runs as root. Empty when already root, as in CI.
SUDO=""
[ "$(id -u)" -eq 0 ] || SUDO="sudo"

DOWNLOAD_DIR="./download"

PROFILES_DIR="./archiso"
RECOVERY_PROFILE="${PROFILES_DIR}/recovery"
ISO_PROFILE="${PROFILES_DIR}/iso"

# Outside the repository: a desktop indexer in it holds pacstrap's mounts open
# and fails the build.
WORK_DIR="$(realpath -m "${WORK_DIR:-/var/tmp/arch-os-iso-work}")"

# Pinned, so local and CI builds match. Raised by hand.
PLYMOUTH_THEME_REPO="https://github.com/murkl/plymouth-theme-arch-os"
PLYMOUTH_THEME_REF="b1b784e55b74535afb61f66b85f4c0e916497e4d"

# Console palette by slot and the reason for each boot argument:
# README.md#console. LIVE_ARGS go on every entry that starts Linux.
CONSOLE_RED=46,191,163,235,94,180,136,216,174,191,163,235,69,180,143,236
CONSOLE_GRN=52,97,190,203,129,142,192,222,181,97,190,203,169,142,188,239
CONSOLE_BLU=64,106,140,139,172,173,208,233,195,106,140,139,218,173,187,244
LIVE_ARGS="nomodeset systemd.condition_needs_update=0 fbcon=nodefer vt.default_red=${CONSOLE_RED} vt.default_grn=${CONSOLE_GRN} vt.default_blu=${CONSOLE_BLU}"
BOOT_ARGS="quiet splash loglevel=3 rd.udev.log_level=3 vt.global_cursor_default=0 systemd.show_status=auto plymouth.ignore-serial-consoles ${LIVE_ARGS}"

# Every live boot is a first boot, which starts systemd-firstboot and enables
# what systemd's presets name. Masked, since they cost time for nothing:
#   systemd-firstboot resets the console under the splash, and the image is
#     already configured
#   systemd-nsresourced holds up sysinit on the first user lookup, and nothing
#     here uses a user namespace
#   systemd-pstore moves the installed system's crash records from the
#     firmware into RAM, which loses them at the next start
MASKED_UNITS="systemd-firstboot.service systemd-nsresourced.socket systemd-pstore.service"
# The Recovery also masks the serial getty: no login on any of its consoles.
RECOVERY_MASKED_UNITS="${MASKED_UNITS} serial-getty@.service"

TEMP_DIR="$(mktemp -d)"

# ////////////////////////////////////////////////////////////////////////////
# CLEANUP
# ////////////////////////////////////////////////////////////////////////////

# Mounts left by an interrupted run fail every later run. Deepest first.
unmount_leftovers() {
    findmnt -rno TARGET | grep "^$(realpath -m "$1")/" | sort -r | while read -r target; do
        echo "unmounting leftover: ${target}"
        ${SUDO} umount -l "$target"
    done
}

# Nothing root-owned stays in the checkout. A failed build keeps its profiles,
# owned by the user. The Recovery's signing key goes either way.
cleanup() {
    status=$?
    set +e
    rm -rf "${TEMP_DIR}"
    unmount_leftovers "${WORK_DIR}"
    ${SUDO} rm -rf "${WORK_DIR}"
    if [ "$status" -eq 0 ]; then
        ${SUDO} rm -rf "${PROFILES_DIR}"
    elif [ -d "${PROFILES_DIR}" ]; then
        echo "build failed, profiles kept at ${PROFILES_DIR}"
        ${SUDO} chown -R "$(id -u):$(id -g)" "${PROFILES_DIR}"
    fi
    exit "$status"
}
trap cleanup EXIT

# ////////////////////////////////////////////////////////////////////////////
# WHAT BOTH IMAGES GET
# ////////////////////////////////////////////////////////////////////////////

# Every function here takes the profile to patch as $1.

# mkarchiso sources profiledef.sh, so an appended line wins over the stock one.
profiledef() {
    local profile="$1"
    shift
    printf '\n%s' "$@" >>"${profile}/profiledef.sh"
    echo >>"${profile}/profiledef.sh"
}

# The program holds every module and keeps its answers and log beside it, in
# /opt/arch-os.
install_arch_os() {
    local profile="$1"
    cp -rf airootfs/* "${profile}/airootfs/"
    ./font/build.sh "${profile}/airootfs/usr/share/kbd/consolefonts"
    install -D -m 755 "$BIN" "${profile}/airootfs/opt/arch-os/arch-os"
}

# mkarchiso drops file modes. Run after every program is in place.
make_executable() {
    local file
    for file in "$1/airootfs/opt/arch-os/arch-os" "$1/airootfs/usr/local/bin/"* "$1/airootfs/usr/local/lib/arch-os/"*; do
        [ -e "$file" ] || continue
        profiledef "$1" "file_permissions+=([\"${file#"$1/airootfs"}\"]=\"0:0:755\")"
    done
}

# Vendored, since the AUR package needs makepkg and a build user for a folder of
# PNGs. A checkout at the pinned commit is reused.
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

    # A line under the spinner names what boots. two-step draws SubTitle at
    # TitleVerticalAlignment, otherwise used only by the hidden progress bar.
    sed -i -e 's/^TitleVerticalAlignment=.*/TitleVerticalAlignment=.8/' \
        -e "/^\[boot-up\]$/a SubTitle=$2" "${theme}/arch-os.plymouth"
    if ! grep -qxF "SubTitle=$2" "${theme}/arch-os.plymouth" || ! grep -qxF "TitleVerticalAlignment=.8" "${theme}/arch-os.plymouth"; then
        echo "Error: the theme's arch-os.plymouth has no [boot-up] or TitleVerticalAlignment" >&2
        exit 1
    fi

    # By hand, since plymouth-set-default-theme would theme the build host. It
    # only writes this config and adds the hook.
    mkdir -p "${profile}/airootfs/etc/plymouth"
    printf '[Daemon]\nTheme=arch-os\n' >"${profile}/airootfs/etc/plymouth/plymouthd.conf"

    # After `base udev`, so plymouth owns the console before anything prints.
    [ -f "$hooks" ] || { echo "Error: archiso mkinitcpio config not found at '${hooks}'" && exit 1; }
    grep -q 'plymouth' "$hooks" || sed -i 's/^HOOKS=(\(base [a-z]*\)/HOOKS=(\1 plymouth/' "$hooks"
    grep -q 'plymouth' "$hooks" || { echo "Error: no HOOKS=(base ...) line in '${hooks}' to add plymouth to" && exit 1; }

    # The installed system's drop-in, so a reboot prints nothing over the splash either.
    install -D -m 644 ../installer/tasks/bootloader/data/watchdog.conf "${profile}/airootfs/etc/systemd/system.conf.d/10-arch-os.conf"
}

mask_units() {
    local unit
    mkdir -p "$1/airootfs/etc/systemd/system"
    for unit in $2; do
        ln -sf /dev/null "$1/airootfs/etc/systemd/system/${unit}"
    done
}

# One unit on tty1 instead of autologin, a shell profile and a menu script,
# since the image has one job.
start_on_tty1() {
    mkdir -p "$1/airootfs/etc/systemd/system/multi-user.target.wants"
    ln -sf /etc/systemd/system/arch-os.service \
        "$1/airootfs/etc/systemd/system/multi-user.target.wants/arch-os.service"
}

# Also lands in the image's os-release.
name_image() { profiledef "$1" "iso_name=\"$2\"" "iso_version=\"${VERSION}\""; }

# ////////////////////////////////////////////////////////////////////////////
# BUILD
# ////////////////////////////////////////////////////////////////////////////

echo "### Initialize Build"

# A missing tool fails the build instead of being installed on the host.
for tool in mkarchiso:archiso ukify:systemd-ukify mkfs.erofs:erofs-utils fsck.erofs:erofs-utils unsquashfs:squashfs-tools diff:diffutils modinfo:kmod; do
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
# mkarchiso resolves its work and out directories before creating them, so
# their parents must exist.
mkdir -p "${PROFILES_DIR}/out" "${WORK_DIR}"

fetch_theme
[ -d "${PLYMOUTH_THEME_SRC}" ] || { echo "Error: plymouth theme not found in '${PLYMOUTH_THEME_SRC}'" && exit 1; }
# plymouthd loads a theme by its .plymouth file.
[ -f "${PLYMOUTH_THEME_SRC}/arch-os.plymouth" ] || { echo "Error: '${PLYMOUTH_THEME_SRC}' is not a plymouth theme" && exit 1; }

# ////////////////////////////////////////////////////////////////////////////
# THE RECOVERY
# ////////////////////////////////////////////////////////////////////////////

# First, since the ISO carries it. Background: Recovery Partition in
# docs/REFERENCE.md.
echo "### Build the Recovery"
cp -r /usr/share/archiso/configs/baseline/. "$RECOVERY_PROFILE"

# baseline is a cloud guest with ssh, cloud-init and four hypervisor agents. All
# of it goes. recovery/ starts the Recovery and the wired network.
rm -rf "${RECOVERY_PROFILE}/airootfs/etc/systemd/system" \
    "${RECOVERY_PROFILE}/airootfs/etc/systemd/network" \
    "${RECOVERY_PROFILE}/airootfs/etc/systemd/networkd.conf.d" \
    "${RECOVERY_PROFILE}/airootfs/etc/systemd/resolved.conf.d" \
    "${RECOVERY_PROFILE}/airootfs/etc/ssh"

# Packages and kiosk: the Recovery on tty1, restarted whenever it ends, seeded
# from the EFI partition, no login anywhere.
cp -r recovery/. "$RECOVERY_PROFILE"

# baseline's root has no password. Locked, so a login that turns up opens nothing.
sed -i 's/^root::/root:!*:/' "${RECOVERY_PROFILE}/airootfs/etc/shadow"
grep -q '^root:!\*:' "${RECOVERY_PROFILE}/airootfs/etc/shadow" || { echo "Error: no root line in baseline's /etc/shadow to lock" >&2 && exit 1; }
cp pacman.conf "$RECOVERY_PROFILE/"

install_arch_os "$RECOVERY_PROFILE"

# arch-os-seed resets the tries with the script and BOOT_TRIES of every
# installed system.
install -D -m 755 ../recovery/data/boot-tries.sh "${RECOVERY_PROFILE}/airootfs/usr/local/lib/arch-os/boot-tries.sh"
tries="$(. ../lib.sh && printf '%s' "$BOOT_TRIES")"
mkdir -p "${RECOVERY_PROFILE}/airootfs/etc/systemd/system/arch-os-seed.service.d"
printf '[Service]\nEnvironment=BOOT_TRIES=%s\n' "$tries" >"${RECOVERY_PROFILE}/airootfs/etc/systemd/system/arch-os-seed.service.d/tries.conf"
make_executable "$RECOVERY_PROFILE"
install_bootsplash "$RECOVERY_PROFILE" "Booting Recovery..."
mask_units "$RECOVERY_PROFILE" "$RECOVERY_MASKED_UNITS"
start_on_tty1 "$RECOVERY_PROFILE"
name_image "$RECOVERY_PROFILE" arch-os-recovery

# No ztailpacking: with it, erofs-utils 1.9.4 wrote ten modules of linux 7.2.9
# corrupt, found by the read-back below.
profiledef "$RECOVERY_PROFILE" 'airootfs_image_type="erofs"' "airootfs_image_tool_options=('-zlzma,109')"

# A key per build, so the partition starts only what this build made. Valid from
# 1970 for a dead clock battery.
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes \
    -subj "/CN=Arch OS Recovery ${VERSION}" \
    -not_before 19700101000000Z -not_after 99991231235959Z \
    -keyout "${TEMP_DIR}/recovery.key" -out "${TEMP_DIR}/recovery.crt"

# netboot yields kernel, initramfs and root file system as three files, no ISO
# to unpack.
${SUDO} mkarchiso -v -m netboot -c "${TEMP_DIR}/recovery.crt ${TEMP_DIR}/recovery.key" \
    -w "${WORK_DIR}/recovery" -o "${PROFILES_DIR}/out/recovery" "$RECOVERY_PROFILE"
netboot="${PROFILES_DIR}/out/recovery/arch"

# The erofs must read back as its source, since the signature covers whatever
# mkfs.erofs wrote.
recovery_root="${WORK_DIR}/recovery/x86_64/airootfs"
[ -d "${recovery_root}/usr/lib/modules" ] || { echo "Error: mkarchiso left no root file system at ${recovery_root}" >&2 && exit 1; }
readback="${WORK_DIR}/recovery-readback"
${SUDO} fsck.erofs --extract="$readback" "${netboot}/x86_64/airootfs.erofs" >/dev/null
compared=0
differs="$(${SUDO} diff -rq --no-dereference "$recovery_root" "$readback")" || compared=$?
case "$compared" in
0) ;;
1)
    printf "Error: the Recovery's erofs differs from its source:\n%s\n" "$differs" >&2
    exit 1
    ;;
*)
    echo "Error: diff failed on the Recovery's erofs" >&2
    exit 1
    ;;
esac
${SUDO} rm -rf "$readback"

# Every command the scripts call is present, and pacman.conf removed no module
# a repair may load. The ISO shares kernel and pacman.conf, so this covers it.
for command in arch-chroot blkid blockdev btrfs cryptsetup curl fsck.fat fuser ip iwctl jq loadkeys localectl lsblk mount mountpoint setfont sha256sum swapoff tar umount; do
    [ -x "${recovery_root}/usr/bin/${command}" ] || { echo "Error: the Recovery has no ${command}" >&2 && exit 1; }
done
# Enabled units, as systemd reads the links: the Recovery, the wired network
# and the clock sync HTTPS needs after a dead clock battery.
for unit in arch-os.service systemd-networkd.service systemd-resolved.service systemd-timesyncd.service; do
    ${SUDO} systemctl --root="$recovery_root" is-enabled -q "$unit" || { echo "Error: the Recovery does not start ${unit}" >&2 && exit 1; }
done
${SUDO} grep -q '^root:!\*:' "${recovery_root}/etc/shadow" || { echo "Error: the Recovery's root is not locked" >&2 && exit 1; }
for unit in $RECOVERY_MASKED_UNITS; do
    [ "$(${SUDO} systemctl --root="$recovery_root" is-enabled "$unit")" = masked ] || { echo "Error: the Recovery does not mask ${unit}" >&2 && exit 1; }
done
modules="$(find "${recovery_root}/usr/lib/modules" -name '*.ko*')"
deps="$(while read -r module; do
    depends="$(modinfo -F depends "$module")" || { echo "Error: modinfo cannot read ${module}" >&2 && exit 1; }
    printf '%s\t%s\n' "$module" "$depends"
done <<<"$modules")"
grep -q $'\t.' <<<"$deps" || { echo "Error: modinfo found no dependencies in ${recovery_root}" >&2 && exit 1; }
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
    printf 'Error: pacman.conf leaves out what these need:\n%s\n' "$unexpected" >&2
    exit 1
fi

# Found by a per-build UUID, so no other partition is mistaken for it.
uuid="$(cat /proc/sys/kernel/random/uuid)"
mkdir -p "${TEMP_DIR}/partition/arch/x86_64"
cp "${netboot}/x86_64/airootfs.erofs" "${netboot}/x86_64/airootfs.erofs.cms.sig" "${TEMP_DIR}/partition/arch/x86_64/"
rm -rf "$RECOVERY_DIR"
mkdir -p "$RECOVERY_DIR"
mkfs.erofs --quiet --all-root -U "$uuid" "${RECOVERY_DIR}/recovery.img" "${TEMP_DIR}/partition"

# Read back as the update writes it to the partition.
fsck.erofs --extract="${TEMP_DIR}/partition-readback" --no-preserve "${RECOVERY_DIR}/recovery.img" >/dev/null
diff -r "${TEMP_DIR}/partition" "${TEMP_DIR}/partition-readback" || {
    echo "Error: recovery.img differs from its source" >&2
    exit 1
}

# copytoram frees the disk for the repair. The boot menu shows its os-release.
cat >"${TEMP_DIR}/os-release" <<EOF
NAME="Arch OS Recovery"
PRETTY_NAME="Arch OS Recovery"
ID=arch-os-recovery
IMAGE_VERSION=${VERSION}
EOF
printf '%s' "archisobasedir=arch archisodevice=UUID=${uuid} copytoram=y cms_verify=y ${BOOT_ARGS}" >"${TEMP_DIR}/cmdline"
ukify build \
    --linux="${netboot}/boot/x86_64/vmlinuz-linux" \
    --initrd="${netboot}/boot/x86_64/initramfs-linux.img" \
    --cmdline="@${TEMP_DIR}/cmdline" \
    --os-release="@${TEMP_DIR}/os-release" \
    --output="${RECOVERY_DIR}/recovery.efi"

# Every section read back by checksum, through ukify's JSON.
inspected="$(ukify inspect "${RECOVERY_DIR}/recovery.efi" --json=short)"
for pair in ".linux:${netboot}/boot/x86_64/vmlinuz-linux" ".initrd:${netboot}/boot/x86_64/initramfs-linux.img" \
    ".cmdline:${TEMP_DIR}/cmdline" ".osrel:${TEMP_DIR}/os-release"; do
    section="${pair%%:*}" source="${pair#*:}"
    have="$(python3 -c 'import json, sys; print(json.load(sys.stdin)[sys.argv[1]]["sha256"])' "$section" <<<"$inspected")"
    [ "$have" = "$(sha256sum <"$source" | cut -d' ' -f1)" ] || {
        echo "Error: section ${section} of recovery.efi differs from ${source}" >&2
        exit 1
    }
done

du -h "${RECOVERY_DIR}/"*

# Fits the Recovery partition, RECOVERY_MIB in lib.sh.
room="$(. ../lib.sh && printf '%s' "$((RECOVERY_MIB * 1048576))")"
size="$(stat -c %s "${RECOVERY_DIR}/recovery.img")"
[ "$size" -le "$room" ] || {
    echo "Error: recovery.img takes ${size} bytes, the Recovery partition holds ${room}" >&2
    exit 1
}

# ////////////////////////////////////////////////////////////////////////////
# THE ISO
# ////////////////////////////////////////////////////////////////////////////

echo "### Build the ISO"
cp -r /usr/share/archiso/configs/releng/. "$ISO_PROFILE"

# Arch OS packages instead of releng's rescue kit: the Recovery's, since the ISO
# runs it too, plus packages.x86_64. Both images share pacman.conf.
cat recovery/packages.x86_64 packages.x86_64 >"${ISO_PROFILE}/packages.x86_64"
cp pacman.conf "$ISO_PROFILE/"

# releng's units and files for the dropped packages, and its Memtest86+ entry.
# iwd starts on demand as on the Recovery: wifi_station in lib.sh, iwctl through
# D-Bus.
airootfs="${ISO_PROFILE}/airootfs"
rm -r "${airootfs}/etc/systemd/system/cloud-init.target.wants" \
    "${airootfs}/etc/systemd/system/sockets.target.wants/pcscd.socket" \
    "${airootfs}/usr/local/bin/Installation_guide" \
    "${ISO_PROFILE}/efiboot/loader/entries/03-archiso-memtest86+x64.conf"
for unit in hv_fcopy_daemon hv_kvp_daemon hv_vss_daemon vboxservice vmtoolsd vmware-vmblock-fuse iwd; do
    rm "${airootfs}/etc/systemd/system/multi-user.target.wants/${unit}.service"
done
profiledef "$ISO_PROFILE" "unset 'file_permissions[/usr/local/bin/Installation_guide]'"

# The initramfs without what a USB boot never uses: kms under nomodeset, network
# boot and syslinux's memdisk. zstd -19 unpacks a second faster than xz and
# stays small for the firmware reading it. Checked against releng's line, so a
# new hook stops the build.
hooks="${airootfs}/etc/mkinitcpio.conf.d/archiso.conf"
grep -qxF 'HOOKS=(base udev microcode modconf kms memdisk archiso archiso_loop_mnt archiso_pxe_common archiso_pxe_nbd archiso_pxe_http archiso_pxe_nfs block filesystems keyboard)' "$hooks" || {
    echo "Error: releng's HOOKS in ${hooks} changed" >&2
    exit 1
}
printf '%s\n' 'HOOKS=(base udev microcode modconf archiso archiso_loop_mnt block filesystems keyboard)' \
    'COMPRESSION="zstd"' 'COMPRESSION_OPTIONS=(-19)' >>"$hooks"

# The Installer writes the Recovery to disk from RECOVERY_IMAGE in lib.sh.
install_arch_os "$ISO_PROFILE"
recovery_image="$(. ../lib.sh && printf '%s' "$RECOVERY_IMAGE")"
install -D -m 644 -t "${airootfs}${recovery_image}" "${RECOVERY_DIR}/recovery.img" "${RECOVERY_DIR}/recovery.efi"
make_executable "$ISO_PROFILE"
install_bootsplash "$ISO_PROFILE" "Booting Installer..."
mask_units "$ISO_PROFILE" "$MASKED_UNITS"
start_on_tty1 "$ISO_PROFILE"

# BOOT_ARGS on the default entry, LIVE_ARGS on every other entry that starts
# Linux, the screen reader's too.
entries="${ISO_PROFILE}/efiboot/loader/entries"
grep -qs '^linux ' "$entries"/01-archiso-linux*.conf || { echo "Error: releng has no boot entry 01-archiso-linux*.conf" && exit 1; }
for entry in "$entries"/*.conf; do
    grep -q '^linux ' "$entry" || continue
    args="$LIVE_ARGS"
    case "${entry##*/}" in 01-archiso-linux*) args="$BOOT_ARGS" ;; esac
    grep -q 'fbcon=nodefer' "$entry" || sed -i "/^options / s/\$/ ${args}/" "$entry"
    grep -q 'fbcon=nodefer' "$entry" || { echo "Error: ${entry} has no options line" && exit 1; }
done
loader="${ISO_PROFILE}/efiboot/loader/loader.conf"
sed -i '/^timeout/d' "$loader"
printf '\ntimeout 0\n' >>"$loader"

# issue and motd show how to start again, before and after login. issue shows
# the cursor the boot hides on every console.
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

# zstd, since xz saves little and costs minutes per build and seconds per boot.
profiledef "$ISO_PROFILE" 'airootfs_image_type="squashfs"' \
    "airootfs_image_tool_options=('-comp' 'zstd' '-Xcompression-level' '19' '-b' '1M')"

# UEFI only: the Installer refuses anything else.
profiledef "$ISO_PROFILE" "bootmodes=('uefi.systemd-boot')"

# A volume identifier is at most 32 upper case letters, digits and underscores.
ISO_LABEL="$(printf 'ARCH_OS_%s' "$VERSION" | tr -c '[:alnum:]' '_' | tr '[:lower:]' '[:upper:]' | cut -c1-32)"
profiledef "$ISO_PROFILE" "iso_label=\"${ISO_LABEL}\""

echo "### Make Arch OS ISO"
${SUDO} mkarchiso -v -w "${WORK_DIR}/iso" -o "${PROFILES_DIR}/out/iso" "$ISO_PROFILE"

iso_root="${WORK_DIR}/iso/x86_64/airootfs"

# The squashfs must read back as its source, like the Recovery's erofs.
sfs="${WORK_DIR}/iso/iso/arch/x86_64/airootfs.sfs"
[ -f "$sfs" ] || { echo "Error: mkarchiso left no squashfs at ${sfs}" >&2 && exit 1; }
readback="${WORK_DIR}/iso-readback"
${SUDO} unsquashfs -no-progress -d "$readback" "$sfs" >/dev/null
compared=0
differs="$(${SUDO} diff -rq --no-dereference "$iso_root" "$readback")" || compared=$?
case "$compared" in
0) ;;
1)
    printf "Error: the ISO's squashfs differs from its source:\n%s\n" "$differs" >&2
    exit 1
    ;;
*)
    echo "Error: diff failed on the ISO's squashfs" >&2
    exit 1
    ;;
esac
${SUDO} rm -rf "$readback"

# The commands the Installer calls beyond the Recovery's, root's shell and
# editor, and the data its lists read: glibc's locales and xkb's layouts, which
# pacman.conf must keep. Tested inside the image, where xkb's absolute link
# resolves.
for command in bootctl efibootmgr genfstab mkfs.btrfs mkfs.fat nano pacstrap partprobe reflector sgdisk sshd timedatectl tmux udevadm wipefs zsh; do
    [ -x "${iso_root}/usr/bin/${command}" ] || { echo "Error: the ISO has no ${command}" >&2 && exit 1; }
done
for file in /usr/share/i18n/SUPPORTED /usr/share/X11/xkb/rules/base.lst; do
    ${SUDO} chroot "$iso_root" test -s "$file" || { echo "Error: the ISO has no ${file}" >&2 && exit 1; }
done
# Enabled units: the Installer, the keyring it waits for with the clock sync the
# keyring needs, the network, and sshd for e2e.sh.
for unit in arch-os.service pacman-init.service systemd-time-wait-sync.service systemd-timesyncd.service systemd-networkd.service systemd-resolved.service sshd.service; do
    ${SUDO} systemctl --root="$iso_root" is-enabled -q "$unit" || { echo "Error: the ISO does not start ${unit}" >&2 && exit 1; }
done
for unit in $MASKED_UNITS; do
    [ "$(${SUDO} systemctl --root="$iso_root" is-enabled "$unit")" = masked ] || { echo "Error: the ISO does not mask ${unit}" >&2 && exit 1; }
done
# No releng unit link points into a dropped package.
dangling="$(find "${iso_root}/etc/systemd/system" -type l -printf '%P\t%l\n' | while IFS=$'\t' read -r link target; do
    case "$target" in
    /dev/null) continue ;;
    /*) target="${iso_root}${target}" ;;
    *) target="${iso_root}/etc/systemd/system/$(dirname "$link")/${target}" ;;
    esac
    [ -e "$target" ] || printf '%s ' "$link"
done)"
[ -z "$dangling" ] || { echo "Error: dangling unit links in the ISO: ${dangling}" >&2 && exit 1; }

# ////////////////////////////////////////////////////////////////////////////
# SHIP
# ////////////////////////////////////////////////////////////////////////////

# The Recovery also ships as one tar for the release page.
echo "### Ship"
mkdir -p "${DIST_DIR}"
cp -f "${PROFILES_DIR}/out/iso/"*.iso "${DIST_DIR}/"
tar -cf "${RECOVERY_DIR}-x86_64.tar" --owner=0 --group=0 --sort=name -C "${DIST_DIR}" "${RECOVERY_DIR##*/}"

# Read back file by file, by the names an update extracts. Not --verify, which
# flags the owners --owner sets (tar 1.35).
for file in recovery.img recovery.efi; do
    tar -xOf "${RECOVERY_DIR}-x86_64.tar" "${RECOVERY_DIR##*/}/${file}" | cmp - "${RECOVERY_DIR}/${file}" || {
        echo "Error: ${file} in ${RECOVERY_DIR##*/}-x86_64.tar differs from its source" >&2
        exit 1
    }
done

# GitHub takes no release file of 2 GiB or more.
for file in "${DIST_DIR}/arch-os-${VERSION}-x86_64.iso" "${RECOVERY_DIR}-x86_64.tar"; do
    size="$(stat -c %s "$file")"
    [ "$size" -lt $((2 * 1024 * 1024 * 1024)) ] || {
        echo "Error: ${file##*/} takes ${size} bytes, GitHub release files must stay under 2 GiB" >&2
        exit 1
    }
done
