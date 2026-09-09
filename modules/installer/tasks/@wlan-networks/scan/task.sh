# The networks in range, one SSID per line, strongest first.
#
# The scan is fired here rather than by Oak because iwctl returns as
# soon as it has started one: the wait belongs beside the command that needs it.
iwctl station "$WLAN_DEVICE" scan || true
sleep 3

# iwctl's table is coloured, drawn for a human, and an SSID may hold spaces,
# so the columns can't be split on whitespace. They're padded apart instead,
# which makes "two or more spaces" the only separator that doesn't corrupt a
# name like "Coffee Bar Free".
iwctl station "$WLAN_DEVICE" get-networks |
    sed -e 's/\x1b\[[0-9;]*m//g' -e 's/\r//' |
    awk '
        # iwctl brackets its header with two rules; the networks come after.
        /^[[:space:]]*-+[[:space:]]*$/ { rules++; next }
        rules < 2 { next }
        {
            line = $0
            # The connected network is marked with ">"; it is still a choice.
            sub(/^[[:space:]]*>?[[:space:]]*/, "", line)
            sub(/[[:space:]]+$/, "", line)
            if (line == "") next
            # Columns are padded apart: name, security, signal.
            split(line, col, /[[:space:]][[:space:]]+/)
            name = col[1]
            if (name == "" || seen[name]++) next
            print name
        }
    '
