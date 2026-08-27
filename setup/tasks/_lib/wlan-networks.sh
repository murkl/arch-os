# Print one SSID per line, strongest first, from iwctl's table.
#
# This is a file of its own because the table is genuinely awkward: it is
# coloured, it is drawn for a human, and an SSID may contain spaces — so the
# columns cannot be split on whitespace. They are padded out instead, which
# makes "two or more spaces" the real separator and the only one that does not
# corrupt a name like "Coffee Bar Free".

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
