# None of these change what is installed. They change how it behaves in the
# small ways that are noticed every day.

simulating && return 0

# Stars while typing a sudo password, so a terminal does not look frozen.
sudoers_rule 20-pwfeedback 'Defaults pwfeedback'

# Parallel downloads and colour, which pacman ships switched off. pacman has
# no drop-in directory - every setting and every repository has to be a
# section of this one file - so this is an edit, and one of the few places a
# .pacnew is still possible.
sed -i 's/^#ParallelDownloads/ParallelDownloads/' "${MNT}/etc/pacman.conf"
sed -i 's/^#Color/Color\nILoveCandy/' "${MNT}/etc/pacman.conf"

# The hardware watchdogs, which nothing here uses and which delay shutdown.
mkdir -p "${MNT}/etc/modprobe.d"
{
    echo 'blacklist sp5100_tco'
    echo 'blacklist iTCO_wdt'
} >"${MNT}/etc/modprobe.d/blacklist-watchdog.conf"

# Debug packages nobody asked for, built alongside every AUR package. As a
# drop-in: /etc/makepkg.conf belongs to pacman and is rewritten often enough that
# editing it would leave a .pacnew to merge after most pacman updates.
mkdir -p "${MNT}/etc/makepkg.conf.d"
{
    echo '# Written by the Arch OS Installer.'
    echo 'OPTIONS+=(!debug)'
} >"${MNT}/etc/makepkg.conf.d/arch-os.conf"

# ----------------------------------------------------------------------------

# How much written data may pile up in memory before the kernel starts moving it
# to the disk. The default is a share of the memory - a fifth of it before a
# program that writes is made to wait, a tenth before the flusher threads start -
# and on a machine with 32 GB that is six gigabytes leaving in one burst, which
# is the second or two everything else stops moving for. As bytes, the ceiling is
# what the disk can keep up with rather than what the memory happens to be.
#
# vfs_cache_pressure halves how eagerly directory and inode entries are
# reclaimed. They are small and expensive to look up again, and everything that
# walks a tree - a file manager, a search, a build - pays for each one that went.
# https://wiki.archlinux.org/title/Sysctl
{
    echo '# Written by the Arch OS Installer.'
    echo 'vm.dirty_bytes = 268435456'
    echo 'vm.dirty_background_bytes = 67108864'
    echo 'vm.dirty_writeback_centisecs = 1500'
    echo 'vm.vfs_cache_pressure = 50'
} >"${MNT}/etc/sysctl.d/99-arch-os-memory.conf"

# ----------------------------------------------------------------------------

# Transparent huge pages are worth having; stopping a program to produce one is
# not. On the default a program asking for memory waits while the kernel shuffles
# pages around to free a contiguous block. defer+madvise hands out what is
# already there and leaves the shuffling to khugepaged - except where a program
# asked for huge pages outright, which is a program that has said it will wait.
# https://docs.kernel.org/admin-guide/mm/transhuge.html
mkdir -p "${MNT}/etc/tmpfiles.d"
{
    echo '# Written by the Arch OS Installer.'
    echo 'w! /sys/kernel/mm/transparent_hugepage/defrag - - - - defer+madvise'
} >"${MNT}/etc/tmpfiles.d/arch-os-hugepages.conf"

# ----------------------------------------------------------------------------

# How long a service gets to stop, and how many files anything may open.
#
# systemd waits a minute and a half for a service that has stopped answering,
# and that wait is the whole of what shutting down looks like from the outside:
# a black screen with one line on it. Fifteen seconds is longer than anything
# installed here needs to write out what it holds. The start timeout is left
# alone - that one belongs to slow hardware rather than to a stuck service, and
# cutting it turns a slow boot into a failed one.
#
# The open-file limit is raised at the ceiling and not at the floor. 1024 is
# what Wine, Proton and anything built on Electron run into, and each of them
# gets past it the way the pair is meant to be used: by raising its own soft
# limit against the hard one. Moving the soft limit for everybody instead would
# hand a program that still calls select() a descriptor above FD_SETSIZE that it
# cannot watch, and that is the whole reason the floor has stayed at 1024. So
# only the ceiling moves, and what it buys is room above Arch's 524288 for the
# few things that ask for it.
#
# Both numbers are written out: given one value systemd sets the soft limit to
# it as well, which is the change this is deliberately not making.
for scope in system user; do
    mkdir -p "${MNT}/etc/systemd/${scope}.conf.d"
    {
        echo '# Written by the Arch OS Installer.'
        echo '[Manager]'
        echo 'DefaultTimeoutStopSec=15s'
        echo 'DefaultLimitNOFILE=1024:2097152'
    } >"${MNT}/etc/systemd/${scope}.conf.d/10-arch-os.conf"
done

# ----------------------------------------------------------------------------

# What the journal may take. Its ceiling is a tenth of the file system it sits
# on, capped at 4 GB, which on any disk sold today means it never reaches either
# and keeps every line there has ever been. 200 MB is months of an ordinary
# desktop, and the disk belongs to the system on it.
mkdir -p "${MNT}/etc/systemd/journald.conf.d"
{
    echo '# Written by the Arch OS Installer.'
    echo '[Journal]'
    echo 'SystemMaxUse=200M'
} >"${MNT}/etc/systemd/journald.conf.d/10-arch-os.conf"

# ----------------------------------------------------------------------------

# The queueing each kind of disk is served best by. The kernel picks by how a
# device is attached and not by what is behind it, so everything on a SCSI or
# SATA bus gets mq-deadline: it orders requests by age and shares nothing out,
# which on a spinning disk is what makes one large copy stop everything else.
# bfq divides the disk between processes instead, and the seeks it saves pay for
# what it costs to decide. NVMe is left as the kernel found it - it has hardware
# queues of its own, and a scheduler in front of them adds latency for nothing.
# https://wiki.archlinux.org/title/Improving_performance#Changing_I/O_scheduler
mkdir -p "${MNT}/etc/udev/rules.d"
{
    echo '# Written by the Arch OS Installer.'
    echo 'ACTION=="add|change", KERNEL=="sd[a-z]*", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq"'
    echo 'ACTION=="add|change", KERNEL=="sd[a-z]*|mmcblk[0-9]*", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="mq-deadline"'
} >"${MNT}/etc/udev/rules.d/60-arch-os-ioschedulers.rules"
