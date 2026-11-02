#!/bin/bash
# Runs a built ISO end to end, unattended: install, boot, repair, boot again,
# start the Recovery and write it again. See README.md.
#
#   e2e.sh <image.iso> [core|desktop]
set -eu

ISO="${1:-}"
START="${2:-core}"
[ -f "$ISO" ] && [[ $START =~ ^(core|desktop)$ ]] || {
    echo "usage: $0 <image.iso> [core|desktop]" >&2
    exit 1
}

# Beside the image, like smoke.sh. Holds the logs of both runs and, on failure,
# a screenshot of the console.
WORK="${WORK:-$(dirname "$ISO")/e2e}"

# The minimum docs/README.md names for this profile, so every run proves it.
# The disk's is the one the Installer enforces, the accounts the ones it refuses
# as username besides the live system's: lib.sh.
MEMORY="$([ "$START" = desktop ] && echo 4096 || echo 2048)"
DISK_SIZE="$(. "$(dirname "$0")/../../lib.sh" && if [ "$START" = desktop ]; then echo "${DESKTOP_GIB}G"; else echo "${CORE_GIB}G"; fi)"
PACKAGE_ACCOUNTS="$(. "$(dirname "$0")/../../lib.sh" && printf '%s' "$PACKAGE_ACCOUNTS")"

# A cold run on a busy runner downloads every package. A Desktop also builds
# three AUR packages.
INSTALL_TIMEOUT="${INSTALL_TIMEOUT:-$([ "$START" = desktop ] && echo 5400 || echo 2700)}"
BOOT_TIMEOUT="${BOOT_TIMEOUT:-300}"
REPAIR_TIMEOUT="${REPAIR_TIMEOUT:-600}"
# The Recovery download, half a gigabyte through qemu's user network.
UPDATE_TIMEOUT="${UPDATE_TIMEOUT:-1800}"

OVMF_CODE="${OVMF_CODE:-/usr/share/edk2/x64/OVMF_CODE.secboot.4m.fd}"
OVMF_VARS="${OVMF_VARS:-/usr/share/edk2/x64/OVMF_VARS.4m.fd}"

# Every installation gets what the Recovery works on: encryption, a signed boot
# chain and the Recovery partition. The firmware starts in setup mode, so the
# Installer enrolls the keys and the next boot enforces them.
USERNAME=tux
PASSWORD=e2e-arch-os
DISK=/dev/vda

for tool in qemu-system-x86_64 qemu-img ssh ssh-keygen tesseract; do
    command -v "$tool" >/dev/null || { echo "Error: ${tool} not found, see README.md" >&2 && exit 1; }
done
[ -f "$OVMF_CODE" ] || { echo "Error: no OVMF firmware at ${OVMF_CODE}. Install edk2-ovmf." >&2 && exit 1; }

rm -rf "$WORK"
mkdir -p "$WORK"
WORK="$(realpath "$WORK")"

QEMU_PID=""
cleanup() {
    status=$?
    set +e
    [ -n "$QEMU_PID" ] && kill "$QEMU_PID" 2>/dev/null
    exit "$status"
}
trap cleanup EXIT

say() { printf '### %s\n' "$*"; }

fail() {
    echo "Error: $1" >&2
    if [ -n "$QEMU_PID" ] && kill -0 "$QEMU_PID" 2>/dev/null; then
        printf 'screendump %s -f png\n' "${WORK}/console.png" >&3 && sleep 2 &&
            echo "console screenshot: ${WORK}/console.png" >&2
    fi
    for log in "$WORK"/*.log; do
        [ -f "$log" ] || continue
        echo "--- ${log##*/}, last lines:" >&2
        tail -n 40 "$log" | sed 's/^/  | /' >&2
    done
    exit 1
}

# ////////////////////////////////////////////////////////////////////////////
# THE MACHINE
# ////////////////////////////////////////////////////////////////////////////

# Free ports for ssh and qemu's monitor, found as in smoke.sh.
free_port() {
    local candidate
    while true; do
        candidate=$((RANDOM % 20000 + 30000))
        (exec 3<>"/dev/tcp/127.0.0.1/${candidate}") 2>/dev/null || break
    done
    printf '%s' "$candidate"
}
PORT="$(free_port)"
MONITOR="$(free_port)"

ssh-keygen -q -t ed25519 -N '' -C arch-os-e2e -f "${WORK}/key"

qemu-img create -q -f qcow2 "${WORK}/disk.qcow2" "$DISK_SIZE"
qemu-img create -q -f qcow2 "${WORK}/usb.qcow2" 64M

