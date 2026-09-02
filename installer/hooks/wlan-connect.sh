# Join the chosen network.
#
# The one place here a secret reaches a command line, and iwctl's only way in
# without one: unasked, it puts the question to an agent on the terminal the
# interface is drawing on. A live image with one account, for one second, for a
# passphrase that is written down nowhere and is not the disk password.

iwctl --passphrase "$WLAN_PASSPHRASE" station "$WLAN_DEVICE" connect "$WLAN_SSID"
