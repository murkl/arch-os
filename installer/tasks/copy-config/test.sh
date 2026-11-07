[ -f "$(user_home)/installer.conf" ]
bash -n "$(user_home)/installer.sh"
last="$(tail -n 1 "$(user_home)/installer.log")"
[ "${last#* * }" = "INFO  Arch OS installed" ]