# The machine's own firmware variables, in setup mode until the Installer
# enrolls its keys.
cp "$OVMF_VARS" "${WORK}/vars.fd"

# The live image takes the key as a systemd credential, which systemd-tmpfiles
# writes to root's authorized_keys. https://systemd.io/CREDENTIALS/
LIVE=(-drive "file=${ISO},if=none,id=cd,media=cdrom,readonly=on" -device "ide-cd,drive=cd,bus=ide.0,bootindex=1"
    -smbios "type=11,value=io.systemd.credential:ssh.authorized_keys.root=$(cat "${WORK}/key.pub")")

# A virtio port of every start, where the ISO and the Recovery write their
# trace: runtime/README.md#trace
TRACE="${WORK}/trace"
TRACED=(-device virtio-serial-pci -chardev "file,id=trace,path=${TRACE}"
    -device "virtserialport,chardev=trace,name=arch-os.trace"
    -smbios "type=11,value=io.systemd.credential:arch-os.trace=/dev/virtio-ports/arch-os.trace")

# Starts the machine in the background, as one of:
#
#   install   from the ISO, with its own variables
#   repair    from the ISO, fresh variables: the enrolled keys refuse the ISO
#   disk      from its disk, the disk password as a credential
start() {
    local vars="${WORK}/vars.fd" boot=()
    case "$1" in
    install) boot=("${LIVE[@]}") ;;
    repair)
        vars="${WORK}/vars-repair.fd"
        cp "$OVMF_VARS" "$vars"
        boot=("${LIVE[@]}")
        ;;
    disk) boot=(-smbios "type=11,value=io.systemd.credential:cryptsetup.passphrase=${PASSWORD}") ;;
    esac
    say "Start: $1"
    : >"$TRACE"
    qemu-system-x86_64 \
        -machine q35,smm=on,accel=kvm:tcg \
        -cpu max \
        -smp 4 \
        -m "$MEMORY" \
        -global driver=cfi.pflash01,property=secure,value=on \
        -drive "if=pflash,format=raw,unit=0,readonly=on,file=${OVMF_CODE}" \
        -drive "if=pflash,format=raw,unit=1,file=${vars}" \
        -drive "file=${WORK}/disk.qcow2,if=none,id=disk,format=qcow2" \
        -device "virtio-blk-pci,drive=disk,bootindex=2" \
        -device qemu-xhci \
        "${boot[@]}" \
        "${TRACED[@]}" \
        -nic "user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:${PORT}-:22" \
        -display none \
        -monitor "tcp:127.0.0.1:${MONITOR},server,nowait" &
    QEMU_PID=$!

    # The monitor does not listen right after qemu starts.
    local deadline=$((SECONDS + 20))
    until (exec 3<>"/dev/tcp/127.0.0.1/${MONITOR}") 2>/dev/null; do
        [ "$SECONDS" -lt "$deadline" ] || fail "qemu's monitor never came up"
        sleep 0.5
    done
    exec 3<>"/dev/tcp/127.0.0.1/${MONITOR}"
}

# Waits for the machine to power off.
stopped() {
    local deadline=$((SECONDS + 120))
    while kill -0 "$QEMU_PID" 2>/dev/null; do
        [ "$SECONDS" -lt "$deadline" ] || fail "the machine did not switch off"
        sleep 2
    done
    QEMU_PID=""
}

# Like a power cut, so what a run reported done must already be on disk.
cut_power() {
    printf 'quit\n' >&3
    stopped
}

# ////////////////////////////////////////////////////////////////////////////
# TALKING TO IT
# ////////////////////////////////////////////////////////////////////////////

# A machine that stops answering ends the connection within half a minute.
SSH_OPTS=(-q -p "$PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o BatchMode=yes
    -o ServerAliveInterval=5 -o ServerAliveCountMax=6)

# The live image, as root by key.
live() { ssh "${SSH_OPTS[@]}" -i "${WORK}/key" root@127.0.0.1 "$@"; }

# The installed system, as the account by the key the Installer gave it.
installed() { ssh "${SSH_OPTS[@]}" -i "${WORK}/key" "${USERNAME}@127.0.0.1" "$@" </dev/null; }

