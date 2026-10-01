# The code alone, from whatever was typed - the whole link or its last word -
# and always asked of paste.rs over https.
ref="$(printf '%s' "$ARCH_OS_CONFIG_SOURCE" | tr -d '[:space:]')"
url="${PASTE}/${ref##*/}"
body="$(fetch_url -s --connect-timeout 10 --max-time 30 "$url")"

# Everything but the sharing itself and the disk: a disk is a path on the
# machine the answers were given on, and here another disk may sit at it.
body="$(printf '%s\n' "$body" | grep '^ARCH_OS_[A-Z0-9_]*=' |
    grep -vE '^ARCH_OS_(CONFIG_[A-Z_]*|DISK)=' || true)"
[ -n "$body" ]

# Appended to the answer file, which Oak reads back once this has worked.
printf '%s\n' "$body" >>"$MODULE_CONF"
