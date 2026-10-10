#!/bin/bash
# Walks a built ISO the whole way a person does, unattended: installs Arch OS
# onto an empty disk, boots it, rolls it back with the Recovery, boots it again
# and starts the Recovery on its own partition. What smoke.sh proves up to the
# first page, this proves past it. A Desktop is installed and booted only.
#
#   e2e.sh <image.iso> [core|desktop]
#
# The live image is reached over ssh, by the cloud-init the Arch ISO carries;
# the interface runs in tmux there, driven by its keys and read off its pane.
# The installed system unlocks its disk from a systemd credential and is asked
# over ssh, as the account the answers name, and the Recovery on its partition
# is read off the screen. Needs qemu, OVMF, openssh, xorriso and tesseract - see
# README.md.
set -eu

ISO="${1:-}"
START="${2:-core}"
[ -f "$ISO" ] && [[ $START =~ ^(core|desktop)$ ]] || {
    echo "usage: $0 <image.iso> [core|desktop]" >&2
    exit 1
}

# Beside the image, like smoke.sh: the logs of both runs land here, and a failed
# phase keeps a picture of the console it ended on.
WORK="${WORK:-$(dirname "$ISO")/e2e}"

# The Recovery built with the ISO, which a release's ISO does not carry and its
# Installer fetches from a release page that is not out yet while this runs.
# It is handed to the live image where the Installer looks after a download.
RECOVERY_DIR="${ISO%-x86_64.iso}-recovery"

# A cold run on a busy runner, with every package downloaded, and for a Desktop
# three builds from the AUR on top.
INSTALL_TIMEOUT="${INSTALL_TIMEOUT:-$([ "$START" = desktop ] && echo 5400 || echo 2700)}"
BOOT_TIMEOUT="${BOOT_TIMEOUT:-300}"
REPAIR_TIMEOUT="${REPAIR_TIMEOUT:-600}"

OVMF_CODE="${OVMF_CODE:-/usr/share/edk2/x64/OVMF_CODE.secboot.4m.fd}"
OVMF_VARS="${OVMF_VARS:-/usr/share/edk2/x64/OVMF_VARS.4m.fd}"

# What every installation here is given, with everything the Recovery works on:
# an encrypted disk, the chain signed, and its partition. The firmware starts in
# setup mode, so the Installer enrolls the keys and the next boot enforces them.
USERNAME=tux
PASSWORD=e2e-arch-os
DISK=/dev/vda

for tool in qemu-system-x86_64 qemu-img ssh ssh-keygen xorriso setsid tesseract; do
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
        printf 'screendump %s -f png\n' "${WORK}/console.png" >&3 && sleep 2 &&
            echo "the console is in ${WORK}/console.png" >&2
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

# The Recovery on its partition, started the way its launcher on the desktop
# starts it. It has to pass Secure Boot with this machine's keys, find and check
# its partition and open on its menu, in the language the Installer was read in.
recovery_menu() {
    local deadline=$((SECONDS + BOOT_TIMEOUT)) shot="${WORK}/recovery.png"
    as_root systemctl reboot --boot-loader-entry=arch-os-recovery.efi || true
    rm -f "$shot"
    until [ -s "$shot" ] && tesseract "$shot" - --psm 6 2>/dev/null | grep -qE 'Setup|Start'; do
        kill -0 "$QEMU_PID" 2>/dev/null || fail "the machine stopped before the Recovery came up"
        [ "$SECONDS" -lt "$deadline" ] || fail "the Recovery on its partition did not open on its menu within ${BOOT_TIMEOUT}s"
        rm -f "$shot"
        printf 'screendump %s -f png\n' "$shot" >&3
        sleep 10
    done
    say "Recovery: started from its partition, on its menu"
    printf 'quit\n' >&3
    stopped
}

# ////////////////////////////////////////////////////////////////////////////
# THE RUN
# ////////////////////////////////////////////////////////////////////////////

# The answers, shared and then the starting point's own: the Desktop is its
# preset with the SSH server on, which is how this run reaches it.
answers() {
    cat <<EOF
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
ARCH_OS_KERNEL_ARGS=''
ARCH_OS_CORE_TWEAKS_ENABLED='true'
ARCH_OS_CONTAINER_ENGINE='none'
ARCH_OS_FIREWALL_ENABLED='true'
ARCH_OS_SSH_SERVER_ENABLED='true'
ARCH_OS_HOUSEKEEPING_ENABLED='true'
ARCH_OS_EDITOR='nano'
ARCH_OS_VM_HOST_ENABLED='false'
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
ARCH_OS_BACKUP='pika-backup'
ARCH_OS_FLATPAK_ENABLED='true'
ARCH_OS_SAMBA_SHARE_ENABLED='false'
EOF
        ;;
    esac
}

start install
until_ok "$BOOT_TIMEOUT" "ssh into the live image" live true
live systemctl stop arch-os
answers | live "cat >/opt/arch-os/installer.conf"
if ! live test -d /opt/arch-os-recovery; then
    say "Hand over the Recovery, which this ISO does not carry"
    for file in recovery.img recovery.efi; do
        [ -s "${RECOVERY_DIR}/${file}" ] || fail "no ${file} in ${RECOVERY_DIR} for an ISO without the Recovery"
        live "mkdir -p /tmp/arch-os-recovery && cat >/tmp/arch-os-recovery/${file}" <"${RECOVERY_DIR}/${file}"
    done
fi
live "tmux new-session -d -s e2e -x 120 -y 40 'installer --language=en'"

say "Install"
shows "Setup"
keys Enter
shows "Password"
typed "$PASSWORD"
keys Enter
shows "Repeat"
typed "$PASSWORD"
keys Enter
shows "Do you really want to start?"
keys Up Enter
finished installer "$INSTALL_TIMEOUT"
live systemctl poweroff || true
stopped

start disk
healthy

# A Desktop is held to its login screen; the repair is the Core's to prove.
if [ "$START" = desktop ]; then
    [ "$(installed systemctl is-active gdm || true)" = active ] || fail "the login screen of the Desktop is not running"
    say "Desktop: the login screen is up"
    shutdown_installed
    say "Arch OS installs a Desktop and boots it to its login screen"
    exit 0
fi

snapshots="$(as_root snapper --csvout --no-headers list | wc -l)"
[ "$snapshots" -gt 1 ] || fail "the installed system holds no snapshot to go back to"
shutdown_installed

start repair
until_ok "$BOOT_TIMEOUT" "ssh into the live image" live true
live systemctl stop arch-os
live "printf \"ARCH_OS_RECOVERY_KEYMAP='us'\nARCH_OS_RECOVERY_DISK='${DISK}'\n\" >/opt/arch-os/recovery.conf"
live "tmux new-session -d -s e2e -x 120 -y 40 'recovery --language=en'"

say "Repair: go back to the newest snapshot and rebuild the boot files"
shows "Setup"
keys Enter
shows "Encryption password"
typed "$PASSWORD"
keys Enter
# Each text is one only its page shows: the run page lists every step's title.
shows "Newest first"
keys Enter
shows "in place of the system on ${DISK}?"
keys Up Enter
# Opens on Yes after the rollback.
shows "Rebuild the kernel images"
keys Enter
finished recovery "$REPAIR_TIMEOUT"
live systemctl poweroff || true
stopped

start disk
healthy
recovery_menu

say "Arch OS installs, boots, repairs, boots again and starts its Recovery"
