# There is somewhere to install a flatpak from: Flathub comes with the package
# rather than from here, which is a promise of the package this reads back.

remotes="$(arch-chroot "$MNT" flatpak remotes --system --columns=name)"
grep -qx flathub <<<"$remotes"
