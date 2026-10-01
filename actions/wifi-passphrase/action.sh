# The one place a secret reaches a command line: iwctl takes it no other way
# without an agent on the terminal. A live image, one account, one second.
iwctl --passphrase "$ARCH_OS_WIFI_PASSPHRASE" station "$(wifi_station)" connect "$ARCH_OS_WIFI_SSID"

# Some cards take a wrong passphrase without a word; no address is the tell.
wifi_online
