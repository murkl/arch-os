# Both files are on this machine and neither is empty. Whether the image is what
# it says it is, is the next task's whole question - this one only answers for
# the download.
debugging && return 0

[ -s "$(image)" ]
[ -s "$(checksum)" ]
