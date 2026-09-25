# Changelog

What each release changed, newest first. Written by the run that publishes it, out of what landed on `main` since the release before — never by hand.

## [2.1.0](https://github.com/murkl/arch-os/compare/v2.0.0...v2.1.0) (2026-09-25)


### Features

* a Recovery partition in the boot menu, and a firewall of public and home zones ([#133](https://github.com/murkl/arch-os/issues/133)) ([e4e57b4](https://github.com/murkl/arch-os/commit/e4e57b44bc3445fc3730555aeb1e26d3bcad4cfc))
* a Recovery partition that opens on its menu in your language, Bazaar and Extension Manager, and clearer settings ([#134](https://github.com/murkl/arch-os/issues/134)) ([24b78dc](https://github.com/murkl/arch-os/commit/24b78dc8451d19ba9d4e91b9a913d718fa0efb88))
* a welcome page under the wordmark, whether this machine is online, a network in the Recovery, passwords in the interface and a configured editor ([#135](https://github.com/murkl/arch-os/issues/135)) ([6513b17](https://github.com/murkl/arch-os/commit/6513b17adecad3e14e362596bf771fd1d40260b9))
* fix kernel, file system, loader and shell, detect drivers and mark AUR tasks optional ([4841ccc](https://github.com/murkl/arch-os/commit/4841ccce8ae50ce3cc3efd1d594120d662c16e2f))
* install Arch OS as the only system and harden installer, recovery and imager ([4841ccc](https://github.com/murkl/arch-os/commit/4841ccce8ae50ce3cc3efd1d594120d662c16e2f))
* Installer or Recovery chosen under the wordmark, and a menu that says Install, Repair or Create ([#137](https://github.com/murkl/arch-os/issues/137)) ([83d0cca](https://github.com/murkl/arch-os/commit/83d0cca774753f0819f9aac38077cfebdc76f916))
* let the installer ask which text editor to install and set as default ([4841ccc](https://github.com/murkl/arch-os/commit/4841ccce8ae50ce3cc3efd1d594120d662c16e2f))
* let the installer set up a firewall, an SSH server and Flatpak ([4841ccc](https://github.com/murkl/arch-os/commit/4841ccce8ae50ce3cc3efd1d594120d662c16e2f))
* load a console font with Cyrillic so more languages need only a catalog ([4841ccc](https://github.com/murkl/arch-os/commit/4841ccce8ae50ce3cc3efd1d594120d662c16e2f))
* open only current installations in the Recovery and bring back the gaming tools ([4841ccc](https://github.com/murkl/arch-os/commit/4841ccce8ae50ce3cc3efd1d594120d662c16e2f))
* remove stale firmware boot entries and show the image download's progress on Oak 0.7.0 ([4841ccc](https://github.com/murkl/arch-os/commit/4841ccce8ae50ce3cc3efd1d594120d662c16e2f))


### Bug Fixes

* changed to bit.ly/archos ([#128](https://github.com/murkl/arch-os/issues/128)) ([f2246f4](https://github.com/murkl/arch-os/commit/f2246f44c50d73906d1cb5e0b8e691faf6e85330))
* rename the core and shell tweaks in German to Optimierungen ([4841ccc](https://github.com/murkl/arch-os/commit/4841ccce8ae50ce3cc3efd1d594120d662c16e2f))
* screenshots ([#130](https://github.com/murkl/arch-os/issues/130)) ([e134be7](https://github.com/murkl/arch-os/commit/e134be77a3d8c1461ff19108c43a6307d28c4a06))

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
