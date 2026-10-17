# The account's menu entry, its icon and the update notification. The System
# Manager sets them up only where a desktop is installed, so after GNOME rather
# than beside the program.
if ! as_user 'system-manager init' </dev/null; then
    echo "the System Manager's menu entry waits for its first start" >&2
    exit 1
fi
