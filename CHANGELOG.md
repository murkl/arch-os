# Changelog

What each release changed, newest first. Written by the run that publishes it, out of what landed on `main` since the release before — never by hand.

## [2.1.0](https://github.com/murkl/arch-os/compare/v2.0.0...v2.1.0) (2026-10-03)


### Features

* a copy to a USB drive shows its real progress instead of finishing into memory ([#141](https://github.com/murkl/arch-os/issues/141)) ([ee5ef2e](https://github.com/murkl/arch-os/commit/ee5ef2e6e07ad2806934232f4d5638d7bc5e897f))
* a finished install ends on a page of choices, open wifi joins without a passphrase, and the Recovery app only asks yes or no ([#145](https://github.com/murkl/arch-os/issues/145)) ([6dbf110](https://github.com/murkl/arch-os/commit/6dbf11015c843cd8c18bd06ae39c0007fcb9df7f))
* a Recovery partition in the boot menu, and a firewall of public and home zones ([#133](https://github.com/murkl/arch-os/issues/133)) ([e4e57b4](https://github.com/murkl/arch-os/commit/e4e57b44bc3445fc3730555aeb1e26d3bcad4cfc))
* a Recovery partition that opens on its menu in your language, Bazaar and Extension Manager, and clearer settings ([#134](https://github.com/murkl/arch-os/issues/134)) ([24b78dc](https://github.com/murkl/arch-os/commit/24b78dc8451d19ba9d4e91b9a913d718fa0efb88))
* a welcome page under the wordmark, whether this machine is online, a network in the Recovery, passwords in the interface and a configured editor ([#135](https://github.com/murkl/arch-os/issues/135)) ([6513b17](https://github.com/murkl/arch-os/commit/6513b17adecad3e14e362596bf771fd1d40260b9))
* fix kernel, file system, loader and shell, detect drivers and mark AUR tasks optional ([4841ccc](https://github.com/murkl/arch-os/commit/4841ccce8ae50ce3cc3efd1d594120d662c16e2f))
* GNOME Software and the Extensions app back, as GNOME ships them ([#139](https://github.com/murkl/arch-os/issues/139)) ([b6287d1](https://github.com/murkl/arch-os/commit/b6287d13bed4d9ec9ae84b636b84f1dac801e537))
* install Arch OS as the only system and harden installer, recovery and imager ([4841ccc](https://github.com/murkl/arch-os/commit/4841ccce8ae50ce3cc3efd1d594120d662c16e2f))
* Installer or Recovery chosen under the wordmark, and a menu that says Install, Repair or Create ([#137](https://github.com/murkl/arch-os/issues/137)) ([83d0cca](https://github.com/murkl/arch-os/commit/83d0cca774753f0819f9aac38077cfebdc76f916))
* let the installer ask which text editor to install and set as default ([4841ccc](https://github.com/murkl/arch-os/commit/4841ccce8ae50ce3cc3efd1d594120d662c16e2f))
* let the installer set up a firewall, an SSH server and Flatpak ([4841ccc](https://github.com/murkl/arch-os/commit/4841ccce8ae50ce3cc3efd1d594120d662c16e2f))
* load a console font with Cyrillic so more languages need only a catalog ([4841ccc](https://github.com/murkl/arch-os/commit/4841ccce8ae50ce3cc3efd1d594120d662c16e2f))
* on Oak 0.18.0 the last page names the disk it erases, every question names its type, the installer waits for the live image's keyring, and CI installs and repairs the ISO end to end ([#151](https://github.com/murkl/arch-os/issues/151)) ([8fa6a92](https://github.com/murkl/arch-os/commit/8fa6a922eb41d1497a4d941e6ffb76aaec96179c))
* open only current installations in the Recovery and bring back the gaming tools ([4841ccc](https://github.com/murkl/arch-os/commit/4841ccce8ae50ce3cc3efd1d594120d662c16e2f))
* remove stale firmware boot entries and show the image download's progress on Oak 0.7.0 ([4841ccc](https://github.com/murkl/arch-os/commit/4841ccce8ae50ce3cc3efd1d594120d662c16e2f))
* test results on the page a run ends on, a shared log that retries and says why it failed, and shorter texts throughout ([#149](https://github.com/murkl/arch-os/issues/149)) ([54a0d64](https://github.com/murkl/arch-os/commit/54a0d64f6e5d9f919b1d47b88e8570a3efd65366))
* the AUR helper as a switch, the starting points on one page, and one shared library for every module ([#146](https://github.com/murkl/arch-os/issues/146)) ([c720f58](https://github.com/murkl/arch-os/commit/c720f58ac0503dea3a59986930a5307e857c9a9c))
* the browser, the backup app, Bazaar and Extension Manager as settings, and the Recovery among the applications ([#144](https://github.com/murkl/arch-os/issues/144)) ([30fa3e4](https://github.com/murkl/arch-os/commit/30fa3e438a216738f596dcb28f9628045d1210a5))
* the network declared per module, a wireless network in the settings wherever there is a card, and a cable on the Recovery partition ([#138](https://github.com/murkl/arch-os/issues/138)) ([7a79ebb](https://github.com/murkl/arch-os/commit/7a79ebb69a8a6df0740e6a430e05479f062ccd0b))
* the wireless network in the Configuration and straight after the keyboard, a yes or no before the work, Firefox by default and an encrypted Core ([#147](https://github.com/murkl/arch-os/issues/147)) ([eace060](https://github.com/murkl/arch-os/commit/eace0606e3a69a42400c5653c21713cdb7147541))
* the wireless network on the menu, a cable preferred, and the log of a failed run shared as a code ([#143](https://github.com/murkl/arch-os/issues/143)) ([d5b283d](https://github.com/murkl/arch-os/commit/d5b283d8f3194b2e1ef00e4389ce7f154b907857))
* the wireless network's row reads Configure the wireless network ([#148](https://github.com/murkl/arch-os/issues/148)) ([32aa073](https://github.com/murkl/arch-os/commit/32aa0733d6a32a937e04182fbbccd25dde635149))


### Bug Fixes

* a command is looked for inside the new system, so helix passes its ([7a79ebb](https://github.com/murkl/arch-os/commit/7a79ebb69a8a6df0740e6a430e05479f062ccd0b))
* changed to bit.ly/archos ([#128](https://github.com/murkl/arch-os/issues/128)) ([f2246f4](https://github.com/murkl/arch-os/commit/f2246f44c50d73906d1cb5e0b8e691faf6e85330))
* rename the core and shell tweaks in German to Optimierungen ([4841ccc](https://github.com/murkl/arch-os/commit/4841ccce8ae50ce3cc3efd1d594120d662c16e2f))
* screenshots ([#130](https://github.com/murkl/arch-os/issues/130)) ([e134be7](https://github.com/murkl/arch-os/commit/e134be77a3d8c1461ff19108c43a6307d28c4a06))
* the Recovery opens a system with a broken fstab and restores the exact kernel, and a reinstall without encryption over an encrypted disk works ([54932ec](https://github.com/murkl/arch-os/commit/54932eca2bf4c5d0e2473c4c00dc7a6abedbf285))

## [2.0.0](https://github.com/murkl/arch-os/compare/1.9.7...v2.0.0) (2026-09-21)


### ⚠ BREAKING CHANGES

* nothing from 1.x carries over - no answer file, no module, no invocation reads the same. Boot the new ISO or run the new tar.gz; there is no upgrade path from installer.sh.

### Features

* add a container engine task, usable the moment podman is installed ([bd39501](https://github.com/murkl/arch-os/commit/bd3950109907de41b4cfc01fdacb68e8a7f778ac))
* add the GNOME desktop task, made flatpak-safe and polished (icons, favorites) ([ae72123](https://github.com/murkl/arch-os/commit/ae72123a12ef6e2811c101653af4c1a18cbc78e7))
* build the bootable ISO, and let a crashed interface stop at the prompt instead of restarting ([35a7964](https://github.com/murkl/arch-os/commit/35a79649fe73d595327791c383e7b81d7ef6c72f))
* fix wireless network detection, and check the console glyph table before shipping ([4b76699](https://github.com/murkl/arch-os/commit/4b766996382a217c7e6d0534300fd9ce8bab3c3d))
* refuse a dual boot onto an EFI partition that already holds a kernel ([a17df0c](https://github.com/murkl/arch-os/commit/a17df0c159038129adda1513dea9458c5fb9f572))
* rewrite Arch OS around the Oak runtime and a modular installer ([8ec90c6](https://github.com/murkl/arch-os/commit/8ec90c62c86a6bc698f3dec0bd89fd6bed3ea9ef))
* tune BBR/fq, vm.max_map_count and -march=native, and ask the recovery password once ([68efc9f](https://github.com/murkl/arch-os/commit/68efc9f8f193036043953dd03e19bf8f6435ff8a))
* verify a release against GitHub's checksum before installing or writing it ([e46c6d3](https://github.com/murkl/arch-os/commit/e46c6d3a4b45695028209938559e5badf28fb27b))

## 1.9.7 and before

On the **[release page](https://github.com/murkl/arch-os/releases)**. This file begins with the first release a run wrote, and every one after it is added above this line.
