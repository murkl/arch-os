# Yes where there is nothing to install. A Recovery to install is a no, and that
# opens the install.
check_online || exit "$EXIT_OFFLINE"
json="$(release_json)" || exit "$EXIT_UNREACHABLE"
found="$(recovery_update <<<"$json")"
[ -z "$found" ]
