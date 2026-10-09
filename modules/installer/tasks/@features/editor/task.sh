# The editor chosen, the one everything that asks for an editor opens, and a
# small configuration of its own: a theme close to the system's palette and
# nothing to update but the package.

# The command, which is also the folder its configuration lies in.
command="$ARCH_OS_EDITOR"
[ "$command" = "neovim" ] && command=nvim

# sudoedit, git and systemctl edit read $EDITOR and fall back on vi, which base
# does not ship. pam_env reads this one file, so it is an edit.
# https://wiki.archlinux.org/title/Environment_variables
render "$(where)/environment" EDITOR="$command" >>"${MNT}/etc/environment"

# nano's own highlighting covers a handful of languages; its nanorc reaches here.
if [ "$ARCH_OS_EDITOR" = "nano" ]; then
    chroot_pacman_install nano-syntax-highlighting
fi

# data/<command>/ is a home: each file lands at the same place in root's and in
# the account's, never in /etc, which belongs to the package.
src="$(where)/${command}"
while IFS= read -r file; do
    for home in "${MNT}/root" "${MNT}/home/${ARCH_OS_USERNAME}"; do
        mkdir -p "$(dirname "${home}/${file}")"
        render "${src}/${file}" >"${home}/${file}"
    done
done < <(find "$src" -type f -printf '%P\n')

own_home
