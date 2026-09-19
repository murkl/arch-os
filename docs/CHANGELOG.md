# Changelog

What each release changed, newest first. The version is `version:` in **[oak.yaml](../oak.yaml)**, and a release is the tag `v` + it. Releases before 2.0.0 are on the **[release page](https://github.com/murkl/arch-os/releases)**.

## 2.0.0 - 2026-09-18

- Rebuilt on **[Oak](https://github.com/murkl/oak)**: the interface is a runtime of its own, and everything in this repository is a module beside it
- Three modules on one image: the Installer, the Recovery, and Create boot medium for writing the USB device from any Linux machine
- Two starting points, Core and Desktop — everything else stays a row in the settings
- Every answer is kept, so an interrupted run picks up where it stopped and the next machine skips what it already knows
- A wireless network is joined from the Installer itself, before the first download - the networks in range, the passphrase, and on to the install
- The disk list is what the machine actually has, eMMC and SD cards included, and never the medium the live image is running from
- A step that fails names the module, the task, the file, the line and the exit code, and the run says how many of its tests passed
- CachyOS tuning for memory, systemd, the journal and the I/O schedulers, `/var` split onto its own btrfs subvolumes
- Both boot images are declared rather than left to the kernel package, whose template stopped building the fallback - an installation without disk encryption had a fallback entry in the boot menu and no image behind it
- The welcome page says where the project is, written out under the greeting - the machine reading it has no browser on it yet
- File sharing announces itself under the hostname as it stands rather than in capitals, so a file manager on the network lists `tux-desktop` and not `TUX-DESKTOP`
- English and German, checked against the glyph table of the font the console draws with - which now also holds the marks the interface itself draws
- One command from anywhere: `curl -Ls https://bit.ly/arch-os | bash` installs, repairs or writes a boot device, decided by the machine it opened on
- A commit is built once: the ISO on the release page is the file CI checked and booted, with signed build provenance
