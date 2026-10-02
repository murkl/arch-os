#!/bin/bash
# Walks a built ISO the whole way a person does, unattended: installs Arch OS
# onto an empty disk, boots it, rolls it back with the Recovery and boots it
# again. What smoke.sh proves up to the first page, this proves past it.
#
#   e2e.sh <image.iso>
#
# The live image is reached over ssh, by the cloud-init the Arch ISO carries;
# the interface runs in tmux there, driven by its keys and read off its pane.
# The installed system unlocks its disk from a systemd credential and is asked
# over ssh, as the account the answers name. Needs qemu, OVMF, openssh and
# xorriso - see README.md.
set -eu

ISO="${1:-}"
[ -f "$ISO" ] || {
    echo "usage: $0 <image.iso>" >&2
    exit 1
}

# Beside the image, like smoke.sh: the logs of both runs land here, and a failed
# phase keeps a picture of the console it ended on.
WORK="${WORK:-$(dirname "$ISO")/e2e}"

# A cold run on a busy runner, with every package downloaded.
INSTALL_TIMEOUT="${INSTALL_TIMEOUT:-2700}"
BOOT_TIMEOUT="${BOOT_TIMEOUT:-300}"
REPAIR_TIMEOUT="${REPAIR_TIMEOUT:-600}"

OVMF_CODE="${OVMF_CODE:-/usr/share/edk2/x64/OVMF_CODE.secboot.4m.fd}"
OVMF_VARS="${OVMF_VARS:-/usr/share/edk2/x64/OVMF_VARS.4m.fd}"

# The answers a Core installation takes, with everything the Recovery works on:
# an encrypted disk, the chain signed, and its partition. The firmware starts in
# setup mode, so the Installer enrolls the keys and the next boot enforces them.
USERNAME=tux
PASSWORD=e2e-arch-os
DISK=/dev/vda

for tool in qemu-system-x86_64 qemu-img ssh ssh-keygen xorriso setsid; do
    command -v "$tool" >/dev/null || { echo "Error: ${tool} not found - see README.md" >&2 && exit 1; }
done
[ -f "$OVMF_CODE" ] || { echo "Error: no OVMF firmware at ${OVMF_CODE} - install edk2-ovmf" >&2 && exit 1; }

rm -rf "$WORK"
mkdir -p "$WORK/seed"
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
        printf 'screendump %s\n' "${WORK}/console.ppm" >&3 && sleep 2 &&
            echo "the console is in ${WORK}/console.ppm" >&2
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

# Free ports for ssh and for qemu's monitor, found the way smoke.sh finds one.
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

# The live image takes the key over cloud-init, from a volume labelled cidata.
# Its locale module is switched off: it rewrites /etc/locale.gen.
cat >"${WORK}/seed/user-data" <<EOF
#cloud-config
locale: false
bootcmd:
  - install -d -m 700 /root/.ssh
  - echo '$(cat "${WORK}/key.pub")' >/root/.ssh/authorized_keys
EOF
printf 'instance-id: arch-os-e2e\n' >"${WORK}/seed/meta-data"
xorriso -as mkisofs -quiet -V cidata -J -r -o "${WORK}/seed.iso" "${WORK}/seed/user-data" "${WORK}/seed/meta-data"

qemu-img create -q -f qcow2 "${WORK}/disk.qcow2" 24G

# The machine's own firmware variables, in setup mode until the Installer
# enrolls its keys into them.
cp "$OVMF_VARS" "${WORK}/vars.fd"

LIVE=(-drive "file=${ISO},if=none,id=cd,media=cdrom,readonly=on" -device "ide-cd,drive=cd,bus=ide.0,bootindex=1"
    -drive "file=${WORK}/seed.iso,if=none,id=seed,media=cdrom,readonly=on" -device "ide-cd,drive=seed,bus=ide.1")