# Retries a command until it succeeds, for up to $1 seconds.
until_ok() {
    local seconds="$1" what="$2" deadline
    shift 2
    deadline=$((SECONDS + seconds))
    until "$@" >/dev/null 2>&1; do
        kill -0 "$QEMU_PID" 2>/dev/null || fail "the machine stopped while waiting for ${what}"
        [ "$SECONDS" -lt "$deadline" ] || fail "no ${what} within ${seconds}s"
        sleep 5
    done
}

# The trace of the machine's interface on tty1, and of the one in tmux on the
# live image.
LIVE_TRACE=/run/arch-os-e2e.trace
on_tty1() { cat "$TRACE"; }
in_tmux() { live cat "$LIVE_TRACE"; }

# Whether a trace line from line $1 on matches the pattern, the whole line. $3
# reads the trace, on_tty1 by default.
traced() {
    local from="$1" pattern="$2" read="${3:-on_tty1}"
    "$read" | tail -n +"$from" | grep -qE "^(${pattern})\$"
}

# Waits up to $3 seconds for a trace line from line $1 on, see traced.
await() {
    local from="$1" pattern="$2" read="${4:-on_tty1}" deadline=$((SECONDS + $3))
    until traced "$from" "$pattern" "$read"; do
        kill -0 "$QEMU_PID" 2>/dev/null || fail "the machine stopped while waiting for ${pattern}"
        [ "$SECONDS" -lt "$deadline" ] || return 1
        sleep 2
    done
}

# Lines of the tty1 trace so far, so a wait sees only what follows.
lines() { wc -l <"$TRACE"; }

# Row under the cursor, the last focus line of a trace.
focused() { "${1:-on_tty1}" | grep '^focus ' | tail -n 1 | cut -d' ' -f2-; }

keys() { live tmux send-keys -t e2e "$@"; }
typed() { live tmux send-keys -t e2e -l "$1"; }
pane() { live tmux capture-pane -p -t e2e; }

# Waits up to $2 seconds for the interface in tmux to trace the pattern.
shows() {
    await 1 "$1" "$2" in_tmux || {
        pane >"${WORK}/pane.log" || true
        live cat /opt/arch-os/recovery.log >"${WORK}/recovery.log" || true
        fail "the interface never traced ${1} within ${2}s"
    }
}

# Moves the cursor in tmux down until the trace says it is on row $1.
focus() {
    for _ in $(seq 40); do
        [ "$(focused in_tmux)" = "$1" ] && return 0
        keys Down
        sleep 0.5
    done
    fail "no row ${1} to put the cursor on"
}

# Runs a module unattended on the live image, passwords in its environment, and
# requires all its tests to pass.
unattended() {
    local module="$1" seconds="$2" status=0 tally passed total
    shift 2
    timeout "$seconds" ssh "${SSH_OPTS[@]}" -i "${WORK}/key" root@127.0.0.1 \
        "env $* arch-os ${module} --unattended" >"${WORK}/${module}.out" 2>&1 || status=$?
    live cat "/opt/arch-os/${module}.log" >"${WORK}/${module}.log" || true
    case "$status" in
    0) ;;
    124) fail "the ${module} did not finish within ${seconds}s" ;;
    *) fail "the ${module} failed, see ${WORK}/${module}.out" ;;
    esac
    # Online and on a clean disk, not even an optional task may fail.
    if grep -q ' WARN ' "${WORK}/${module}.log"; then
        fail "the ${module} finished with a warning, see ${WORK}/${module}.log"
    fi
    tally="$(grep -oE '[0-9]+ of [0-9]+ tests passed' "${WORK}/${module}.out" || true)"
    read -r passed _ total _ <<<"$tally"
    if [ -z "$tally" ] || [ "$passed" != "$total" ]; then
        fail "the ${module} finished with ${tally:-no tally of its tests}"
    fi
    say "${module}: ${tally}"
}

# The installed system is up, unlocked, signed and running clean.
healthy() {
    until_ok "$BOOT_TIMEOUT" "login to the installed system" installed true
    local state
    # Bounded, since a job that never ends holds --wait forever.
    state="$(installed timeout "$BOOT_TIMEOUT" systemctl is-system-running --wait || true)"
    [ "$state" = running ] || {
        installed systemctl --failed --no-legend >"${WORK}/failed.log" || true
        installed systemctl list-jobs --no-legend >>"${WORK}/failed.log" || true
        fail "the installed system is ${state:-still starting after ${BOOT_TIMEOUT}s}, not running"
    }
    as_root bootctl status 2>/dev/null | grep -q 'Secure Boot: enabled' ||
        fail "the installed system did not start with Secure Boot on"
    [ "$(installed cat /proc/sys/kernel/panic)" = 10 ] ||
        fail "the installed system does not restart after a kernel panic"
    [ "$(installed systemctl show -p RebootWatchdogUSec --value)" = 0 ] ||
        fail "the installed system arms the watchdog for a reboot, whose message prints over the splash"
    as_root journalctl -b -o cat -u "'systemd-fsck@*'" | grep -q '^fsck\.fat ' ||
        fail "the installed system did not check its EFI partition at boot"
    say "Installed system: running, Secure Boot on, restarts after a panic, reboots without the watchdog, checked its EFI partition"
}

