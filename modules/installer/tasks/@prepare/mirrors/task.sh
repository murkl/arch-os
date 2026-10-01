# What this machine is, in one line, before anything else is in the log.
printf 'machine: %s cores, %s memory, %s on %s, virtualisation %s\n' \
    "$(nproc)" \
    "$(awk '/^MemTotal:/ { printf "%.1f GiB", $2 / 1048576 }' /proc/meminfo)" \
    "$(lsblk -bdno SIZE "$ARCH_OS_DISK" | numfmt --to=iec)" \
    "$ARCH_OS_DISK" \
    "$(systemd-detect-virt || true)"

# The live image ships an unranked worldwide list, and pacstrap copies it into
# the new system. Never fatal: a slow mirror installs, no list does not.
# https://wiki.archlinux.org/title/Reflector
rank_mirrors() {
    command -v reflector >/dev/null || {
        echo "this image has no reflector, installing from the list it shipped" >&2
        return 0
    }

    local ranked warnings servers unrated args=(--protocol https --age 12 --latest 10 --sort rate)
    [ -n "$ARCH_OS_REFLECTOR_COUNTRY" ] && args+=(--country "$ARCH_OS_REFLECTOR_COUNTRY")
    ranked="$(mktemp)"
    warnings="$(mktemp)"

    # reflector keeps a mirror that timed out, unranked, and exits 0 even when
    # every one did - a list worse than the shipped one, which opens on Arch's CDN.
    if timeout 120 reflector "${args[@]}" --save "$ranked" 2>"$warnings" && [ -s "$ranked" ]; then
        servers="$(grep -c '^Server' "$ranked" || true)"
        unrated="$(grep -c 'failed to rate' "$warnings" || true)"
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

echo "ranking mirrors"
rank_mirrors

timedatectl set-ntp true
rm -f /var/lib/pacman/db.lck

# A stale keyring is the commonest reason a fresh install refuses a package.
pacman -Sy --noconfirm archlinux-keyring