# Starts the machine in the background, as one of:
#
#   install   from the ISO, with its own variables
#   repair    from the ISO, with a fresh set: the enrolled keys refuse the ISO
#   disk      from its disk, the disk password handed over as a credential
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
    qemu-system-x86_64 \
        -machine q35,smm=on,accel=kvm:tcg \
        -cpu max \
        -smp 4 \
        -m 4096 \
        -global driver=cfi.pflash01,property=secure,value=on \
        -drive "if=pflash,format=raw,unit=0,readonly=on,file=${OVMF_CODE}" \
        -drive "if=pflash,format=raw,unit=1,file=${vars}" \
        -drive "file=${WORK}/disk.qcow2,if=none,id=disk,format=qcow2" \
        -device "virtio-blk-pci,drive=disk,bootindex=2" \
        "${boot[@]}" \
        -nic "user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:${PORT}-:22" \
        -display none \
        -monitor "tcp:127.0.0.1:${MONITOR},server,nowait" &
    QEMU_PID=$!

    # The monitor is not listening the instant qemu is started.
    local deadline=$((SECONDS + 20))
    until (exec 3<>"/dev/tcp/127.0.0.1/${MONITOR}") 2>/dev/null; do
        [ "$SECONDS" -lt "$deadline" ] || fail "qemu's monitor never came up"
        sleep 0.5
    done
    exec 3<>"/dev/tcp/127.0.0.1/${MONITOR}"
}

# Waits for the machine to switch itself off.
stopped() {
    local deadline=$((SECONDS + 120))
    while kill -0 "$QEMU_PID" 2>/dev/null; do
        [ "$SECONDS" -lt "$deadline" ] || fail "the machine did not switch off"
        sleep 2
    done
    QEMU_PID=""
}

# ////////////////////////////////////////////////////////////////////////////
# TALKING TO IT
# ////////////////////////////////////////////////////////////////////////////

