# The code alone, from whatever was typed, the whole link or its last word,
# and always asked of paste.rs over https.
ref="$(printf '%s' "$ARCH_OS_CONFIG_SOURCE" | tr -d '[:space:]')"
url="${PASTE}/${ref##*/}"
body="$(fetch_url -sS --max-time 30 --retry 3 --retry-delay 2 "$url")"

# Everything but the sharing itself and what belongs to the machine the
# answers were given on: its disk, a path another disk may sit at here, and its
# kernel parameters, a line nobody should take on from a stranger's code.
body="$(printf '%s\n' "$body" | grep '^ARCH_OS_[A-Z0-9_]*=' |
    grep -vE '^ARCH_OS_(CONFIG_[A-Z_]*|DISK|KERNEL_ARGS)=' || true)"
[ -n "$body" ]

# Appended to the answer file, which the runtime reads back once this has worked.
printf '%s\n' "$body" >>"$MODULE_CONF"
