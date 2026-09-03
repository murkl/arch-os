# The wireless device to use.
#
# The first station is taken rather than asked for: a machine with two wireless
# cards is rare enough that a prompt would cost everyone else a question.

iwctl device list | grep -E '\bstation\b' | awk '{print $2}' | head -n 1
