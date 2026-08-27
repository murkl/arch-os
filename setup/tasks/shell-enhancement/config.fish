if status is-interactive
    # Commands to run in interactive sessions can go here
end

set fish_greeting

# Colourful man pages.
command -v bat &>/dev/null && export MANPAGER="sh -c \"col -bx | bat -l man -p\""
command -v bat &>/dev/null && export MANROFFOPT="-c"

test -f "$HOME/.aliases" && source "$HOME/.aliases"

command -v zoxide &>/dev/null && zoxide init fish | source

# The prompt, outside a text console where the font can draw it.
if not tty | string match -q "/dev/tty*"
    and command -v starship >/dev/null
    starship init fish | source
end
