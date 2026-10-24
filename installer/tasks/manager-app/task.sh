# `system-manager init` needs an installed desktop, so this runs after the
# gnome task.
if ! as_user 'system-manager init' </dev/null; then
    echo "system-manager init failed, its menu entry follows at its first start" >&2
    exit 1
fi
