# The networks in range for the page, one SSID per line, strongest first.
# Simulated, a machine with networks in range, whatever the desk has.
if debugging; then
    printf '%s\n' Home "Coffee Bar Free"
    return 0
fi

# iwctl returns as soon as a scan has started, so the list is read once the
# card says it is done rather than after a fixed pause. Into a variable first:
# a grep that stops reading fails the pipe under pipefail.
device="$(wifi_station)"
iwctl station "$device" scan || true
for _ in $(seq 20); do
    sleep 0.5
    state="$(iwctl station "$device" show | sed -e 's/\x1b\[[0-9;]*m//g' -e 's/\r//')"
    grep -qE '^[[:space:]]*Scanning[[:space:]]+no([[:space:]]|$)' <<<"$state" && break
done

# Columns are padded apart and an SSID may hold spaces, so two or more spaces is
# the only separator that keeps "Coffee Bar Free" whole. The connected one is
# marked with ">" and is still a choice.
iwctl station "$device" get-networks |
    sed -e 's/\x1b\[[0-9;]*m//g' -e 's/\r//' |
    awk '
        /^[[:space:]]*-+[[:space:]]*$/ { rules++; next }
        rules < 2 { next }
        {
            line = $0
            sub(/^[[:space:]]*>?[[:space:]]*/, "", line)
            sub(/[[:space:]]+$/, "", line)
            if (line == "") next
            split(line, col, /[[:space:]][[:space:]]+/)
            name = col[1]
            if (name == "" || seen[name]++) next
            print name
        }
    '
