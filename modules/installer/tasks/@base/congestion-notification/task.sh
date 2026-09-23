# Some old routers drop connections that use explicit congestion notification,
# which shows up as a download stalling halfway through. The live system gets
# the same setting before the first download - see the init task - and a router
# that drops these connections goes on dropping them after a restart.
# https://wiki.archlinux.org/title/Sysctl

simulating && return 0

render "$(where)/99-arch-os-ecn.conf" >"${MNT}/etc/sysctl.d/99-arch-os-ecn.conf"
