dir="${MNT}/var/log/arch-os"
# Root's alone.
modes="$(stat -c '%a %u' "${dir}/installer.conf" "${dir}/installer.log" "${dir}/installer.sh")"
[ "$modes" = "$(printf '600 0\n600 0\n700 0')" ]
bash -n "${dir}/installer.sh"
last="$(tail -n 1 "${dir}/installer.log")"
[ "${last#* * }" = "INFO  Arch OS installed" ]
