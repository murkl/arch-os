[ -f "$(user_home)/installer.conf" ]
last="$(tail -n 1 "$(user_home)/installer.log")"
[ "${last#* * }" = "INFO  Arch OS installed" ]
