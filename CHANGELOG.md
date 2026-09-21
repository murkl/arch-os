# Changelog

What each release changed, newest first. Written by the run that publishes it, out of what landed on `main` since the release before — never by hand.

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
