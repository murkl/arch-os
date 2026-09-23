# A machine with nothing plugged in cannot be helped by any answer, and a
# question listing nothing is worse than being told why.

[ -n "$(list_devices)" ] && return 0
echo "No USB device found. Plug a stick in and start this again." >&2
exit 1
