# https://wiki.archlinux.org/title/Installation_guide#Network_configuration

# /etc/hosts stays as shipped: nss-myhostname answers for this name.
# https://wiki.archlinux.org/title/Network_configuration#Local_hostname_resolution
echo "$ARCH_OS_HOSTNAME" >"${MNT}/etc/hostname"

arch-chroot "$MNT" systemctl enable NetworkManager

iwd_setting() {
    awk -v section="[$2]" -v key="$3" '
        /^\[/ { inside = ($0 == section); next }
        inside && index($0, key "=") == 1 { print substr($0, length(key) + 2); exit }
    ' "$1"
}

# Every Wi-Fi network the live system joined, so the first boot is online. iwd
# names a profile after the SSID, or "=" and its hex. https://man.archlinux.org/man/iwd.network.5
for profile in /var/lib/iwd/*.psk /var/lib/iwd/*.open; do
    [ -f "$profile" ] || continue
    name="$(basename "$profile")"
    name="${name%.*}"
    ssid="$name"
    if [[ $name == =* ]]; then
        hex="${name#=}" escaped=""
        while [ -n "$hex" ]; do
            escaped+="\\x${hex:0:2}"
            hex="${hex:2}"
        done
        ssid="$(printf '%b' "$escaped")"
    fi
    args=(type wifi con-name "$ssid" ssid "$ssid")
    if [ "$(iwd_setting "$profile" Settings Hidden)" = "true" ]; then
        args+=(wifi.hidden yes)
    fi
    # wpa-psk covers WPA2 and WPA3 Personal. The derived key stands in where
    # iwd kept no passphrase.
    if [[ $profile == *.psk ]]; then
        secret="$(iwd_setting "$profile" Security Passphrase)"
        [ -n "$secret" ] || secret="$(iwd_setting "$profile" Security PreSharedKey)"
        args+=(wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$secret")
    fi
    keyfile="${MNT}/etc/NetworkManager/system-connections/${name}.nmconnection"
    (umask 077 && arch-chroot "$MNT" nmcli --offline connection add "${args[@]}" >"$keyfile")
    echo "carried over Wi-Fi ${ssid}"
done
