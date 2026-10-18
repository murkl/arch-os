# The Arch ISO ships no xkeyboard-config, and then data/ answers.
layout="$(desktop_layout)"
[ -n "$layout" ] || return 0

echo none

variants="$(localectl list-x11-keymap-variants "$layout" 2>/dev/null || true)"
if [ -n "$variants" ]; then
    echo "$variants"
    return 0
fi
# A layout without variants has no line there.
{ grep "^${layout} " "$(installer_data)/x11-variants" || true; } | cut -d' ' -f2- | tr ' ' '\n'