SSH_OPTS=(-q -p "$PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o BatchMode=no)

# The live image, as root by the key.
live() { ssh "${SSH_OPTS[@]}" -i "${WORK}/key" -o BatchMode=yes root@127.0.0.1 "$@"; }

# The installed system, as the account by its password: ssh reads it from an
# askpass program when it has no terminal, and setsid takes the terminal away.
printf '#!/bin/sh\necho %s\n' "$PASSWORD" >"${WORK}/askpass"
chmod +x "${WORK}/askpass"
installed() {
    SSH_ASKPASS="${WORK}/askpass" SSH_ASKPASS_REQUIRE=force setsid -w \
        ssh "${SSH_OPTS[@]}" -o PubkeyAuthentication=no "${USERNAME}@127.0.0.1" "$@" </dev/null
}

# Retries a command until it works, up to a number of seconds.
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

# The interface, in tmux on the live image.
keys() { live tmux send-keys -t e2e "$@"; }
typed() { live tmux send-keys -t e2e -l "$1"; }
pane() { live tmux capture-pane -p -t e2e; }

# Waits for the interface to show a text, then gives it a moment to settle.
shows() {
    local deadline=$((SECONDS + 60))
    until pane | grep -qF -- "$1"; do
        [ "$SECONDS" -lt "$deadline" ] || {
            pane >"${WORK}/pane.log" || true
            fail "the interface never showed \"$1\""
        }
        sleep 1
    done
    sleep 1
}

# Waits for a module's run to end and holds it to its own tests. A task's
# report holds the run on a page of its own until somebody reads it.
finished() {
    local module="$1" seconds="$2" deadline result
    deadline=$((SECONDS + seconds))
    until result="$(live "grep -m1 -E '\\| (INFO \\| run: ok|ERROR \\|)' /opt/arch-os/${module}.log" 2>/dev/null)"; do
        [ "$SECONDS" -lt "$deadline" ] || fail "the ${module} did not finish within ${seconds}s"
        if pane | grep -qF -- "⏎ continue"; then
            keys Enter
        fi
        sleep 10
    done
    live cat "/opt/arch-os/${module}.log" >"${WORK}/${module}.log" || true
    pane >"${WORK}/pane.log" || true
    grep -q 'run: ok' <<<"$result" || fail "the ${module} failed"

    local tally passed total
    tally="$(grep -oE '[0-9]+ of [0-9]+ tests passed' "${WORK}/pane.log" || true)"
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
    state="$(installed systemctl is-system-running --wait || true)"
    [ "$state" = running ] || {
        installed systemctl --failed --no-legend >"${WORK}/failed.log" || true
        fail "the installed system is ${state:-unreachable}, not running"
    }
    as_root bootctl status 2>/dev/null | grep -q 'Secure Boot: enabled' ||
        fail "the installed system did not start with Secure Boot on"
    say "Installed system: running, Secure Boot on"
}

# A command as root on the installed system, through sudo and the password.
as_root() { installed "printf '%s\n' '${PASSWORD}' | sudo -S -p '' $*"; }

shutdown_installed() {
    as_root systemctl poweroff || true
    stopped
}

# ////////////////////////////////////////////////////////////////////////////
# THE RUN
# ////////////////////////////////////////////////////////////////////////////

start install
until_ok "$BOOT_TIMEOUT" "ssh into the live image" live true
live systemctl stop arch-os
live "cat >/opt/arch-os/installer.conf" <<EOF
ARCH_OS_USERNAME='${USERNAME}'
ARCH_OS_HOSTNAME='arch-os-e2e'
ARCH_OS_LOCALE_LANG='en_US'
ARCH_OS_VCONSOLE_KEYMAP='us'
ARCH_OS_VCONSOLE_FONT='auto'
ARCH_OS_TIMEZONE='UTC'
ARCH_OS_REFLECTOR_COUNTRY='auto'
ARCH_OS_DISK='${DISK}'
ARCH_OS_ENCRYPTION_ENABLED='true'
ARCH_OS_SECURE_BOOT_ENABLED='true'
ARCH_OS_RECOVERY_ENABLED='true'
ARCH_OS_BOOTSPLASH_ENABLED='false'
ARCH_OS_KERNEL_ARGS=''
ARCH_OS_CORE_TWEAKS_ENABLED='true'
ARCH_OS_MULTILIB_ENABLED='false'
ARCH_OS_AUR_HELPER_ENABLED='false'
ARCH_OS_CONTAINER_ENGINE='none'
ARCH_OS_FIREWALL_ENABLED='true'
ARCH_OS_SSH_SERVER_ENABLED='true'
ARCH_OS_HOUSEKEEPING_ENABLED='true'
ARCH_OS_EDITOR='nano'
ARCH_OS_SHELL_ENHANCEMENT_ENABLED='false'
ARCH_OS_MANAGER_ENABLED='false'
ARCH_OS_VM_HOST_ENABLED='false'
ARCH_OS_DESKTOP='none'
EOF
live "tmux new-session -d -s e2e -x 120 -y 40 'installer --language=en'"

say "Install"
shows "Install Arch Linux on this machine."
keys Enter
shows "Password"
typed "$PASSWORD"
keys Enter
shows "Repeat"
typed "$PASSWORD"
keys Enter
shows "and install Arch Linux?"
keys Up Enter
finished installer "$INSTALL_TIMEOUT"
live systemctl poweroff || true
stopped

start disk
healthy
snapshots="$(as_root snapper --csvout --no-headers list | wc -l)"
[ "$snapshots" -gt 1 ] || fail "the installed system holds no snapshot to go back to"
shutdown_installed

start repair
until_ok "$BOOT_TIMEOUT" "ssh into the live image" live true
live systemctl stop arch-os
live "printf \"ARCH_OS_RECOVERY_KEYMAP='us'\nARCH_OS_RECOVERY_DISK='${DISK}'\n\" >/opt/arch-os/recovery.conf"
live "tmux new-session -d -s e2e -x 120 -y 40 'recovery --language=en'"

say "Repair: go back to the newest snapshot and rebuild the boot files"
shows "Repair an Arch Linux system"
keys Enter
shows "Encryption password"
typed "$PASSWORD"
keys Enter
shows "Open the system on"
keys Up Enter
shows "Go back to a snapshot"
keys Enter
shows "in place of the system"
keys Up Enter
shows "Rebuild the kernel images"
keys Up Enter
finished recovery "$REPAIR_TIMEOUT"
live systemctl poweroff || true
stopped

start disk
healthy
shutdown_installed

say "Arch OS installs, boots, repairs and boots again"
