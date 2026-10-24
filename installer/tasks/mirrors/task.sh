# Hardware summary at the top of the log.
printf 'machine: %s cores, %s memory, %s on %s, virtualization %s\n' \
    "$(nproc)" \
    "$(awk '/^MemTotal:/ { printf "%.1f GiB", $2 / 1048576 }' /proc/meminfo)" \
    "$(lsblk -bdno SIZE "$ARCH_OS_DISK" | numfmt --to=iec)" \
    "$ARCH_OS_DISK" \
    "$(systemd-detect-virt || allow 1)"

# The live system ships an unranked worldwide list, and pacstrap copies it into
# the new system. Never fatal: a slow mirror still installs.
# https://wiki.archlinux.org/title/Reflector
rank_mirrors() {
    local ranked warnings servers unrated country args=(--protocol https --age 12 --latest 10 --sort rate)
    country="$(mirror_country)"
    [ -n "$country" ] && args+=(--country "$country")
    ranked="$(mktemp)"
    warnings="$(mktemp)"

    # reflector keeps a timed-out mirror unranked and exits 0 even if all timed
    # out, a list worse than the shipped one, which starts with Arch's CDN.
    if timeout 120 reflector "${args[@]}" --save "$ranked" 2>"$warnings" && [ -s "$ranked" ]; then
        servers="$(grep -c '^Server' "$ranked" || allow 1)"
        unrated="$(grep -c 'failed to rate' "$warnings" || allow 1)"
        if [ "$servers" -gt "$unrated" ]; then
            install -m 644 "$ranked" /etc/pacman.d/mirrorlist
            echo "installing from ${servers} ranked mirrors"
        else
            echo "none of ${servers} mirrors ranked in time, installing from the shipped list" >&2
        fi
    else
        echo "ranking mirrors failed, installing from the shipped list" >&2
    fi
    cat "$warnings" >&2
    rm -f "$ranked" "$warnings"
}

# NTP first: https to the mirrors and the keyring below need the right time.
# https://wiki.archlinux.org/title/Installation_guide#Update_the_system_clock
timedatectl set-ntp true

echo "ranking mirrors"
rank_mirrors

# A lock without a running pacman is left by an aborted earlier attempt.
pgrep -x pacman >/dev/null || rm -f /var/lib/pacman/db.lck

# The live system creates its keyring after the NTP sync, and pacman refuses
# every package until then. start waits for a running unit and returns at once
# for a finished one.
timeout 300 systemctl start pacman-init.service || {
    echo "no pacman keyring on the live system after 5 minutes" >&2
    exit 10
}

# A stale keyring is the most common reason pacman refuses a package.
if ! pacman -Sy --noconfirm archlinux-keyring; then
    check_online || exit "$EXIT_OFFLINE"
    echo "updating the keyring failed" >&2
    exit 1
fi
