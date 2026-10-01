# Simulated, an address all the same, so the page can be looked at. Oak keeps
# the log beside the answer file, under the module's name.
if debugging; then
    answer ARCH_OS_LOG_URL "${PASTE}/demo"
    return 0
fi
url="$(paste_online <"${MODULE_CONF%.conf}.log")"
[ -n "$url" ]
answer ARCH_OS_LOG_URL "$url"
