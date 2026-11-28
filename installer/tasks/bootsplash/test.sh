# Theme, plymouthd and a DRM driver in every image. Each can go missing without
# an error: docs/REFERENCE.md
grep -qx 'Theme=arch-os' "${MNT}/etc/plymouth/plymouthd.conf"
while read -r image; do
    contents="$(arch-chroot "$MNT" lsinitcpio "$image")"
    grep -q 'plymouthd' <<<"$contents"
    grep -q 'themes/arch-os/' <<<"$contents"
    grep -q 'gpu/drm/' <<<"$contents"
done < <(boot_images)

# Every shutdown splash starts without the boot's delay. Listed, so a renamed
# unit in the package fails here.
for unit in plymouth-halt plymouth-kexec plymouth-poweroff plymouth-reboot; do
    grep -q '^ExecStart=/usr/local/lib/arch-os/plymouthd-shutdown --mode=' "${MNT}/etc/systemd/system/${unit}.service.d/10-arch-os.conf"
    [ -z "$(unit_complaints "${unit}.service")" ]
done
