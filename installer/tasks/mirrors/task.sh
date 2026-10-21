# What this machine is, in one line, before anything else is in the log.
printf 'machine: %s cores, %s memory, %s on %s, virtualization %s\n' \
    "$(nproc)" \
    "$(awk '/^MemTotal:/ { printf "%.1f GiB", $2 / 1048576 }' /proc/meminfo)" \
    "$(lsblk -bdno SIZE "$ARCH_OS_DISK" | numfmt --to=iec)" \
    "$ARCH_OS_DISK" \
    "$(systemd-detect-virt || allow 1)"

# The live image ships an unranked worldwide list, and pacstrap copies it into
# the new system. Never fatal: a slow mirror installs, no list does not.
# https://wiki.archlinux.org/title/Reflector
rank_mirrors() {
    local ranked warnings servers unrated country args=(--protocol https --age 12 --latest 10 --sort rate)
    country="$(mirror_country)"
    [ -n "$country" ] && args+=(--country "$country")
    ranked="$(mktemp)"
    warnings="$(mktemp)"

    # reflector keeps a mirror that timed out, unranked, and exits 0 even when
    # every one did: a list worse than the shipped one, which opens on Arch's CDN.
    if timeout 120 reflector "${args[@]}" --save "$ranked" 2>"$warnings" && [ -s "$ranked" ]; then
        servers="$(grep -c '^Server' "$ranked" || allow 1)"
        unrated="$(grep -c 'failed to rate' "$warnings" || allow 1)"
        if [ "$servers" -gt "$unrated" ]; then
            install -m 644 "$ranked" /etc/pacman.d/mirrorlist
            echo "installing from ${servers} ranked mirrors"
        else
            echo "none of the ${servers} mirrors answered in time to be ranked, installing from the list the image shipped" >&2
        fi
    else
        echo "the mirrors could not be ranked, installing from the list the image shipped" >&2
    fi
    cat "$warnings" >&2
    rm -f "$ranked" "$warnings"
}

# The clock from network time first: the mirrors answer over https, and the
# keyring below is made once it is set.
# https://wiki.archlinux.org/title/Installation_guide#Update_the_system_clock
timedatectl set-ntp true

echo "ranking mirrors"
rank_mirrors

rm -f /var/lib/pacman/db.lck

# The live image makes its keyring once the clock is set from network time,
# and pacman refuses every package until then. A start waits for a running one
# and returns at once for a finished one.
timeout 300 systemctl start pacman-init.service || {
    echo "the live image had no pacman keyring after 5 minutes" >&2
    exit 10
}

# A stale keyring is the commonest reason a fresh install refuses a package.
if ! pacman -Sy --noconfirm archlinux-keyring; then
    check_online || exit "$EXIT_OFFLINE"
    echo "the keyring could not be brought up to date" >&2
    exit 1
fi
