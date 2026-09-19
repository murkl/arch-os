# Small adjustments that change how the system behaves, never what is installed.
# Why each of these numbers and not the defaults: docs/REFERENCE.md

simulating && return 0

# Stars while typing a sudo password, so a terminal does not look frozen.
sudoers_rule 20-pwfeedback 'Defaults pwfeedback'

# Parallel downloads and colour, which pacman ships switched off. A repository
# and every setting are sections of this one file and pacman reads no drop-in
# directory, so this is an edit.
sed -i 's/^#ParallelDownloads/ParallelDownloads/' "${MNT}/etc/pacman.conf"
sed -i 's/^#Color/Color\nILoveCandy/' "${MNT}/etc/pacman.conf"

# The hardware watchdogs, which nothing here uses and which delay shutdown.
mkdir -p "${MNT}/etc/modprobe.d"
{
    echo 'blacklist sp5100_tco'
    echo 'blacklist iTCO_wdt'
} >"${MNT}/etc/modprobe.d/blacklist-watchdog.conf"

# Debug packages nobody asked for, built alongside every AUR package. This is
# the one thing in here makepkg is told; the compiler flags are left as Arch
# sets them - see docs/REFERENCE.md for why -march=native is not among them.
mkdir -p "${MNT}/etc/makepkg.conf.d"
{
    echo '# Written by the Arch OS Installer.'
    echo 'OPTIONS+=(!debug)'
} >"${MNT}/etc/makepkg.conf.d/arch-os.conf"

# ----------------------------------------------------------------------------

# How much written data may pile up in memory before the kernel moves it, and
# how eagerly directory and inode entries are reclaimed.
# https://wiki.archlinux.org/title/Sysctl
{
    echo '# Written by the Arch OS Installer.'
    echo 'vm.dirty_bytes = 268435456'
    echo 'vm.dirty_background_bytes = 67108864'
    echo 'vm.dirty_writeback_centisecs = 1500'
    echo 'vm.vfs_cache_pressure = 50'
} >"${MNT}/etc/sysctl.d/99-arch-os-memory.conf"

# The default caps a process at 65530 mapped memory regions. Fine for most
# software, too low for some games and emulators, which crash outright rather
# than fall back to fewer, larger ones.
# https://wiki.archlinux.org/title/Gaming#Increase_vm.max_map_count
{
    echo '# Written by the Arch OS Installer.'
    echo 'vm.max_map_count = 2147483642'
} >"${MNT}/etc/sysctl.d/99-arch-os-mmap.conf"

# cubic backs off on any packet loss, which congested wifi and long-distance
# links produce without actually being full. bbr judges the path by the delay
# it measures instead, so it keeps sending.
# https://wiki.archlinux.org/title/Sysctl#TCP_congestion_algorithm
{
    echo '# Written by the Arch OS Installer.'
    echo 'net.core.default_qdisc = fq'
    echo 'net.ipv4.tcp_congestion_control = bbr'
} >"${MNT}/etc/sysctl.d/99-arch-os-bbr.conf"

# Transparent huge pages are worth having; stopping a program to produce one is
# not. https://docs.kernel.org/admin-guide/mm/transhuge.html
mkdir -p "${MNT}/etc/tmpfiles.d"
{
    echo '# Written by the Arch OS Installer.'
    echo 'w! /sys/kernel/mm/transparent_hugepage/defrag - - - - defer+madvise'
} >"${MNT}/etc/tmpfiles.d/arch-os-hugepages.conf"

# How long a service gets to stop, and how many files anything may open. Both
# numbers of the limit are written out: given one, systemd moves the soft limit
# to it as well, which is the change this is deliberately not making.
for scope in system user; do
    mkdir -p "${MNT}/etc/systemd/${scope}.conf.d"
    {
        echo '# Written by the Arch OS Installer.'
        echo '[Manager]'
        echo 'DefaultTimeoutStopSec=15s'
        echo 'DefaultLimitNOFILE=1024:2097152'
    } >"${MNT}/etc/systemd/${scope}.conf.d/10-arch-os.conf"
done

# What the journal may take.
mkdir -p "${MNT}/etc/systemd/journald.conf.d"
{
    echo '# Written by the Arch OS Installer.'
    echo '[Journal]'
    echo 'SystemMaxUse=200M'
} >"${MNT}/etc/systemd/journald.conf.d/10-arch-os.conf"

# The queueing each kind of disk is served best by. The kernel picks by how a
# device is attached and not by what is behind it, and NVMe is left as it found
# it - it has hardware queues of its own.
# https://wiki.archlinux.org/title/Improving_performance#Changing_I/O_scheduler
mkdir -p "${MNT}/etc/udev/rules.d"
{
    echo '# Written by the Arch OS Installer.'
    echo 'ACTION=="add|change", KERNEL=="sd[a-z]*", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq"'
    echo 'ACTION=="add|change", KERNEL=="sd[a-z]*|mmcblk[0-9]*", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="mq-deadline"'
} >"${MNT}/etc/udev/rules.d/60-arch-os-ioschedulers.rules"
