# The editor chosen, with a small configuration of its own: a theme close to
# the palette the rest of the system is drawn in, and the few settings that make
# it read like any other editor. Nothing beyond what it ships with - no plugins,
# and nothing to update but the package.
#
# data/<command>/ is a home: every file in it lands at the same place in root's
# home and in the account's. A home rather than /etc, which belongs to the
# package and would leave a .pacnew to merge on every update.

src="$(where)/$(editor_command)"

# nano's own highlighting covers a handful of languages, and its nanorc reaches
# for the rest here.
if [ "$ARCH_OS_EDITOR" = "nano" ]; then
    chroot_pacman_install nano-syntax-highlighting
fi

while IFS= read -r file; do
    for home in "${MNT}/root" "${MNT}/home/${ARCH_OS_USERNAME}"; do
        mkdir -p "$(dirname "${home}/${file}")"
        render "${src}/${file}" >"${home}/${file}"
    done
done < <(find "$src" -type f -printf '%P\n')

own_home