# A command as root on the installed system, through sudo and the password.
as_root() { installed "printf '%s\n' '${PASSWORD}' | sudo -S -p '' $*"; }

# systemd-oomd watches a cgroup for swap and the user manager for memory
# pressure, per its two drop-ins. Section names as oomctl prints them,
# src/oom/oomd-manager.c.
oomd_watches() {
    as_root oomctl | awk '
        /^Swap Monitored CGroups:/ { section = "swap"; next }
        /^Memory Pressure Monitored CGroups:/ { section = "pressure"; next }
        section == "swap" && /Path: / { swap = 1 }
        section == "pressure" && /Path: .*\/user@[0-9]+\.service$/ { pressure = 1 }
        END { exit !(swap && pressure) }'
}

# A SATA disk in a USB enclosure on the port start() adds. ata_id reports such a
# disk as ID_BUS=ata, which qemu's usb-storage cannot, so a rule between 60 and
# 70 sets it.
usb_writeback() {
    local rule='SUBSYSTEM=="block", SUBSYSTEMS=="usb", ENV{ID_BUS}="ata"' disk limits
    # In base64, so no shell on the way reads the rule's quotes.
    as_root "sh -c 'echo $(base64 -w0 <<<"$rule") | base64 -d >/etc/udev/rules.d/65-e2e-enclosure.rules'"
    as_root udevadm control --reload
    printf 'drive_add 0 file=%s,if=none,id=usb,format=qcow2\n' "${WORK}/usb.qcow2" >&3
    printf 'device_add usb-storage,drive=usb,id=usb-disk\n' >&3
    until_ok 60 "USB disk in the installed system" usb_disk
    disk="$(usb_disk)"
    as_root udevadm settle --timeout=30
    installed udevadm info --query=property --name="/dev/${disk}" | grep -qx 'ID_BUS=ata' ||
        fail "the stand-in rule did not report the USB disk as ata"
    limits="$(installed cat "/sys/block/${disk}/bdi/strict_limit" "/sys/block/${disk}/bdi/max_ratio")"
    [ "$limits" = $'1\n10' ] || fail "a SATA disk in a USB enclosure keeps the kernel's writeback: ${limits//$'\n'/ }"
    printf 'device_del usb-disk\n' >&3
    as_root rm /etc/udev/rules.d/65-e2e-enclosure.rules
    say "Installed system: a SATA disk in a USB enclosure writes at a tenth of the dirty limit"
}

# The USB disk's name in the installed system.
usb_disk() { installed lsblk -dno NAME,TRAN | awk '$2 == "usb" { print $1; found = 1 } END { exit !found }'; }

shutdown_installed() {
    as_root systemctl poweroff || true
    stopped
}

# The boot came from entry $1, and both entries have their tries back, which any
# good start restores.
entries_ready() {
    local status listed name
    status="$(as_root bootctl status 2>/dev/null || true)"
    grep -qE "Current Entry: ${1//./\\.}\$" <<<"$status" ||
        fail "the installed system did not start from ${1}: $(grep 'Current Entry' <<<"$status")"
    listed="$(as_root ls /boot/loader/entries)"
    for name in main main-fallback; do
        grep -qx "${name}+3.conf" <<<"$listed" || fail "${name} did not get its tries back: ${listed//$'\n'/ }"
    done
    say "Installed system: started from ${1}, both entries counted again"
}

# Uses up the tries of the entries named, as three failed starts do.
used_up() {
    local name
    for name in "$@"; do
        as_root mv "/boot/loader/entries/${name}+3.conf" "/boot/loader/entries/${name}+0-3.conf"
    done
}

