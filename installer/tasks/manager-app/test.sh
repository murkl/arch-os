# The entry the dock names, found as the account's session looks it up, and the
# icon it names in hicolor, where every theme falls back to.
data="/home/${ARCH_OS_USERNAME}/.local/share"
arch-chroot "$MNT" desktop-file-validate "${data}/applications/system-manager.desktop"
found="$(as_user "gjs -c \"print(imports.gi.GioUnix.DesktopAppInfo.new('system-manager.desktop') !== null)\"")"
[ "$found" = true ]
icon="$(sed -n 's/^Icon=//p' "${MNT}${data}/applications/system-manager.desktop")"
[ -s "${MNT}${data}/icons/hicolor/scalable/apps/${icon}.svg" ]
