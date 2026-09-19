# The one place here a secret reaches a command line, and iwctl's only way in
# without one: unasked, it puts the question to an agent on the terminal the
# interface is drawing on. A live image with one account, for one second, for a
# passphrase that is written down nowhere and is not the disk password.

iwctl --passphrase "$WLAN_PASSPHRASE" station "$WLAN_DEVICE" connect "$WLAN_SSID" && return 0

# What iwctl says when it refuses is a row of its own table and goes to stdout,
# which here is the hook's answer rather than anything anybody reads. So the
# reason is said once, in a sentence, on the channel a failure is read from -
# and it names the passphrase, which is what it is nearly every time.
echo "${WLAN_SSID} did not accept that passphrase, or it is no longer in range." >&2
exit 1
