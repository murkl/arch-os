# Without --dont-ask, iwctl asks for a passphrase on the terminal the interface
# is drawn on. Online is waited for, not required: the page behind says so.
iwctl --dont-ask station "$(wifi_station)" connect "$ARCH_OS_WIFI_SSID"
wifi_online || true
