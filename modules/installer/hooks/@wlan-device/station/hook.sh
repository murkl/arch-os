# The first station is taken rather than asked for: a machine with two wireless
# cards is rare enough that a prompt would cost everyone else a question.
#
# iwctl draws a table for a human: it is coloured, and it puts the reset
# sequence at the start of the line that follows a coloured one - which is the
# first device row. Read as it comes, the first column of that row is the escape
# and not a name, and a machine with one card, which is every laptop, hands the
# whole of the wireless flow a device called "\e[0m". So the colours come off
# first, exactly as they do in the scan beside this.
#
# The match is remembered rather than exited on: a filter that closes the pipe
# leaves iwctl with a write error, and under pipefail that is a failed hook
# instead of an answer.

iwctl device list |
    sed -e 's/\x1b\[[0-9;]*m//g' -e 's/\r//' |
    awk '!found && $NF == "station" { print $1; found = 1 }'
