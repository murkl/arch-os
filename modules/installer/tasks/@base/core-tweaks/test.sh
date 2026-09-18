# Four of these write cleanly, look right afterwards and simply never take
# effect: sysctl passes over a key the kernel does not have, systemd never looks
# outside its own drop-in directories, udev throws away a whole rule file that
# fails to parse, and tmpfiles skips a line it cannot read. So each is read back
# through the tool that will act on it rather than compared against a value
# repeated here, which is the copy that goes stale.
simulating && return 0

[ -f "${MNT}/etc/sudoers.d/20-pwfeedback" ]
grep -q '^ParallelDownloads' "${MNT}/etc/pacman.conf"

sysctl_keys_exist "${MNT}/etc/sysctl.d/99-arch-os-memory.conf"
sysctl_keys_exist "${MNT}/etc/sysctl.d/99-arch-os-mmap.conf"
sysctl_keys_exist "${MNT}/etc/sysctl.d/99-arch-os-bbr.conf"

# The same two files makepkg itself sources, in the order it sources them, so
# a typo in the drop-in shows up here rather than in the middle of a build.
# shellcheck disable=SC2016  # makepkg's own config loader expands this, not us
arch-chroot "$MNT" bash -c '
    source /usr/share/makepkg/util/config.sh
    load_makepkg_config
    [[ $CFLAGS == *"-march=native"* && $CXXFLAGS == *"-march=native"* ]]
'

# systemd prints the files it would load and in what order, so a drop-in that is
# not in that list is one it is never going to read.
for config in system user journald; do
    systemd-analyze --root="$MNT" cat-config "systemd/${config}.conf" |
        grep -q "^# .*/${config}\.conf\.d/10-arch-os\.conf$"
done

# --no-style, so a style rule a later systemd adds cannot fail an installation
# over a rule that works.
udevadm verify --resolve-names=never --no-style --no-summary \
    "${MNT}/etc/udev/rules.d/60-arch-os-ioschedulers.rules"

# --dry-run, because the line in there writes to /sys, and the /sys this runs
# against belongs to the live image rather than to the system being installed.
systemd-tmpfiles --dry-run --create "${MNT}/etc/tmpfiles.d/arch-os-hugepages.conf"
