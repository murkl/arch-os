# sysctl says nothing about a key it has never heard of, so a renamed one is a
# file that looks right and does nothing.

sysctl_keys_exist "${MNT}/etc/sysctl.d/99-arch-os-ecn.conf"
