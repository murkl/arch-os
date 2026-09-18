# Both files are here and neither is empty. Whether the image is what it says it
# is, is the next task's whole question.
simulating && return 0

[ -s "$(image)" ]
[ -s "$(checksum)" ]
