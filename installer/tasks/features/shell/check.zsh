#!/usr/bin/env zsh
# Types into an interactive zsh that reads the given zshrc and checks where the
# word keys stop and which title the tab gets. Usage: check.zsh <zshrc>
emulate -L zsh
setopt extended_glob
zmodload zsh/zpty zsh/zselect zsh/system || exit 1
zshrc=${1:A}
[[ -r $zshrc ]] || { print -u2 "no zshrc: $1"; exit 1 }
tmp=$(mktemp -d) || exit 1
# Only this shell cleans up: a zpty child is a fork of it and inherits the trap.
main=$sysparams[pid]
trap '[[ $sysparams[pid] == $main ]] && { zpty -d t 2>/dev/null; rm -rf $tmp }' EXIT

typeset -A keys=(
    ctrl-backspace $'\b'
    ctrl-left $'\e[1;5D'
    ctrl-right $'\e[1;5C'
    ctrl-delete $'\e[3;5~'
    alt-backspace $'\e\x7f'
)
# typed | keys pressed after it | what is left of it
cases=(
    'gnome-extensions-app|ctrl-backspace|gnome-extensions-'
    'gnome-extensions-app|ctrl-backspace ctrl-backspace|gnome-'
    '/usr/share/applications|ctrl-backspace|/usr/share/'
    'snake_case.txt|alt-backspace|snake_case.'
    'key=value:more|ctrl-left ctrl-delete|key=value:'
    'one-two|ctrl-left ctrl-left ctrl-right ctrl-delete|one-'
)
# folder below the home | title of the tab there. proj is a repository.
titles=(
    'proj|proj'
    'proj/sub|proj/sub'
    'plain|~/plain'
)

# await waits until test $1 $2 holds, collecting the terminal's output in $out.
await() {
    local deadline=$((SECONDS + 10)) chunk
    until test $1 $2 || ((SECONDS >= deadline)); do
        zpty -rt t chunk && out+=$chunk || zselect -t 5
    done
    test $1 $2
}

failed=0
for c in $cases; do
    typed=${c%%|*} rest=${c#*|}
    pressed=(${(s: :)rest%%|*}) want=${rest#*|}
    # A home of its own per case: a history line from the case before would be
    # offered by the autosuggestions and taken by the end-of-line key. The XDG
    # variables go too, or zoxide writes to the caller's real database.
    home=$tmp/$((++n))
    mkdir $home && cp $zshrc $home/.zshrc
    # Keys go in only once the line editor runs: before that the terminal is
    # still cooked, and ^? there erases the ESC of Alt+Backspace.
    print -r -- 'autoload -Uz add-zle-hook-widget; _keys_ready() { : >$HOME/ready }; add-zle-hook-widget line-init _keys_ready' >>$home/.zshrc
    zpty t "env -u TERM_PROGRAM -u TMUX -u XDG_CONFIG_HOME -u XDG_CACHE_HOME -u XDG_DATA_HOME -u XDG_STATE_HOME HOME=$home ZDOTDIR=$home TERM=xterm-256color zsh -i"
    got=
    if await -e $home/ready; then
        # The line writes what is left of the word to a file once the keys are done.
        zpty -w -n t "print -r -- @$typed"
        for k in $pressed; do
            zselect -t 5
            zpty -w -n t ${keys[$k]}
        done
        zselect -t 5
        zpty -w -n t $'\x05@>'$home/out$'\r'
        await -s $home/out && got=${${"$(<$home/out)"#@}%@}
    fi
    zpty -d t
    if [[ $got == $want ]]; then
        print -r -- "ok    $typed (${rest%%|*}): $got"
    else
        print -r -- "FAIL  $typed (${rest%%|*}): got '$got', want '$want'"
        failed=1
    fi
done

# One shell for every title: each cd draws a new prompt and with it the title.
home=$tmp/$((++n))
mkdir -p $home/proj/.git $home/proj/sub $home/plain && cp $zshrc $home/.zshrc
print -r -- 'autoload -Uz add-zle-hook-widget; _keys_ready() { : >$HOME/ready }; add-zle-hook-widget line-init _keys_ready' >>$home/.zshrc
zpty t "env -u TERM_PROGRAM -u TMUX -u XDG_CONFIG_HOME -u XDG_CACHE_HOME -u XDG_DATA_HOME -u XDG_STATE_HOME HOME=$home ZDOTDIR=$home TERM=xterm-256color zsh -i"
await -e $home/ready
for c in $titles; do
    dir=${c%%|*} want=${c#*|} got= out=
    rm -f $home/ready
    zpty -w -n t "cd ${(q)home}/$dir"$'\r'
    if await -e $home/ready; then
        # The title comes before the prompt and so before ready: it is in the terminal already.
        while zpty -rt t chunk; do out+=$chunk; done
        osc=(${(M)${(ps:\a:)out}:#*$'\e]0;'*})
        got=${osc[-1]##*$'\e]0;'}
    fi
    if [[ $got == $want ]]; then
        print -r -- "ok    cd $dir: $got"
    else
        print -r -- "FAIL  cd $dir: got '${(V)got}', want '$want'"
        failed=1
    fi
done
zpty -d t
exit $failed
