# Each file read back by the tool that acts on it: sysctl, systemd, udev and
# tmpfiles all pass over what they cannot read without a word.

[ -f "${MNT}/etc/sudoers.d/20-pwfeedback" ]
arch-chroot "$MNT" pacman-conf Color | grep -qx Color

sysctl_keys_exist "${MNT}/etc/sysctl.d/99-arch-os-memory.conf"
sysctl_keys_exist "${MNT}/etc/sysctl.d/99-arch-os-bbr.conf"

# makepkg's own loader, which sources the drop-ins as a build does.
# shellcheck disable=SC2016  # expanded inside the chroot
arch-chroot "$MNT" bash -c '
    source /usr/share/makepkg/util/config.sh
    load_makepkg_config
    [[ " ${OPTIONS[*]} " == *" !debug "* ]]
'

for config in user journald; do
    systemd-analyze --root="$MNT" cat-config "systemd/${config}.conf" |
        grep -q "^# .*/${config}\.conf\.d/10-arch-os\.conf$"
done

# --no-style, so a style rule a later systemd adds fails nothing that works.
udevadm verify --resolve-names=never --no-style --no-summary \
    "${MNT}/etc/udev/rules.d/60-arch-os-ioschedulers.rules" \
    "${MNT}/etc/udev/rules.d/70-arch-os-usb-writeback.rules"

# --dry-run: the line writes to /sys, which here is the live image's.
systemd-tmpfiles --dry-run --create "${MNT}/etc/tmpfiles.d/arch-os-hugepages.conf"
