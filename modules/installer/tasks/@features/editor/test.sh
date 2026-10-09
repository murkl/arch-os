# An $EDITOR naming nothing installed looks exactly like a correct line.
editor="$(sed -n 's/^EDITOR=//p' "${MNT}/etc/environment")"
[ -n "$editor" ]
has_command "$editor"

# Every file as written, in both homes. What is in them was loaded by the
# editors themselves - vim 9.2, neovim 0.12, nano 9.2, micro 2.0.15,
# helix 25.07 - before it went in here.
src="$(where)/${editor}"
while IFS= read -r file; do
    cmp -s "${src}/${file}" "${MNT}/root/${file}"
    cmp -s "${src}/${file}" "${MNT}/home/${ARCH_OS_USERNAME}/${file}"
done < <(find "$src" -type f -printf '%P\n')
