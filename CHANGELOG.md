# Changelog

What each release changed, newest first. Written by the run that publishes it, out of what landed on `main` since the release before, never by hand.

## [2.0.0](https://github.com/murkl/arch-os/compare/1.9.7...v2.0.0) (2026-10-10)


### ⚠ BREAKING CHANGES

* rewrite Arch OS on the Oak runtime

### Features

* Create boot medium asks for the device each time it starts and never keeps it ([c1daf0f](https://github.com/murkl/arch-os/commit/c1daf0f3d36f83c7b33d8cb2e7308ba0dabc20e8))
* rewrite Arch OS on the Oak runtime ([ceaf586](https://github.com/murkl/arch-os/commit/ceaf58681da8b704987608777aba8b5c86df7e90))
* the boot splash names the Installer or the Recovery it starts ([c1daf0f](https://github.com/murkl/arch-os/commit/c1daf0f3d36f83c7b33d8cb2e7308ba0dabc20e8))
* the Installer carries the wireless network it joined into the new system ([c1daf0f](https://github.com/murkl/arch-os/commit/c1daf0f3d36f83c7b33d8cb2e7308ba0dabc20e8))
* the live system follows the time zone as it is answered ([c1daf0f](https://github.com/murkl/arch-os/commit/c1daf0f3d36f83c7b33d8cb2e7308ba0dabc20e8))
* the Recovery updates itself from its partition ([c1daf0f](https://github.com/murkl/arch-os/commit/c1daf0f3d36f83c7b33d8cb2e7308ba0dabc20e8))


### Bug Fixes

* German task titles start with a capital ([c1daf0f](https://github.com/murkl/arch-os/commit/c1daf0f3d36f83c7b33d8cb2e7308ba0dabc20e8))
* the console font is the size the kernel picks ([c1daf0f](https://github.com/murkl/arch-os/commit/c1daf0f3d36f83c7b33d8cb2e7308ba0dabc20e8))
* the release ISO stays under 2 GiB and its Installer fetches the Recovery ([c1daf0f](https://github.com/murkl/arch-os/commit/c1daf0f3d36f83c7b33d8cb2e7308ba0dabc20e8))
* VM support on a desktop no longer makes GNOME fail on jack2 ([c1daf0f](https://github.com/murkl/arch-os/commit/c1daf0f3d36f83c7b33d8cb2e7308ba0dabc20e8))

## 1.9.7 and before

On the **[release page](https://github.com/murkl/arch-os/releases)**. This file begins with the first release a run wrote, and every one after it is added above this line.
