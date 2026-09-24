# The two firmware settings an installation cannot be started without. Secure
# Boot is set up again at the end, with keys of this machine's own.

if [ ! -d /sys/firmware/efi ]; then
    echo "This machine booted in BIOS mode, which Arch OS does not install to. Set the boot mode to UEFI in the firmware settings and start again." >&2
    exit 1
fi

# Read whole before it is searched: grep stops at the first match, and bootctl,
# still writing, would die of that - which pipefail reports as Secure Boot on.
if ! grep -q "Secure Boot: disabled" <<<"$(bootctl status 2>/dev/null)"; then
    echo "Secure Boot is switched on. Turn it off in the firmware settings and start again - the installer can set it up again for you afterwards." >&2
    exit 1
fi
