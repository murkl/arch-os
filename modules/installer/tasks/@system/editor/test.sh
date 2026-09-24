# Every file the editor was given is where it looks for it, in both homes, as it
# was written. What is in them was held to the editors themselves: each file was
# loaded by its own - vim 9.2, neovim 0.12, nano 9.2, micro 2.0.15, helix 25.07 -
# and a copy with an unknown setting or theme refused, before it went in here.

src="$(where)/$(editor_command)"
while IFS= read -r file; do
    cmp -s "${src}/${file}" "${MNT}/root/${file}"
    cmp -s "${src}/${file}" "${MNT}/home/${ARCH_OS_USERNAME}/${file}"
done < <(find "$src" -type f -printf '%P\n')
