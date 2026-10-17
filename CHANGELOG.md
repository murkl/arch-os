# Changelog

What each release changed, newest first. Written by the run that publishes it, out of what landed on `main` since the release before, never by hand.

## [2.1.0](https://github.com/murkl/arch-os/compare/v2.0.0...v2.1.0) (2026-10-17)


### Features

* a Desktop's start counts as one that worked only once its login screen or session is up ([#205](https://github.com/murkl/arch-os/issues/205)) ([ce2ba5f](https://github.com/murkl/arch-os/commit/ce2ba5f95fbbfa1ef0d1cf5223445f711018e246))
* a kernel panic restarts the machine, so the loader counts the start as failed ([#204](https://github.com/murkl/arch-os/issues/204)) ([248f726](https://github.com/murkl/arch-os/commit/248f7269f124a07ddeaff575b7984343bd826388))
* a system kept offline stays clean, its timers skip rather than fail ([#200](https://github.com/murkl/arch-os/issues/200)) ([5731f07](https://github.com/murkl/arch-os/commit/5731f0773911d58ab58c2850eb4487e55438ab6d))
* a system that does not start falls back to its fallback image, then to the Recovery ([#203](https://github.com/murkl/arch-os/issues/203)) ([384e31c](https://github.com/murkl/arch-os/commit/384e31cd9ef036de256f51fbd59ee516808bfa8b))
* an updated Recovery is signed with the system's keys whenever the system signs its boot chain ([adfaa66](https://github.com/murkl/arch-os/commit/adfaa6603d068636fda019b4932efa9a345cc42e))
* Arch OS starts only from its own ISO, and get.sh writes it from any Linux ([#219](https://github.com/murkl/arch-os/issues/219)) ([470602a](https://github.com/murkl/arch-os/commit/470602ab26a64c8d029e854793d78a16077daf66))
* AUR builds use every core, and connections find a smaller path MTU ([#210](https://github.com/murkl/arch-os/issues/210)) ([1a279c9](https://github.com/murkl/arch-os/commit/1a279c9e4cbf0c1ed8646d7e8b2eaf4446afd30d))
* Bazaar can take GNOME Software's place, and older machines run smoother ([#214](https://github.com/murkl/arch-os/issues/214)) ([d38f113](https://github.com/murkl/arch-os/commit/d38f113fbd706e26779af62cf13df8d0e7193769))
* behind disk encryption the password prompt comes first, without the splash flashing before it ([adfaa66](https://github.com/murkl/arch-os/commit/adfaa6603d068636fda019b4932efa9a345cc42e))
* Create boot medium asks only for the device, the image lands in ~/Downloads ([#199](https://github.com/murkl/arch-os/issues/199)) ([4bb87af](https://github.com/murkl/arch-os/commit/4bb87af1ee6df134affcc3e2c17508e496ec005f))
* every account starts with the same GNOME defaults, set through dconf ([adfaa66](https://github.com/murkl/arch-os/commit/adfaa6603d068636fda019b4932efa9a345cc42e))
* GNOME Boxes works once installed, in place of the virtual machine setting ([#197](https://github.com/murkl/arch-os/issues/197)) ([c61b254](https://github.com/murkl/arch-os/commit/c61b254d1c48519def97b4e200acc34f2246688d))
* **shell:** stop the word keys at dashes, dots and slashes ([#195](https://github.com/murkl/arch-os/issues/195)) ([f55b91a](https://github.com/murkl/arch-os/commit/f55b91a89e3b835e03d5623e81d0fbe20dec3d4b))
* the firmware lists the Recovery, leaving it shows no login, and its launcher takes the theme's icon ([#198](https://github.com/murkl/arch-os/issues/198)) ([3588a52](https://github.com/murkl/arch-os/commit/3588a52133b61b81222dc17a2d703243b8e734ff))
* the Recovery on the ISO writes the Recovery partition again where an update was cut short ([adfaa66](https://github.com/murkl/arch-os/commit/adfaa6603d068636fda019b4932efa9a345cc42e))
* the Recovery updates to the newest release of its series, even once a newer major version is out ([adfaa66](https://github.com/murkl/arch-os/commit/adfaa6603d068636fda019b4932efa9a345cc42e))
* the root partition carries the type systemd's tools find it by ([adfaa66](https://github.com/murkl/arch-os/commit/adfaa6603d068636fda019b4932efa9a345cc42e))
* the shared folders of GNOME Boxes reach a desktop guest ([#202](https://github.com/murkl/arch-os/issues/202)) ([72db5e4](https://github.com/murkl/arch-os/commit/72db5e45f8c9b4b9f13f9b621759f0537f239bea))
* the System Manager 2.0, written in Rust, replaces the Arch OS Manager ([05444f7](https://github.com/murkl/arch-os/commit/05444f74ef3d36aa62322fdcff4796773758d304))
* what goes wrong is said in plain words, and only a broken script shows where ([#201](https://github.com/murkl/arch-os/issues/201)) ([5df367d](https://github.com/murkl/arch-os/commit/5df367d5a6f2e33b42960fc3e9ce9cfab072a609))


### Bug Fixes

* a download's progress bar no longer fills the log ([#211](https://github.com/murkl/arch-os/issues/211)) ([f4bb355](https://github.com/murkl/arch-os/commit/f4bb35534e959fc9b7daffe24cf3d1b6785fe9ad))
* a power cut right after an installation or a repair leaves a system that starts ([#209](https://github.com/murkl/arch-os/issues/209)) ([5cda627](https://github.com/murkl/arch-os/commit/5cda627d592702459a3955b75b74a210ed0448a9))
* a Recovery from a pre-release counts as older than its release ([adfaa66](https://github.com/murkl/arch-os/commit/adfaa6603d068636fda019b4932efa9a345cc42e))
* a shared configuration leaves the kernel parameters out ([adfaa66](https://github.com/murkl/arch-os/commit/adfaa6603d068636fda019b4932efa9a345cc42e))
* the Recovery keeps the subvolumes made inside the system and repairs the disk it was started from ([#208](https://github.com/murkl/arch-os/issues/208)) ([4a95c12](https://github.com/murkl/arch-os/commit/4a95c12ded876014f832332cb8e4ee2f776648c8))
* the Recovery partition is read back from the disk after it is written ([adfaa66](https://github.com/murkl/arch-os/commit/adfaa6603d068636fda019b4932efa9a345cc42e))
* the weekly cache trim keeps the kernel a rollback needs ([#212](https://github.com/murkl/arch-os/issues/212)) ([c949e2a](https://github.com/murkl/arch-os/commit/c949e2ac3ef65e5509c45e44b5fe7e297dfe99fb))

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
