set fish_greeting

# Colourful man pages.
if command -v bat >/dev/null
    set -gx MANPAGER "sh -c 'col -bx | bat -l man -p'"
    set -gx MANROFFOPT -c
end

# The same as in .bashrc, where the reason is written.
set -gx LS_COLORS "di=1;34:ln=36:so=35:pi=33:ex=32:bd=33;1:cd=33;1:su=31:sg=31:tw=34:ow=34"

test -f "$HOME/.aliases" && source "$HOME/.aliases"

command -v zoxide >/dev/null && zoxide init fish | source

# Ctrl+R searches the history, Ctrl+T picks a file, Alt+C changes into a folder.
command -v fzf >/dev/null && fzf --fish | source

# The prompt, outside a text console where the font can draw it. The same test
# the other two shells make, spelled the same way - why it is TERM and not the
# terminal device is written out once, in .bashrc.
if test "$TERM" != linux
    and command -v starship >/dev/null
    starship init fish | source
end
