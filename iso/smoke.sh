#!/bin/bash
# Boots a built image until its interface answers a key, proving the boot chain
# no linter sees. See README.md.
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

# A failure keeps every frame, since the screen is the only evidence. A pass
# keeps the matching one.
FRAME_DIR="${FRAME_DIR:-$(dirname "$IMAGE")/smoke/$(basename "$IMAGE" .iso)}"

# Covers a cold boot under emulation without KVM, with room to spare.
TIMEOUT="${TIMEOUT:-300}"
INTERVAL="${INTERVAL:-15}"

OVMF_CODE="${OVMF_CODE:-/usr/share/edk2/x64/OVMF_CODE.4m.fd}"
OVMF_VARS="${OVMF_VARS:-/usr/share/edk2/x64/OVMF_VARS.4m.fd}"

# The welcome page, by its languages: OCR reads them cleanly, unlike other text
# and the block-drawn wordmark.
EXPECT='English|Deutsch'

# A page on screen may not take keys yet: a console the splash left locked
# echoes them. So Deutsch is chosen by key, and the first question, the
# keyboard, must come up in German.
ANSWER='Tastatur|Konsole'

# A failed boot prints one of these, so the run stops before the timeout.
PANIC='Kernel panic|Failed to start'

for tool in qemu-system-x86_64 tesseract; do
    command -v "$tool" >/dev/null || { echo "Error: ${tool} not found, see README.md" >&2 && exit 1; }
done
[ -f "$OVMF_CODE" ] || { echo "Error: no OVMF firmware at ${OVMF_CODE}. Install edk2-ovmf." >&2 && exit 1; }

rm -rf "$FRAME_DIR"
mkdir -p "$FRAME_DIR"

# OVMF writes its variables back to the file, so the machine gets its own copy.
VARS="${FRAME_DIR}/vars.fd"
cp "$OVMF_VARS" "$VARS"

QEMU_PID=""
last_shot=""
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
    printf 'screendump %s -f png\n' "$1" >&3
    for _ in $(seq 25); do
        sleep 0.2
        [ -s "$1" ] && return 0
    done
    return 1
}

# --psm 6, since a console is one block of text in one font, which the default
# page segmentation gets wrong.
console_text() {
    tesseract "$1" - --psm 6 2>/dev/null || true
}

# Logs the console text too, since a login prompt and a stuck splash otherwise
# fail alike.
fail() {
    echo "Error: $1" >&2
    if [ -n "$last_shot" ]; then
        echo "the console read:" >&2
        console_text "$last_shot" | sed 's/^/  | /' >&2
    else
        echo "no screendump of the console, see the monitor output above" >&2
    fi
    echo "console screenshots: ${FRAME_DIR}" >&2
    exit 1
}

# Screenshots the console every INTERVAL seconds, for up to TIMEOUT, until it
# matches the pattern. The matching frame lands in $found.
found=""
frame=0
await() {
    local pattern="$1" deadline=$((SECONDS + TIMEOUT)) shot text
    found=""
    while [ "$SECONDS" -lt "$deadline" ]; do
        sleep "$INTERVAL"
        kill -0 "$QEMU_PID" 2>/dev/null || fail "the machine stopped before the interface came up"

        frame=$((frame + 1))
        shot="$(printf '%s/frame-%02d.png' "$FRAME_DIR" "$frame")"
        screendump "$shot" || continue
        last_shot="$shot"

        text="$(console_text "$shot")"
        grep -qE "$PANIC" <<<"$text" && fail "the machine did not finish booting"
        if grep -qE "$pattern" <<<"$text"; then
            found="$shot"
            return 0
        fi
    done
    return 1
}

# A key as the keyboard sends it, then a moment for the interface to draw.
press() {
    printf 'sendkey %s\n' "$1" >&3
    sleep 1
}

echo "### Wait for the interface (up to ${TIMEOUT}s)"
await "$EXPECT" || fail "the interface did not come up within ${TIMEOUT}s"

echo "### Choose Deutsch with the keyboard"
press down
press ret
await "$ANSWER" || fail "the interface did not answer the keyboard within ${TIMEOUT}s"

mv "$found" "${FRAME_DIR}/arch-os.png"
rm -f "${FRAME_DIR}"/frame-*.png
echo "### Arch OS is up and answers: ${FRAME_DIR}/arch-os.png"
