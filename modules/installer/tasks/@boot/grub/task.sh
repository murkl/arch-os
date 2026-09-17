# The loader the firmware starts, and how it is told to start this system.
#
# Its own task beside the systemd-boot one rather than a branch inside a shared
# one: the two write different files in different places, and which of them runs
# is an answer the yaml can declare - so a run that installs systemd-boot never
# even lists this step.
#
# grub-mkconfig reads /etc/default/grub and nothing beside it, so every line
# below is an edit of a file the grub package owns.

simulating && return 0

# The line is dropped and written again rather than spliced into: it is a shell
# assignment in a file grub-mkconfig sources, so writing it whole is both what it
# is and the only way a comma or an ampersand in the answers survives - spliced
# in with sed, both are characters that mean something to sed instead.
#
# What it says comes from module.sh, so a unified kernel image built from the
# same answers cannot disagree with this line about how the system boots.
sed -i '/^GRUB_CMDLINE_LINUX=/d' "${MNT}/etc/default/grub"
printf 'GRUB_CMDLINE_LINUX="%s"\n' "$(kernel_args)" >>"${MNT}/etc/default/grub"

arch-chroot "$MNT" grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB

sed -i "s/^GRUB_TIMEOUT=.*$/GRUB_TIMEOUT=3/" "${MNT}/etc/default/grub"
sed -i "s/^GRUB_TIMEOUT_STYLE=.*$/GRUB_TIMEOUT_STYLE=menu/" "${MNT}/etc/default/grub"

# Off by default since GRUB 2.06, and the only way the other system appears.
[ "$ARCH_OS_DUAL_BOOT_ENABLED" = "true" ] && echo 'GRUB_DISABLE_OS_PROBER=false' >>"${MNT}/etc/default/grub"

arch-chroot "$MNT" grub-mkconfig -o /boot/grub/grub.cfg

# Rebuilds the menu whenever a snapshot appears or goes. An if block rather than
# a guard because it is the last thing this task does: a guard that does not fire
# leaves 1 behind, and that is what the task hands back.
if [ "$ARCH_OS_FILESYSTEM" = "btrfs" ]; then
    arch-chroot "$MNT" systemctl enable grub-btrfsd.service
fi
