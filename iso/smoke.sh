#!/bin/bash
# Boots a built Arch OS image and waits for the installer to come up in it.
#
# Nothing is installed: the machine is switched off the moment the installer's
# first page is recognised on its console. What that proves is the whole chain
# no linter can see — the boot entry, the initramfs and its plymouth hook, the
# systemd unit on tty1, the runtime, and the installer tree it loads. An image
# that fails here is one that would have failed on somebody's hardware.
#
# Takes the image as its one argument; `make smoke` hands it the newest build.
# Needs qemu, OVMF and tesseract — see README.md.
set -e

ISO="$1"
[ -f "$ISO" ] || { echo "usage: $0 <image.iso>" >&2 && exit 1; }

# Where the console is photographed. A failure keeps every frame, because a
# picture of the screen is the only thing there is to go on afterwards; a run
# that worked keeps the one frame the installer was recognised in and nothing
# else.
FRAME_DIR="${FRAME_DIR:-./smoke}"

# How long the image gets, and how often it is looked at. The slow case is a
# cold boot under emulation with no KVM to fall back on, and five minutes
# covers it with room to spare.
TIMEOUT="${TIMEOUT:-300}"
INTERVAL="${INTERVAL:-15}"

OVMF_CODE="${OVMF_CODE:-/usr/share/edk2/x64/OVMF_CODE.4m.fd}"
OVMF_VARS="${OVMF_VARS:-/usr/share/edk2/x64/OVMF_VARS.4m.fd}"

# The installer's first page after the splash, as the console spells it. Two
# strings rather than one: a console font read back through OCR loses a letter
# now and again, and the page is recognised as long as either survives intact.
EXPECT='Interface language|Choose the language for this installer'

# Read off the same screen: a machine that got this far and no further says so
# in plain words, and there is no reason to sit out the timeout for it.
PANIC='Kernel panic|Failed to start'

for tool in qemu-system-x86_64 tesseract; do
    command -v "$tool" >/dev/null || { echo "Error: ${tool} not found — see README.md" >&2 && exit 1; }
done
[ -f "$OVMF_CODE" ] || { echo "Error: no OVMF firmware at ${OVMF_CODE} — install edk2-ovmf" >&2 && exit 1; }

rm -rf "$FRAME_DIR"
mkdir -p "$FRAME_DIR"

# OVMF writes its variables back to the file it was given, so this machine gets
# a copy of its own rather than the one every other guest on this host boots
# from.
VARS="${FRAME_DIR}/vars.fd"
cp "$OVMF_VARS" "$VARS"

QEMU_PID=""
cleanup() {
    status=$?
    set +e
    [ -n "$QEMU_PID" ] && kill "$QEMU_PID" 2>/dev/null
    rm -f "$VARS"
    exit "$status"
}
trap cleanup EXIT

# A free port for qemu's monitor. It is spoken to over tcp rather than a unix
# socket because bash can open a tcp connection on its own, and a unix one would
# mean a second program on the machine for the sake of saying `screendump`.
port=0
while [ "$port" -eq 0 ]; do
    candidate=$((RANDOM % 20000 + 30000))
    (exec 3<>"/dev/tcp/127.0.0.1/${candidate}") 2>/dev/null || port=$candidate
done

echo "### Boot $(basename "$ISO")"
qemu-system-x86_64 \
    -machine q35,accel=kvm:tcg \
    -cpu max \
    -smp 2 \
    -m 4096 \
    -drive "if=pflash,format=raw,unit=0,readonly=on,file=${OVMF_CODE}" \
    -drive "if=pflash,format=raw,unit=1,file=${VARS}" \
    -drive "media=cdrom,readonly=on,file=${ISO}" \
    -boot order=d \
    -nic user,model=virtio-net-pci \
    -display none \
    -monitor "tcp:127.0.0.1:${port},server,nowait" &
QEMU_PID=$!

# The monitor is not listening the instant qemu is started.
connected=false
for _ in $(seq 40); do
    if (exec 3<>"/dev/tcp/127.0.0.1/${port}") 2>/dev/null; then
        exec 3<>"/dev/tcp/127.0.0.1/${port}"
        connected=true
        break
    fi
    sleep 0.5
done
[ "$connected" = true ] || { echo "Error: qemu's monitor never came up on port ${port}" >&2 && exit 1; }

# The monitor answers on the same connection. Nothing here reads those answers —
# a screendump is judged by the file it leaves, not by what the monitor says
# about it — and a run's worth of prompts is far too little to fill the socket.
screendump() {
    printf 'screendump %s\n' "$1" >&3
    for _ in $(seq 25); do
        sleep 0.2
        [ -s "$1" ] && return 0
    done
    return 1
}

# What the console says, as far as it can be made out. --psm 6 because a console
# is one block of text in one font, which is exactly the case the default page
# segmentation is wrong about.
console_text() {
    tesseract "$1" - --psm 6 2>/dev/null || true
}

fail() {
    echo "Error: $1" >&2
    echo "the console is in ${FRAME_DIR}" >&2
    exit 1
}

echo "### Wait for the installer (up to ${TIMEOUT}s)"
deadline=$((SECONDS + TIMEOUT))
found=""
frame=0
while [ "$SECONDS" -lt "$deadline" ]; do
    sleep "$INTERVAL"
    kill -0 "$QEMU_PID" 2>/dev/null || fail "the machine stopped before the installer came up"

    frame=$((frame + 1))
    shot="$(printf '%s/frame-%02d.ppm' "$FRAME_DIR" "$frame")"
    screendump "$shot" || continue

    text="$(console_text "$shot")"
    grep -qE "$PANIC" <<<"$text" && fail "the machine did not finish booting"
    if grep -qE "$EXPECT" <<<"$text"; then
        found="$shot"
        break
    fi
done

[ -n "$found" ] || fail "the installer did not come up within ${TIMEOUT}s"

# The one frame worth keeping is the one it was recognised in.
mv "$found" "${FRAME_DIR}/installer.ppm"
rm -f "${FRAME_DIR}"/frame-*.ppm
echo "### The installer is up — ${FRAME_DIR}/installer.ppm"
