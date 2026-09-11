# The two that would be noticed if they silently stopped being written: the
# drop-in sudo reads, and the setting pacman ships switched off.
debugging && return 0

[ -f "${MNT}/etc/sudoers.d/20-pwfeedback" ]
grep -q '^ParallelDownloads' "${MNT}/etc/pacman.conf"
