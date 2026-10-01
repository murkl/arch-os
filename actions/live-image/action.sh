# Arch on top: an image built the same way by somebody else is another system.
on_live_image
grep -qs '^ID=arch$' /etc/os-release
