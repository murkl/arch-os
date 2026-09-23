# Small adjustments that change how the system behaves, never what is installed.
# Why each of these numbers and not the defaults: docs/REFERENCE.md

data="$(where)"

# Stars while typing a sudo password, so a terminal does not look frozen.
render "${data}/20-pwfeedback" | sudoers_rule 20-pwfeedback

# Colour, which pacman ships switched off. Parallel downloads it already has.
pacman_include "${data}/arch-os-options.conf"

# The hardware watchdogs, which nothing here uses and which delay shutdown.
mkdir -p "${MNT}/etc/modprobe.d"
render "${data}/blacklist-watchdog.conf" >"${MNT}/etc/modprobe.d/blacklist-watchdog.conf"

# Debug packages nobody asked for, built alongside every AUR package. This is
# the one thing in here makepkg is told; the compiler flags are left as Arch
# sets them - see docs/REFERENCE.md for why -march=native is not among them.
mkdir -p "${MNT}/etc/makepkg.conf.d"
render "${data}/makepkg.conf" >"${MNT}/etc/makepkg.conf.d/arch-os.conf"

# ----------------------------------------------------------------------------

# How much written data may pile up in memory before the kernel moves it, and
# how eagerly directory and inode entries are reclaimed.
# https://wiki.archlinux.org/title/Sysctl
render "${data}/99-arch-os-memory.conf" >"${MNT}/etc/sysctl.d/99-arch-os-memory.conf"

# cubic backs off on any packet loss, which congested wifi and long-distance
# links produce without actually being full. bbr judges the path by the delay
# it measures instead, so it keeps sending.
# https://wiki.archlinux.org/title/Sysctl#TCP_congestion_algorithm
render "${data}/99-arch-os-bbr.conf" >"${MNT}/etc/sysctl.d/99-arch-os-bbr.conf"

# Transparent huge pages are worth having; stopping a program to produce one is
# not. https://docs.kernel.org/admin-guide/mm/transhuge.html
mkdir -p "${MNT}/etc/tmpfiles.d"
render "${data}/arch-os-hugepages.conf" >"${MNT}/etc/tmpfiles.d/arch-os-hugepages.conf"

# How long a service gets to stop, and how many files anything may open. Both
# numbers of the limit are written out: given one, systemd moves the soft limit
# to it as well, which is the change this is deliberately not making.
for scope in system user; do
    mkdir -p "${MNT}/etc/systemd/${scope}.conf.d"
    render "${data}/manager.conf" >"${MNT}/etc/systemd/${scope}.conf.d/10-arch-os.conf"
done

# What the journal may take.
mkdir -p "${MNT}/etc/systemd/journald.conf.d"
render "${data}/journald.conf" >"${MNT}/etc/systemd/journald.conf.d/10-arch-os.conf"

# The queueing each kind of disk is served best by. The kernel picks by how a
# device is attached and not by what is behind it, and NVMe is left as it found
# it - it has hardware queues of its own.
# https://wiki.archlinux.org/title/Improving_performance#Changing_I/O_scheduler
mkdir -p "${MNT}/etc/udev/rules.d"
render "${data}/60-arch-os-ioschedulers.rules" >"${MNT}/etc/udev/rules.d/60-arch-os-ioschedulers.rules"
