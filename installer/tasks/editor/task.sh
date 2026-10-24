# No plugins, so the package is all there is to update.

# The command, also the name of its folder in data/.
command="$ARCH_OS_EDITOR"
[ "$command" = "neovim" ] && command=nvim

# sudoedit, git and systemctl edit fall back on vi, which base lacks. Appended,
# since pam_env reads no drop-in.
# https://wiki.archlinux.org/title/Environment_variables
render "$(where)/environment" EDITOR="$command" >>"${MNT}/etc/environment"

# nano's own highlighting covers few languages. data/nano includes this set.
if [ "$ARCH_OS_EDITOR" = "nano" ]; then
    chroot_pacman_install nano-syntax-highlighting
fi

# data/<command>/ mirrors a home and lands in root's and the account's, not in
# /etc, which the package owns. Listed first, so a missing folder fails.
src="$(where)/${command}"
files="$(find "$src" -type f -printf '%P\n')"
while IFS= read -r file; do
    for home in "${MNT}/root" "$(user_home)"; do
        mkdir -p "$(dirname "${home}/${file}")"
        render "${src}/${file}" >"${home}/${file}"
    done
done <<<"$files"

own_home
