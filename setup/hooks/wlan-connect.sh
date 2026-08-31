# Join the chosen network.

iwctl --passphrase "$WLAN_PASSPHRASE" station "$WLAN_DEVICE" connect "$WLAN_SSID"
