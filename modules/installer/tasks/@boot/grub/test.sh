# A machine that will not boot is the one failure nothing later makes up for, so
# what is checked is what the firmware reaches for.

[ -f "${MNT}/boot/grub/grub.cfg" ]

# The drop-in directory is recent, and a drop-in grub-mkconfig never sourced
# leaves a menu that boots with the stock command line instead of this one.
grep -qF -- "$(kernel_options)" "${MNT}/boot/grub/grub.cfg"

# The one root= GRUB writes itself, and no microcode image loaded a second time
# in front of a ram disk that already starts with it.
awk '
    $1 == "linux" && gsub(/(^|[[:space:]])root=/, "&") > 1 { print "two root= in:" $0; bad = 1 }
    $1 == "initrd" && /-ucode\.img/ { print "microcode loaded twice:" $0; bad = 1 }
    END { exit bad }
' "${MNT}/boot/grub/grub.cfg" >&2
