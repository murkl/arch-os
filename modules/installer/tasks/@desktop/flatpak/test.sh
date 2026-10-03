remotes="$(arch-chroot "$MNT" flatpak remotes --system --columns=name)"
grep -qx flathub <<<"$remotes"
