# Yes where nothing newer is out. A newer one is a no, and that opens the
# install.
check_online || exit "$EXIT_OFFLINE"
json="$(release_json latest)" || exit "$EXIT_UNREACHABLE"
found="$(newer_recovery <<<"$json")"
[ -z "$found" ]
