# Simulated, an address all the same, so the page can be looked at.
if debugging; then
    answer ARCH_OS_CONFIG_URL "${PASTE}/demo"
    return 0
fi

url="$(grep -v '^ARCH_OS_CONFIG_' "$MODULE_CONF" | paste_online)"
[ -n "$url" ]
answer ARCH_OS_CONFIG_URL "$url"

# And into the copy the installed system keeps, so it knows where it was shared.
target="${MNT}/home/${ARCH_OS_USERNAME}/installer.conf"
if [ -f "$target" ]; then
    printf "ARCH_OS_CONFIG_URL='%s'\n" "$url" >>"$target"
fi
