#!/bin/bash
# Boots a built image until its interface answers a key, proving the boot chain
# no linter sees. Reads the interface's trace on a virtio port, not the screen.
# See README.md.
#
#   smoke.sh <image.iso | recovery-dir>
set -eu

IMAGE="${1:-}"
if [ -f "$IMAGE" ]; then
    BOOT=(-drive "media=cdrom,readonly=on,file=${IMAGE}" -boot order=d)
elif [ -f "${IMAGE}/recovery.efi" ]; then
    BOOT=(-kernel "${IMAGE}/recovery.efi" -drive "if=virtio,format=raw,readonly=on,file=${IMAGE}/recovery.img")
else
    echo "usage: $0 <image.iso | recovery-dir>" >&2
    exit 1
fi

# A failure keeps every frame and the trace. A pass keeps the last frame.
FRAME_DIR="${FRAME_DIR:-$(dirname "$IMAGE")/smoke/$(basename "$IMAGE" .iso)}"

# Covers a cold boot under emulation without KVM, with room to spare.
TIMEOUT="${TIMEOUT:-300}"
INTERVAL="${INTERVAL:-15}"

OVMF_CODE="${OVMF_CODE:-/usr/share/edk2/x64/OVMF_CODE.4m.fd}"
OVMF_VARS="${OVMF_VARS:-/usr/share/edk2/x64/OVMF_VARS.4m.fd}"

for tool in qemu-system-x86_64 od; do
    command -v "$tool" >/dev/null || { echo "Error: ${tool} not found, see README.md" >&2 && exit 1; }
done
[ -f "$OVMF_CODE" ] || { echo "Error: no OVMF firmware at ${OVMF_CODE}. Install edk2-ovmf." >&2 && exit 1; }

rm -rf "$FRAME_DIR"
mkdir -p "$FRAME_DIR"

# OVMF writes its variables back to the file, so the machine gets its own copy.
VARS="${FRAME_DIR}/vars.fd"
cp "$OVMF_VARS" "$VARS"

# The launcher passes the credential on as --trace: runtime/README.md#trace
TRACE="${FRAME_DIR}/trace"
: >"$TRACE"

QEMU_PID=""
cleanup() {
    status=$?
    set +e
    [ -n "$QEMU_PID" ] && kill "$QEMU_PID" 2>/dev/null
    rm -f "$VARS"
    exit "$status"
}
trap cleanup EXIT

# A free port for qemu's monitor. tcp rather than a unix socket, since bash
# opens tcp connections by itself.
port=0
while [ "$port" -eq 0 ]; do
    candidate=$((RANDOM % 20000 + 30000))
    (exec 3<>"/dev/tcp/127.0.0.1/${candidate}") 2>/dev/null || port=$candidate
done

echo "### Boot $(basename "$IMAGE")"
qemu-system-x86_64 \
    -machine q35,accel=kvm:tcg \
    -cpu max \
    -smp 2 \
    -m 4096 \
    -drive "if=pflash,format=raw,unit=0,readonly=on,file=${OVMF_CODE}" \
    -drive "if=pflash,format=raw,unit=1,file=${VARS}" \
    "${BOOT[@]}" \
    -nic user,model=virtio-net-pci \
    -display none \
    -device virtio-serial-pci \
    -chardev "file,id=trace,path=${TRACE}" \
    -device "virtserialport,chardev=trace,name=arch-os.trace" \
    -smbios "type=11,value=io.systemd.credential:arch-os.trace=/dev/virtio-ports/arch-os.trace" \
    -monitor "tcp:127.0.0.1:${port},server,nowait" &
QEMU_PID=$!

# The monitor does not listen right after qemu starts.
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

# The monitor's answers go unread. A screendump is judged by the file it
# leaves.
screendump() {
    printf 'screendump %s -f %s\n' "$1" "${1##*.}" >&3
    for _ in $(seq 25); do
        sleep 0.2
        [ -s "$1" ] && return 0
    done
    return 1
}

fail() {
    echo "Error: $1" >&2
    echo "trace:" >&2
    sed 's/^/  | /' "$TRACE" >&2
    echo "console screenshots: ${FRAME_DIR}" >&2
    exit 1
}

# Waits for a trace line matching the pattern, a screenshot every INTERVAL
# seconds as evidence.
frame=0
await() {
    local pattern="$1" deadline=$((SECONDS + TIMEOUT)) next=$SECONDS
    while ! grep -qE "^(${pattern})\$" "$TRACE"; do
        [ "$SECONDS" -lt "$deadline" ] || return 1
        kill -0 "$QEMU_PID" 2>/dev/null || fail "the machine stopped before the interface answered"
        if [ "$SECONDS" -ge "$next" ]; then
            frame=$((frame + 1))
            screendump "$(printf '%s/frame-%02d.png' "$FRAME_DIR" "$frame")" || true
            next=$((SECONDS + INTERVAL))
        fi
        sleep 1
    done
}

# A key as the keyboard sends it, then a moment for the interface to draw.
press() {
    printf 'sendkey %s\n' "$1" >&3
    sleep 1
}

# The trace proves the program runs, not that the screen shows it: a picture of
# one color is a blank screen.
shows_something() {
    local colors
    colors="$({ read -r _ && read -r _ && read -r _ && od -An -v -tx1 -w3; } <"$1" | sort -u | wc -l)"
    [ "$colors" -gt 1 ]
}

echo "### Wait for the interface (up to ${TIMEOUT}s)"
await 'page language' || fail "the interface did not come up within ${TIMEOUT}s"

echo "### Choose Deutsch with the keyboard"
for _ in $(seq 10); do
    [ "$(grep '^focus ' "$TRACE" | tail -n 1)" = "focus de" ] && break
    press down
done
press ret
await 'language de' || fail "the interface did not answer the keyboard within ${TIMEOUT}s"
await 'page question [A-Z_]+' || fail "the interface did not move on to its first question within ${TIMEOUT}s"

screendump "${FRAME_DIR}/arch-os.ppm" || fail "no screendump of the console"
shows_something "${FRAME_DIR}/arch-os.ppm" || fail "the console shows nothing"
screendump "${FRAME_DIR}/arch-os.png" || fail "no screendump of the console"
rm -f "${FRAME_DIR}"/frame-*.png "${FRAME_DIR}/arch-os.ppm" "$TRACE"
echo "### Arch OS is up and answers: ${FRAME_DIR}/arch-os.png"