# Lays the installation out with UKIs in EFI/Linux, started as the loader
# default, and no counted entries.
images_in_efi_linux() {
    live bash -s <<EOF
set -euo pipefail
printf '%s' '${PASSWORD}' | cryptsetup open ${DISK}2 e2e-old
mount -t btrfs -o subvol=@ /dev/mapper/e2e-old /mnt
mount -t vfat ${DISK}1 /mnt/boot
sed -i 's|/boot/EFI/arch-os/|/boot/EFI/Linux/|' /mnt/etc/mkinitcpio.d/linux-zen.preset
for name in arch-linux-zen arch-linux-zen-fallback; do
    mv "/mnt/boot/EFI/arch-os/\${name}.efi" "/mnt/boot/EFI/Linux/\${name}.efi"
done
rm -f /mnt/boot/loader/entries/main*.conf
printf 'default arch-linux-zen.efi\nconsole-mode auto\ntimeout 0\neditor no\n' >/mnt/boot/loader/loader.conf
arch-chroot /mnt systemctl disable arch-os-boot-tries.service
rm -f /mnt/etc/systemd/system/arch-os-boot-tries.service /mnt/usr/local/lib/arch-os/boot-tries.sh
umount -R /mnt
cryptsetup close e2e-old
EOF
    say "Laid the installation out with its images in EFI/Linux"
}

# A subvolume inside @ after its newest snapshot, as machinectl makes one. No
# snapshot holds it, so a rollback must keep it.
nested_subvolume() {
    live bash -s <<EOF
set -euo pipefail
printf '%s' '${PASSWORD}' | cryptsetup open ${DISK}2 e2e-nested
mount -t btrfs -o subvol=@ /dev/mapper/e2e-nested /mnt
btrfs subvolume create /mnt/var/lib/machines/e2e
echo kept >/mnt/var/lib/machines/e2e/kept
umount /mnt
cryptsetup close e2e-nested
EOF
    say "Made a subvolume inside the system"
}

# Marks the EFI partition as not cleanly unmounted, at the FAT32 dirty flag, as a
# start broken during a write leaves it. The repair checks it before writing.
esp_dirty() {
    live "printf '\\001' | dd of=${DISK}1 bs=1 seek=65 count=1 conv=notrunc,fsync status=none"
    say "Marked the EFI partition as not cleanly unmounted"
}

# Removes the loader from the EFI partition, as a full partition or a cleaning
# firmware does. The rebuild must restore it.
loader_gone() {
    live bash -s <<EOF
set -euo pipefail
mount -t vfat ${DISK}1 /mnt
rm /mnt/EFI/systemd/systemd-bootx64.efi /mnt/EFI/BOOT/BOOTX64.EFI
umount /mnt
EOF
    say "Took the boot loader off the EFI partition"
}

# Exit 0 where GitHub holds a Recovery of the image's series with its checksum,
# which an update from the ISO installs, 1 where it holds none.
published_in_series() {
    live bash -s <<'EOF'
set -euo pipefail
series="$(arch-os --version | awk '$1 == "arch-os" { split($2, v, "."); print v[1] }')"
json="$(curl -fsS --proto '=https' --tlsv1.2 --max-time 30 'https://api.github.com/repos/murkl/arch-os/releases?per_page=100')"
jq -e --arg pattern "^arch-os-${series}\\.[0-9]+\\.[0-9]+-recovery-x86_64\\.tar$" \
    '[.[].assets[]? | select((.name | test($pattern)) and .digest != null)] | length > 0' <<<"$json" >/dev/null
EOF
}

# Waits for the dashboard of the Recovery partition: past Secure Boot with this
# machine's keys, its partition found and checked, in the Installer's language.
recovery_opens() {
    local from
    from="$(lines)"
    await "$from" "page dashboard" "$BOOT_TIMEOUT" ||
        fail "the Recovery on its partition did not open on its dashboard within ${BOOT_TIMEOUT}s"
    traced "$from" "language en" || fail "the Recovery did not open in the Installer's language"
    say "Recovery: started ${1}, on its first page"
}

# Waits for the language page of a published Recovery, which reads no language
# the Installer left. One without --trace shows the catalogs' names for
# themselves, which OCR finds.
published_recovery_opens() {
    local from deadline=$((SECONDS + BOOT_TIMEOUT)) shot="${WORK}/recovery.png"
    from="$(lines)"
    until traced "$from" "page language"; do
        kill -0 "$QEMU_PID" 2>/dev/null || fail "the machine stopped before the Recovery came up"
        [ "$SECONDS" -lt "$deadline" ] || fail "the published Recovery did not open on its language page within ${BOOT_TIMEOUT}s"
        rm -f "$shot"
        printf 'screendump %s -f png\n' "$shot" >&3
        sleep 10
        [ -s "$shot" ] && tesseract "$shot" - --psm 6 2>/dev/null | grep -qE 'English|Deutsch' && break
    done
    say "Recovery: started ${1}, on its first page"
}

