# The image is on this machine and is what it says it is. The task checked that
# already and threw a damaged file away - this reads back what survived, which
# is the one thing the next task writes to a device.
debugging && return 0

[ -s "$(image)" ]
(cd "$HERE" && sha256sum -c "$(basename "$(image)").sha256" >/dev/null 2>&1)
