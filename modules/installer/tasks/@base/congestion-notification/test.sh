# Read back through sysctl's own rules rather than compared against the line
# written above: sysctl says nothing about a key it has never heard of, so a
# renamed one is a file that looks right and does nothing.
debugging && return 0

sysctl_keys_exist "${MNT}/etc/sysctl.d/99-arch-os-ecn.conf"
