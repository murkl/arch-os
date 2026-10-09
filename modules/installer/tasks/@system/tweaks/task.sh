# How the system behaves, never what is installed. Why these numbers and not
# the defaults: docs/REFERENCE.md#tuning

data="$(where)"

# Stars while typing a sudo password, so a terminal does not look frozen.
render "${data}/20-pwfeedback" | sudoers_rule 20-pwfeedback

# Colour, which pacman ships off.
pacman_include "${data}/arch-os-options.conf"

# Watchdogs nothing here uses, which delay every shutdown.
mkdir -p "${MNT}/etc/modprobe.d"
render "${data}/blacklist-watchdog.conf" >"${MNT}/etc/modprobe.d/blacklist-watchdog.conf"

# No debug packages beside every AUR build; the compiler flags stay Arch's.
mkdir -p "${MNT}/etc/makepkg.conf.d"
render "${data}/makepkg.conf" >"${MNT}/etc/makepkg.conf.d/arch-os.conf"

# Dirty pages and cache reclaim. https://wiki.archlinux.org/title/Sysctl
render "${data}/99-arch-os-memory.conf" >"${MNT}/etc/sysctl.d/99-arch-os-memory.conf"

# bbr judges a path by its delay, where cubic backs off at the first lost packet.
# https://wiki.archlinux.org/title/Sysctl#TCP_congestion_algorithm
render "${data}/99-arch-os-bbr.conf" >"${MNT}/etc/sysctl.d/99-arch-os-bbr.conf"

# Huge pages, but no program stopped to make one.
# https://docs.kernel.org/admin-guide/mm/transhuge.html
mkdir -p "${MNT}/etc/tmpfiles.d"
render "${data}/arch-os-hugepages.conf" >"${MNT}/etc/tmpfiles.d/arch-os-hugepages.conf"

# The session's services stop quickly; a system service may be writing.
mkdir -p "${MNT}/etc/systemd/user.conf.d"
render "${data}/manager.conf" >"${MNT}/etc/systemd/user.conf.d/10-arch-os.conf"

mkdir -p "${MNT}/etc/systemd/journald.conf.d"
render "${data}/journald.conf" >"${MNT}/etc/systemd/journald.conf.d/10-arch-os.conf"

# bfq for a spinning disk only; NVMe and the rest keep the kernel's choice.
# https://wiki.archlinux.org/title/Improving_performance#Changing_I/O_scheduler
mkdir -p "${MNT}/etc/udev/rules.d"
render "${data}/60-arch-os-ioschedulers.rules" >"${MNT}/etc/udev/rules.d/60-arch-os-ioschedulers.rules"

# A USB drive held to a tenth of the dirty limit, so a copy runs at its pace
# instead of finishing into memory. 70, because ID_BUS is set at 60.
# https://docs.kernel.org/admin-guide/abi-testing.html#abi-sys-class-bdi-bdi-strict-limit
render "${data}/70-arch-os-usb-writeback.rules" >"${MNT}/etc/udev/rules.d/70-arch-os-usb-writeback.rules"
