# Changelog

What each release changed, newest first. Written by the run that publishes it, out of what landed on `main` since the release before, never by hand.

## [2.1.0](https://github.com/murkl/arch-os/compare/v2.0.0...2.1.0) (2026-10-24)


### Features

* a Desktop's start counts as one that worked only once its login screen or session is up ([#205](https://github.com/murkl/arch-os/issues/205)) ([ce2ba5f](https://github.com/murkl/arch-os/commit/ce2ba5f95fbbfa1ef0d1cf5223445f711018e246))
* a kernel panic restarts the machine, so the loader counts the start as failed ([#204](https://github.com/murkl/arch-os/issues/204)) ([248f726](https://github.com/murkl/arch-os/commit/248f7269f124a07ddeaff575b7984343bd826388))
* a system kept offline stays clean, its timers skip rather than fail ([#200](https://github.com/murkl/arch-os/issues/200)) ([5731f07](https://github.com/murkl/arch-os/commit/5731f0773911d58ab58c2850eb4487e55438ab6d))
* a system that does not start falls back to its fallback image, then to the Recovery ([#203](https://github.com/murkl/arch-os/issues/203)) ([384e31c](https://github.com/murkl/arch-os/commit/384e31cd9ef036de256f51fbd59ee516808bfa8b))
* an installation keeps the kernel's crash records from the firmware ([b74985b](https://github.com/murkl/arch-os/commit/b74985bc6307a8607998f134f6e94d686508d9ce))
* an updated Recovery is signed with the system's keys whenever the system signs its boot chain ([adfaa66](https://github.com/murkl/arch-os/commit/adfaa6603d068636fda019b4932efa9a345cc42e))
* Arch OS starts only from its own ISO ([470602a](https://github.com/murkl/arch-os/commit/470602ab26a64c8d029e854793d78a16077daf66))
* AUR builds use every core, and connections find a smaller path MTU ([#210](https://github.com/murkl/arch-os/issues/210)) ([1a279c9](https://github.com/murkl/arch-os/commit/1a279c9e4cbf0c1ed8646d7e8b2eaf4446afd30d))
* Bazaar can take GNOME Software's place, and older machines run smoother ([#214](https://github.com/murkl/arch-os/issues/214)) ([d38f113](https://github.com/murkl/arch-os/commit/d38f113fbd706e26779af62cf13df8d0e7193769))
* behind disk encryption the password prompt comes first, without the splash flashing before it ([adfaa66](https://github.com/murkl/arch-os/commit/adfaa6603d068636fda019b4932efa9a345cc42e))
* every account starts with the same GNOME defaults, set through dconf ([adfaa66](https://github.com/murkl/arch-os/commit/adfaa6603d068636fda019b4932efa9a345cc42e))
* GNOME Boxes works once installed, in place of the virtual machine setting ([#197](https://github.com/murkl/arch-os/issues/197)) ([c61b254](https://github.com/murkl/arch-os/commit/c61b254d1c48519def97b4e200acc34f2246688d))
* **shell:** stop the word keys at dashes, dots and slashes ([#195](https://github.com/murkl/arch-os/issues/195)) ([f55b91a](https://github.com/murkl/arch-os/commit/f55b91a89e3b835e03d5623e81d0fbe20dec3d4b))
* the boot splash draws in Nord throughout and names every keyboard layout right ([#225](https://github.com/murkl/arch-os/issues/225)) ([16f6cec](https://github.com/murkl/arch-os/commit/16f6cec43469a82ac08ada9c960e0810da924f9c))
* the firmware lists the Recovery, leaving it shows no login, and its launcher takes the theme's icon ([#198](https://github.com/murkl/arch-os/issues/198)) ([3588a52](https://github.com/murkl/arch-os/commit/3588a52133b61b81222dc17a2d703243b8e734ff))
* the Installer runs unattended, failures name the right line, a shell no longer stops it, the Recovery takes the kernel from the snapshot, and a SATA disk behind USB gets the writeback limit ([#233](https://github.com/murkl/arch-os/issues/233)) ([7e75c97](https://github.com/murkl/arch-os/commit/7e75c9783d4b0c5d3eaa672953b7f70967c942c7))
* the ISO carries the Recovery again, and laptops get sound, GNOME its calendar and a text editor ([#231](https://github.com/murkl/arch-os/issues/231)) ([af01001](https://github.com/murkl/arch-os/commit/af01001e03de8806ac9a7142e9497493fb61d89d))
* the Recovery on the ISO writes the Recovery partition again where an update was cut short ([adfaa66](https://github.com/murkl/arch-os/commit/adfaa6603d068636fda019b4932efa9a345cc42e))
* the Recovery updates to the newest release of its series, even once a newer major version is out ([adfaa66](https://github.com/murkl/arch-os/commit/adfaa6603d068636fda019b4932efa9a345cc42e))
* the root partition carries the type systemd's tools find it by ([adfaa66](https://github.com/murkl/arch-os/commit/adfaa6603d068636fda019b4932efa9a345cc42e))
* the Rust runtime replaces Oak, with the Installer on a dashboard ([#223](https://github.com/murkl/arch-os/issues/223)) ([d33ab74](https://github.com/murkl/arch-os/commit/d33ab745dfcbf5772f48338763b479ff9a4e9ead))
* the shared folders of GNOME Boxes reach a desktop guest ([#202](https://github.com/murkl/arch-os/issues/202)) ([72db5e4](https://github.com/murkl/arch-os/commit/72db5e45f8c9b4b9f13f9b621759f0537f239bea))
* the System Manager 2.0, written in Rust, replaces the Arch OS Manager ([05444f7](https://github.com/murkl/arch-os/commit/05444f74ef3d36aa62322fdcff4796773758d304))
* what goes wrong is said in plain words, and only a broken script shows where ([#201](https://github.com/murkl/arch-os/issues/201)) ([5df367d](https://github.com/murkl/arch-os/commit/5df367d5a6f2e33b42960fc3e9ce9cfab072a609))


### Bug Fixes

* a download's progress bar no longer fills the log ([#211](https://github.com/murkl/arch-os/issues/211)) ([f4bb355](https://github.com/murkl/arch-os/commit/f4bb35534e959fc9b7daffe24cf3d1b6785fe9ad))
* a power cut right after an installation or a repair leaves a system that starts ([#209](https://github.com/murkl/arch-os/issues/209)) ([5cda627](https://github.com/murkl/arch-os/commit/5cda627d592702459a3955b75b74a210ed0448a9))
* a Recovery from a pre-release counts as older than its release ([adfaa66](https://github.com/murkl/arch-os/commit/adfaa6603d068636fda019b4932efa9a345cc42e))
* a shared configuration leaves the kernel parameters out ([adfaa66](https://github.com/murkl/arch-os/commit/adfaa6603d068636fda019b4932efa9a345cc42e))
* irqbalance runs on every real machine, whether or not Housekeeping is on ([0eee042](https://github.com/murkl/arch-os/commit/0eee042065d2c92574f891601b15af6b5a4618c6))
* PipeWire gets its realtime priority without the desktop extras ([#232](https://github.com/murkl/arch-os/issues/232)) ([c6fe860](https://github.com/murkl/arch-os/commit/c6fe8601cbdb9eea3a36d9cc7091cf14f9557d92))
* recovery, hardening and texts ([#234](https://github.com/murkl/arch-os/issues/234)) ([e52d1a6](https://github.com/murkl/arch-os/commit/e52d1a6d0bcec61d9d28718d9e880a14888ab229))
* secure defaults, test trace ([#235](https://github.com/murkl/arch-os/issues/235)) ([6b089e4](https://github.com/murkl/arch-os/commit/6b089e45a620361ed433cc973af13ee4647c88a9))
* the console font list offers only the fonts an installation has ([b74985b](https://github.com/murkl/arch-os/commit/b74985bc6307a8607998f134f6e94d686508d9ce))
* the Recovery keeps the subvolumes made inside the system and repairs the disk it was started from ([#208](https://github.com/murkl/arch-os/issues/208)) ([4a95c12](https://github.com/murkl/arch-os/commit/4a95c12ded876014f832332cb8e4ee2f776648c8))
* the Recovery partition is read back from the disk after it is written ([adfaa66](https://github.com/murkl/arch-os/commit/adfaa6603d068636fda019b4932efa9a345cc42e))
* the weekly cache trim keeps the kernel a rollback needs ([#212](https://github.com/murkl/arch-os/issues/212)) ([c949e2a](https://github.com/murkl/arch-os/commit/c949e2ac3ef65e5509c45e44b5fe7e297dfe99fb))


### Performance Improvements

* the ISO carries only what Arch OS uses and both images boot faster ([b74985b](https://github.com/murkl/arch-os/commit/b74985bc6307a8607998f134f6e94d686508d9ce))

## [2.0.0](https://github.com/murkl/arch-os/compare/1.9.7...v2.0.0) (2026-10-10)


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
