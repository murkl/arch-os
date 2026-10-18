# The Arch ISO ships no xkeyboard-config, and then data/ answers.
printf 'auto\tauto (%s)\n' "$(auto_layout)"

layouts="$(localectl list-x11-keymap-layouts 2>/dev/null || true)"
if [ -n "$layouts" ]; then
    echo "$layouts"
    return 0
fi
grep -v '^#' "$(installer_data)/x11-layouts"
