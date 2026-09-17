# Some old routers drop connections that use explicit congestion notification,
# which shows up as a download stalling halfway through.
#
# The live system gets the same setting before the first download - see the init
# task - and the installed one needs it as well: a router that drops these
# connections goes on dropping them after the machine is restarted.
# https://wiki.archlinux.org/title/Sysctl

simulating && return 0

{
    echo '# Written by the Arch OS Installer.'
    echo 'net.ipv4.tcp_ecn = 0'
} >"${MNT}/etc/sysctl.d/99-arch-os-ecn.conf"