# The Recovery partition, started as its desktop launcher does, then left with
# Start over.
recovery_dashboard() {
    local deadline shot="${WORK}/recovery.png"
    as_root systemctl reboot --boot-loader-entry=arch-os-recovery.efi || true
    recovery_opens "by the boot loader"

    # Start over is the exit row of the page q opens. Screenshots often enough
    # to catch a login flashing by, getty's word rather than one of the
    # interface. Back within seconds, unlike a reboot.
    local frame=0 text from
    from="$(lines)"
    printf 'sendkey q\n' >&3
    await "$from" "page leave" 10 || fail "q did not open the leave page"
    for _ in $(seq 10); do
        [ "$(focused)" = exit ] && break
        printf 'sendkey down\n' >&3
        sleep 0.5
    done
    from="$(lines)"
    printf 'sendkey ret\n' >&3
    deadline=$((SECONDS + 15))
    until traced "$from" "page dashboard"; do
        [ "$SECONDS" -lt "$deadline" ] || fail "the Recovery did not come back on its dashboard within 15s of Start over"
        frame=$((frame + 1))
        shot="${WORK}/recovery-exit-${frame}.png"
        printf 'screendump %s -f png\n' "$shot" >&3
        sleep 0.5
        [ -s "$shot" ] || continue
        text="$(tesseract "$shot" - --psm 6 2>/dev/null || true)"
        grep -qi 'login' <<<"$text" && fail "leaving the Recovery showed a login, see ${shot}"
        rm -f "$shot"
    done
    rm -f "${WORK}"/recovery-exit-*.png
    say "Recovery: Start over restarts it without a login"

    cut_power
}

# ////////////////////////////////////////////////////////////////////////////
# THE RUN
# ////////////////////////////////////////////////////////////////////////////

# Shared answers, then the profile's. The Desktop is its preset plus the SSH
# server, which this run connects through.
answers() {
    cat <<EOF
MODULE_LANGUAGE='en'
ARCH_OS_USERNAME='${USERNAME}'
ARCH_OS_HOSTNAME='arch-os-e2e'
ARCH_OS_LOCALE_LANG='en_US'
ARCH_OS_VCONSOLE_KEYMAP='us'
ARCH_OS_VCONSOLE_FONT='auto'
ARCH_OS_TIMEZONE='UTC'
ARCH_OS_REFLECTOR_COUNTRY='none'
ARCH_OS_DISK='${DISK}'
ARCH_OS_ENCRYPTION_ENABLED='true'
ARCH_OS_SECURE_BOOT_ENABLED='true'
ARCH_OS_RECOVERY_ENABLED='true'
ARCH_OS_KERNEL_ARGS=''
ARCH_OS_CORE_TWEAKS_ENABLED='true'
ARCH_OS_CONTAINER_ENGINE='none'
ARCH_OS_FIREWALL_ENABLED='true'
ARCH_OS_SSH_SERVER_ENABLED='true'
ARCH_OS_SSH_KEY='$(cat "${WORK}/key.pub")'
ARCH_OS_HOUSEKEEPING_ENABLED='true'
ARCH_OS_EDITOR='nano'
EOF
    case "$START" in
    core)
        cat <<EOF
ARCH_OS_BOOTSPLASH_ENABLED='false'
ARCH_OS_MULTILIB_ENABLED='false'
ARCH_OS_AUR_HELPER_ENABLED='false'
ARCH_OS_SHELL_ENHANCEMENT_ENABLED='false'
ARCH_OS_MANAGER_ENABLED='false'
ARCH_OS_DESKTOP='none'
EOF
        ;;
    desktop)
        cat <<EOF
ARCH_OS_BOOTSPLASH_ENABLED='true'
ARCH_OS_MULTILIB_ENABLED='true'
ARCH_OS_AUR_HELPER_ENABLED='true'
ARCH_OS_SHELL_ENHANCEMENT_ENABLED='true'
ARCH_OS_MANAGER_ENABLED='true'
ARCH_OS_DESKTOP='gnome'
ARCH_OS_DESKTOP_EXTRAS_ENABLED='true'
ARCH_OS_DESKTOP_SLIM_ENABLED='true'
ARCH_OS_BROWSER='firefox'
ARCH_OS_BACKUP='deja-dup'
ARCH_OS_FLATPAK_ENABLED='true'
ARCH_OS_BAZAAR_ENABLED='false'
ARCH_OS_SAMBA_SHARE_ENABLED='false'
EOF
        ;;
    esac
}

