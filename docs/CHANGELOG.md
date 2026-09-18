# Changelog

What each release changed, newest first. The version is `version:` in **[oak.yaml](../oak.yaml)**, and a release is the tag `v` + it. Releases before 2.0.0 are on the **[release page](https://github.com/murkl/arch-os/releases)**.

## 2.0.0 - 2026-09-18

- Rebuilt on **[Oak](https://github.com/murkl/oak)**: the interface is a runtime of its own, and everything in this repository is a module beside it
- Three modules on one image: the Installer, the Recovery, and Create boot medium for writing the USB device from any Linux machine
- Two starting points, Core and Desktop — everything else stays a row in the settings
- Every answer is kept, so an interrupted run picks up where it stopped and the next machine skips what it already knows
- A step that fails names the module, the task, the file, the line and the exit code, and the run says how many of its tests passed
- CachyOS tuning for memory, systemd, the journal and the I/O schedulers, `/var` split onto its own btrfs subvolumes
- English and German, checked against the glyph table of the font the console draws with
- One command from anywhere: `curl -Ls https://bit.ly/arch-os | bash` installs, repairs or writes a boot device, decided by the machine it opened on
- A commit is built once: the ISO on the release page is the file CI checked and booted, with signed build provenance
