# The networks in range, one SSID per line, strongest first.
#
# The scan is fired here rather than by Oak because iwctl returns as soon as it
# has started one: the wait belongs beside the command that needs it. And it is
# a wait for the card rather than a fixed pause - a list read while the radio is
# still going round the channels is short rather than wrong, and a card that has
# finished in half a second should not cost three.
iwctl station "$WLAN_DEVICE" scan || true
for _ in $(seq 20); do
    sleep 0.5
    # Into a variable first: a grep that stops reading leaves iwctl with a write
    # error, and under pipefail that is a failed hook instead of an answer.
    state="$(iwctl station "$WLAN_DEVICE" show | sed -e 's/\x1b\[[0-9;]*m//g' -e 's/\r//')"
    grep -qE '^[[:space:]]*Scanning[[:space:]]+no([[:space:]]|$)' <<<"$state" && break
done

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