start install
until_ok "$BOOT_TIMEOUT" "ssh into the live image" live true
live systemctl stop arch-os
live "getent passwd; getent group" | cut -d: -f1 | sort -u >"${WORK}/live-accounts"
answers | live "cat >/opt/arch-os/installer.conf"

say "Install"
unattended installer "$INSTALL_TIMEOUT" "ARCH_OS_PASSWORD='${PASSWORD}'"

# The Recovery's firmware entry as next boot: the way in from the firmware's
# boot menu when the loader's menu never shows.
if [ "$START" = core ]; then
    entries="$(live efibootmgr)"
    entry="$(awk '!found && /^Boot[0-9A-Fa-f]/ && index($0, "Arch OS Recovery") { print substr($1, 5, 4); found = 1 }' <<<"$entries")"
    [ -n "$entry" ] || fail "no firmware entry for the Recovery"
    live efibootmgr -q --bootnext "$entry"
fi
cut_power

if [ "$START" = core ]; then
    start disk
    recovery_opens "by its firmware entry"
    cut_power
fi

start disk
healthy
usb_writeback

# A Desktop must reach its login screen, and a start counts as good only once
# the session in front is up: the autologin session, then without autologin the
# login screen's. The Core run proves the repair.
if [ "$START" = desktop ]; then
    [ "$(installed systemctl is-active gdm || true)" = active ] || fail "the login screen of the Desktop is not running"
    entries_ready main.conf
    say "Desktop: the session it logs into counted the start"

    # Every account a package of the Desktop creates is one the Installer refuses
    # as username.
    taken="$(installed "cat /usr/lib/sysusers.d/*.conf" | awk '$1 ~ /^[ug]!?$/ { print $2 }' | sort -u |
        grep -vxF -f "${WORK}/live-accounts" | grep -vxF -f <(tr ' ' '\n' <<<"$PACKAGE_ACCOUNTS") || true)"
    [ -z "$taken" ] || fail "the Installer takes a username a package claims: ${taken//$'\n'/ }, see PACKAGE_ACCOUNTS in lib.sh"
    say "Desktop: every account a package creates is refused as username"

    until_ok "$BOOT_TIMEOUT" "systemd-oomd watching swap and the session" oomd_watches
    say "Desktop: systemd-oomd watches swap and the session"

    # No session comes up: the shell masked for every user, the wait shortened.
    as_root systemctl --global mask org.gnome.Shell@.service
    as_root "sh -c 'mkdir -p /etc/systemd/system/arch-os-session-up.service.d && printf \"[Service]\\nExecStart=\\nExecStart=/usr/local/lib/arch-os/session-up.sh 30\\n\" >/etc/systemd/system/arch-os-session-up.service.d/e2e.conf'"
    shutdown_installed
    start disk
    until_ok "$BOOT_TIMEOUT" "the wait for a session to give up" as_root systemctl is-failed --quiet arch-os-session-up.service
    left="$(as_root ls /boot/loader/entries)"
    grep -qx 'main+2-1.conf' <<<"$left" || fail "a start without a session counted as good: ${left//$'\n'/ }"
    say "Desktop: a start without a session keeps its try taken"

    as_root systemctl --global unmask org.gnome.Shell@.service
    as_root rm -r /etc/systemd/system/arch-os-session-up.service.d /etc/gdm/custom.conf
    shutdown_installed
    start disk
    healthy
    entries_ready main.conf
    say "Desktop: the login screen counted the start"
    shutdown_installed
    say "Arch OS installs a Desktop and boots it to its login screen"
    exit 0
fi

entries_ready main.conf
snapshots="$(as_root snapper --csvout --no-headers list | wc -l)"
[ "$snapshots" -gt 1 ] || fail "the installed system holds no snapshot to go back to"
newest="$(as_root snapper --csvout --no-headers list --columns number | tail -n1)"
[ -n "$newest" ] || fail "the installed system names no newest snapshot"

# Its entry used up, the system starts from its fallback.
used_up main
shutdown_installed
start disk
healthy
entries_ready main-fallback.conf

# Both used up, the Recovery starts by itself and restores their tries.
used_up main main-fallback
shutdown_installed
start disk
recovery_opens "after the system used up every try"
cut_power
start disk
healthy
entries_ready main.conf
shutdown_installed

start repair
until_ok "$BOOT_TIMEOUT" "ssh into the live image" live true
live systemctl stop arch-os
images_in_efi_linux
nested_subvolume
loader_gone
esp_dirty
live "printf \"MODULE_LANGUAGE='en'\nARCH_OS_RECOVERY_KEYMAP='us'\nARCH_OS_RECOVERY_DISK='${DISK}'\n\" >/opt/arch-os/recovery.conf"

say "Repair: go back to the newest snapshot and rebuild the boot files"
unattended recovery "$REPAIR_TIMEOUT" \
    "ARCH_OS_RECOVERY_PASSWORD='${PASSWORD}' ARCH_OS_RECOVERY_SNAPSHOT='@snapshots/${newest}/snapshot'"
grep -q 'removing dirty bit' "${WORK}/recovery.log" || fail "the repair wrote to the EFI partition unchecked"
say "Repair: checked the EFI partition before writing to it"
cut_power

start disk
healthy
entries_ready main.conf
as_root test -f /boot/EFI/arch-os/arch-linux-zen.efi || fail "the repair left no unified image in /boot/EFI/arch-os"
if as_root test -e /boot/EFI/Linux/arch-linux-zen.efi; then
    fail "the repair left an image in EFI/Linux, where the loader lists it twice"
fi
say "Repair: laid the installation out as the Installer does"
[ "$(as_root cat /var/lib/machines/e2e/kept)" = kept ] || fail "the rollback lost the subvolume made inside the system"
say "Repair: kept the subvolume made inside the system"
as_root snapper --no-headers list --columns description | grep -qx ' *rollback backup *' ||
    fail "the rollback kept no snapshot of the system it replaced"
say "Repair: kept the replaced system as a snapshot"
recovery_dashboard

# An interrupted update leaves a partition whose UUID the boot image no longer
# names. Secure Boot is off on the ISO, and the system's keys sign the result.
start repair
until_ok "$BOOT_TIMEOUT" "ssh into the live image" live true
live systemctl stop arch-os
live dd if=/dev/urandom of="${DISK}3" bs=1M count=8 conv=fsync status=none
live "printf \"MODULE_LANGUAGE='en'\nARCH_OS_RECOVERY_KEYMAP='us'\nARCH_OS_RECOVERY_DISK='${DISK}'\n\" >/opt/arch-os/recovery.conf"
live "tmux new-session -d -s e2e -x 120 -y 40 'arch-os recovery --trace ${LIVE_TRACE}'"

say "Update: write the Recovery again from the ISO"
shows "page dashboard" 60
focus update
keys Enter
shows "page password ARCH_OS_RECOVERY_UPDATE_PASSWORD|page report update" 120
if traced 1 "page report update" in_tmux; then
    # No Recovery published for this series yet, as for a new major version. The
    # live image asks GitHub itself, so a broken lookup cannot pass as that.
    status=0
    published_in_series || status=$?
    case "$status" in
    0) fail "the update found no Recovery, though GitHub holds one of this series" ;;
    1) ;;
    *) fail "GitHub did not say whether a Recovery of this series is published" ;;
    esac
    say "Update: skipped, no Recovery published for this series"
    exit 0
fi
typed "$PASSWORD"
keys Enter
shows "page confirm update-install" 60
focus yes
keys Enter
shows "page report update-install|page (stopped|failure) update-install" "$UPDATE_TIMEOUT"
traced 1 "page report update-install" in_tmux || {
    live cat /opt/arch-os/recovery.log >"${WORK}/recovery.log" || true
    pane >"${WORK}/pane.log" || true
    fail "the Recovery was not written again, see ${WORK}/recovery.log"
}
cut_power

start disk
healthy
uuid="$(as_root blkid -p -s UUID -o value "${DISK}3")"
as_root bootctl list --json=short | grep -qF "archisodevice=UUID=${uuid} " ||
    fail "the Recovery's boot image does not name its partition"
as_root sbctl verify 2>/dev/null | grep -qF "/boot/EFI/Linux/arch-os-recovery.efi is signed" ||
    fail "the Recovery written from the ISO is not signed"
as_root systemctl reboot --boot-loader-entry=arch-os-recovery.efi || true
# The newest release may predate this Installer and not read its language. Its
# language page, listing Deutsch, also counts as started.
published_recovery_opens "after it was written again from the ISO"
cut_power

say "Arch OS installs, boots, repairs, boots again, starts its Recovery and writes it again"
