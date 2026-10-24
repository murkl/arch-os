# Settings only, no packages. Values: docs/REFERENCE.md#tuning

data="$(where)"

# Asterisks while typing a sudo password, so the terminal does not look frozen.
render "${data}/20-pwfeedback" | sudoers_rule 20-pwfeedback

# pacman ships Color off.
pacman_include "${data}/arch-os-options.conf"

# No debug packages from AUR builds. The compiler flags stay Arch's.
mkdir -p "${MNT}/etc/makepkg.conf.d"
render "${data}/makepkg.conf" >"${MNT}/etc/makepkg.conf.d/arch-os.conf"

# https://wiki.archlinux.org/title/Sysctl
render "${data}/99-arch-os-memory.conf" >"${MNT}/etc/sysctl.d/99-arch-os-memory.conf"

# bbr judges a path by its delay, where cubic backs off at the first lost packet.
# https://wiki.archlinux.org/title/Sysctl#TCP_congestion_algorithm
render "${data}/99-arch-os-network.conf" >"${MNT}/etc/sysctl.d/99-arch-os-network.conf"

# Huge pages without stalling a program to compact memory.
# https://docs.kernel.org/admin-guide/mm/transhuge.html
mkdir -p "${MNT}/etc/tmpfiles.d"
render "${data}/arch-os-hugepages.conf" >"${MNT}/etc/tmpfiles.d/arch-os-hugepages.conf"

# User services only: a system service may still be writing.
mkdir -p "${MNT}/etc/systemd/user.conf.d"
render "${data}/manager.conf" >"${MNT}/etc/systemd/user.conf.d/10-arch-os.conf"

mkdir -p "${MNT}/etc/systemd/journald.conf.d"
render "${data}/journald.conf" >"${MNT}/etc/systemd/journald.conf.d/10-arch-os.conf"

# bfq for a spinning disk only. NVMe and the rest keep the kernel's choice.
# https://wiki.archlinux.org/title/Improving_performance#Changing_I/O_scheduler
mkdir -p "${MNT}/etc/udev/rules.d"
render "${data}/60-arch-os-ioschedulers.rules" >"${MNT}/etc/udev/rules.d/60-arch-os-ioschedulers.rules"

# A USB drive gets a tenth of the dirty limit, so a copy runs at its pace
# instead of into memory. By SUBSYSTEMS, since ata_id reports a SATA disk in
# an enclosure as ID_BUS=ata.
# https://docs.kernel.org/admin-guide/abi-testing.html#abi-sys-class-bdi-bdi-strict-limit
render "${data}/70-arch-os-usb-writeback.rules" >"${MNT}/etc/udev/rules.d/70-arch-os-usb-writeback.rules"
