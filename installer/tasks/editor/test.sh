# An $EDITOR naming nothing installed looks like a valid line.
editor="$(sed -n 's/^EDITOR=//p' "${MNT}/etc/environment")"
[ -n "$editor" ]
has_command "$editor"

# Every file as written, in both homes. Contents checked by loading them in
# vim 9.2, neovim 0.12, nano 9.2, micro 2.0.15 and helix 25.07. An empty folder
# compares nothing, so it fails.
src="$(where)/${editor}"
files="$(find "$src" -type f -printf '%P\n')"
[ -n "$files" ]
while IFS= read -r file; do
    cmp -s "${src}/${file}" "${MNT}/root/${file}"
    cmp -s "${src}/${file}" "$(user_home)/${file}"
done <<<"$files"
