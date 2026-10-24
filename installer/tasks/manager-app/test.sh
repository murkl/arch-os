# The dock's entry as the session finds it, and its icon in hicolor, the
# fallback of every theme.
data="/home/${ARCH_OS_USERNAME}/.local/share"
arch-chroot "$MNT" desktop-file-validate "${data}/applications/system-manager.desktop"
found="$(as_user "gjs -c \"print(imports.gi.GioUnix.DesktopAppInfo.new('system-manager.desktop') !== null)\"")"
[ "$found" = true ]
icon="$(sed -n 's/^Icon=//p' "${MNT}${data}/applications/system-manager.desktop")"
[ -s "${MNT}${data}/icons/hicolor/scalable/apps/${icon}.svg" ]
