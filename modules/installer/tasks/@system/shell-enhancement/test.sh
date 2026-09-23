# Every shell gets the prompt through .bashrc. zsh additionally becomes the one
# that opens; fish cannot be a login shell, so .bashrc hands over to it, and
# that line has to be in there or fish is installed and never seen.

home="${MNT}/home/${ARCH_OS_USERNAME}"

[ "$ARCH_OS_SHELL_ENHANCEMENT_SHELL" != "zsh" ] ||
    arch-chroot "$MNT" getent passwd "$ARCH_OS_USERNAME" | grep -q ':/usr/bin/zsh$'
[ "$ARCH_OS_SHELL_ENHANCEMENT_SHELL" != "fish" ] ||
    grep -q 'exec fish' "${home}/.bashrc"
# And its colours, which fish keeps in a file of its own rather than in the one
# written here.
[ "$ARCH_OS_SHELL_ENHANCEMENT_SHELL" != "fish" ] ||
    grep -q '^SETUVAR fish_color_command:' "${home}/.config/fish/fish_variables"

# Every rendered file, on two counts. A placeholder that survives is a comment
# or a word that reads perfectly well and does nothing it stood for, and whoever
# meets it is the person using the machine rather than the run that wrote it.
# And splicing one file into another is how a stray character lands in the
# middle of a line: a .bashrc that does not parse is a login that says so on
# every terminal the machine opens.
for file in "${MNT}/root/.bashrc" "${MNT}/root/.aliases" \
    "${home}/.bashrc" "${home}/.aliases"; do

    if grep -q '{{' "$file"; then
        echo "${file} still carries a placeholder" >&2
        exit 1
    fi
    bash -n "$file"
done
