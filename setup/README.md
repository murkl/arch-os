# Arch OS Installer

Everything this installer knows about Arch Linux. It is data — one YAML file and
the folders beside it — and it does not run on its own: the [runtime](../runtime)
draws the interface, asks the questions and runs the tasks in order.

```sh
make check                            # load the tree and lint every script
DEBUG=true make -C ../runtime run     # run it, without touching this machine
```

A release is this folder with the binary in it: the runtime looks for its
`installer.yaml` beside itself and nowhere else. Nothing puts one here while
developing, though — both commands above reach the tree with `-dir`, and a
build artefact in the middle of the source is the thing that gets committed by
accident.

## What is where

```
installer.yaml           what this image can do, what it asks, what order it works in
tasks/<id>/task.yaml     where that unit belongs: its stage, its needs, its conditions
tasks/<id>/task.sh       what it does — and any file it ships with, beside it
hooks/<name>.sh          everything around the work itself
lib.sh                   what every script of an installation shares, sourced before each one
util.sh                  general shell with no idea what Arch OS is, sourced by lib.sh
recovery.sh              what every script of a recovery shares, sourced by lib.sh
data/                    the tables a language and a country are looked up in
locales/                 one <code>.yaml per language this installer speaks
```

Nothing points at any of this from `installer.yaml`: each part is found by its
own name. `tasks/` is only Arch Linux — the steps that build a system on a disk,
and the steps that put a broken one back. Everything else the program does is a
hook.

## The two things this image does

`installer.yaml` declares two **modes**, and the program asks which one this run
is right after the console keyboard — before the network screen, before the
check, before the starting points, because every one of those depends on the
answer.

| | |
|---|---|
| `install` | put Arch Linux on this machine — stages `prepare` … `finish` |
| `recovery` | repair one that is already on a disk — stages `open`, `repair`, `close` |

A task belongs to whichever mode owns the stage it names, so nothing says it
twice. A question says so with `mode:`, and one that says nothing belongs to
both — which is exactly the console keyboard, asked before there is a mode for
it to belong to. Both halves reach every script as `INSTALLER_MODE`, which is
what `hooks/preflight.sh` and `hooks/online.sh` branch on: a recovery downloads
nothing and has no opinion about this machine's firmware, so neither a network
nor UEFI is a wall in front of it.

## Tasks

Every folder under `tasks/` is a step, and nothing lists them: the folder is the
list. Each mode in `installer.yaml` declares its stages, top to bottom; every
task names one, and `needs:` orders the ones that share a stage.

```yaml
# tasks/aur-helper/task.yaml
name: Install the AUR helper
stage: system
needs: [enable-multilib]
conditions: ARCH_OS_AUR_HELPER != none
```

| stage | what it is |
|---|---|
| `prepare` | the live system, made ready to install from |
| `disk` | partitioned, encrypted, formatted, mounted — the only stage that destroys anything |
| `base` | the system on the disk, configured, with an account on it |
| `boot` | the boot loader and the kernel command line |
| `system` | everything that is switched on rather than installed |
| `desktop` | GNOME, its driver, and what belongs to it |
| `finalize` | the last things done to the new system |
| `finish` | what is offered once it is installed |
| `open` | *(recovery)* the installed system unlocked and mounted at `/mnt` |
| `repair` | *(recovery)* rolled back, made bootable again, worked in by hand |
| `close` | *(recovery)* unmounted, and the disk locked again |

Three orderings are load bearing, and each is written down as a `needs:` or as a
stage: the disk exists before anything is installed onto it, 32-bit support is
switched on before any package that needs it is pulled in, and the boot chain is
signed last — signing only holds if nothing rebuilds the kernel image
afterwards.

`make check` prints the order the whole tree adds up to. It is the one thing
about an installer nobody writes down, so it is worth reading after every change.

### Writing one

A unit is a folder with two files in it. The script is **sourced** by the runtime
into a shell that already carries an `ERR` trap and `lib.sh`, so it needs no
shebang, no `set -e`, no imports and no error handling: if a command fails, the
task fails, and the interface shows the file, the line, the command and the exit
code.

```sh
# tasks/thing/task.sh
simulating && return 0

chroot_pacman_install git base-devel
arch-chroot "$MNT" systemctl enable something.service
cp "$(where)/thing.conf" "${MNT}/etc/thing.conf"
```

The first line is what makes `DEBUG=true` a simulation rather than an
installation — see *Trying it out*. It belongs at the top of every task, before
the first command that changes anything. `where` is the unit's own folder, which
is where a unit keeps the files it ships with.

Three rules:

- **Ask nothing.** Every question is declared in `installer.yaml` and asked
  inside the interface. A script reading from the terminal is the one thing that
  breaks the frame — unless it declares `tty: true`, which hands it the whole
  terminal on purpose.
- **Print nothing for a person to read.** Everything on stdout and stderr goes to
  the log. What is on screen is the name of the task.
- **Do one thing.** A task is a line in a list somebody is watching.

Anything a task cannot do because there is no user session yet — GNOME settings
live in the session's own database — goes through `on_first_login`, which
collects the lines into a script that runs once at the first login and then
removes itself.

### Tasks that ask, one that reports, and one that takes the terminal

Seven keys change what a unit is rather than what it does:

```yaml
asks: ARCH_OS_RECOVERY_SNAPSHOT                   # a value, asked mid-run, before the offer
confirm: Restart into {{ARCH_OS_HOSTNAME}} now?   # a yes or no in the frame; no skips it
default: no                                       # which of the two that offer opens on
report: |                                         # the run stops on a page of this one's own
  Arch Linux is installed
shows: ARCH_OS_CONFIG_URL                         # an answer on that page, as a code to scan
quits: true                                       # the program does not come back from this
tty: true                                         # hand it the terminal, and take it back after
```

That is how everything after the installation — a copy of the answers, a shell
in the new system, a restart, an unmount — is a task of the `finish` stage like
any other, rather than a page of its own.

`asks:` is what the rollback needs and nothing else does: the snapshots on a
disk cannot be listed before that disk has been unlocked and mounted, which is
the task before it. So the question is asked in the middle of the run, and the
`confirm:` under it names the snapshot that was just chosen.

`report:` is on `copy-config`, the last thing done to the installation itself.
Everything past it is an offer, and a list of task names cannot say that on its
own — so the run stops there, once, under a large green tick, and says the
machine is installed before it asks whether to open a shell in it. The first
paragraph is the headline; the rest is the paragraph under it.

## Sharing a configuration

An installation is two dozen answers, and the second machine set up the same way
is otherwise those two dozen answers given again by hand. So the finished
`installer.conf` goes to [paste.rs](https://paste.rs) — no account, no key,
nothing to agree to — and the address of it stands on the page above as a code
to scan.

Both ends of that are in `lib.sh`:

| | |
|---|---|
| `share_config` | uploads and records the address as `ARCH_OS_CONFIG_URL`; never fails an installation that has already worked |
| `import_config` | fetches one and appends it to the answer file, which the runtime reads back |
| `config_url` | the address, from either the whole link or the code at the end of it |

The upload is `ARCH_OS_CONFIG_SHARE_ENABLED`, on by default and a row in the
settings like any other. What goes up is the answer file with its own
`ARCH_OS_CONFIG_*` lines stripped, and the password is not in it — the runtime
never writes a secret down at all. Everything else is: the host name, the user
name, the disk, the language. **Anybody holding the address can read it.**

The other end is the third row of the starting points, `paste.rs - Online`. It
asks for the code, `import_config` turns it into answers, and from the next page
on nothing about them is any different — which usually means the main menu
straight away, since a configuration that installed one machine answers
everything a second one asks.

## Hooks

Bash the runtime calls by name for everything that is not the installation
itself. A hook that is there is used; one that is not turns that part of the
interface off. Any other file name under `hooks/` is refused when the tree
loads, so a typo is a message at startup rather than a hook that never runs.

| | |
|---|---|
| `preflight.sh` | root and the live image, and — installing — UEFI, Secure Boot off and a network, all before anything is asked bar the keyboard |
| `online.sh` | whether there is internet; always yes in a recovery, which downloads nothing |
| `wlan-device.sh` | the wireless device to use |
| `wlan-networks.sh` | scan, wait, and print one SSID per line |
| `wlan-connect.sh` | join one, with `WLAN_DEVICE`, `WLAN_SSID` and `WLAN_PASSPHRASE` in the environment |
| `restart.sh` | close the target and reboot |
| `shutdown.sh` | close the target and switch off |

The last two are what make leaving the installer a question rather than an exit:
the ISO boots to run this, so quitting by accident would leave a machine that
answers nothing. ctrl+c, the row that says quit, backing off the first page and
the end of an installation all land on the same three answers. Both go through
`leave_machine` in `lib.sh`, which unmounts whatever the installation had open
and does nothing at all under `DEBUG=true`.

The third answer is `console:` in `installer.yaml`, and it runs nothing: the
installer closes and the machine keeps running. On this image the systemd unit
that started it hands tty1 to a root shell when it stops, and `installer` there
starts it again from the answers already given. The sentence in that key is what
the interface prints on the way out; `/etc/motd` says it again on the way in.
See [iso/](../iso).

## `auto` and `none`

The two words the lists in `installer.yaml` share. `auto` says this machine works
the answer out; `none` is the empty answer said out loud. `lib.sh` resolves both
before any task runs, so nothing downstream ever tests for either word — and each
stays a variable anyone can answer outright.

| on `auto` | comes to |
|---|---|
| `ARCH_OS_VCONSOLE_KEYMAP` | the keyboard the language is typed on, then the live image's own, then `us` |
| `ARCH_OS_DESKTOP_KEYBOARD_LAYOUT` | the same keyboard in xkb's names |
| `ARCH_OS_VCONSOLE_FONT` | the font that can draw the language's script |
| `ARCH_OS_REFLECTOR_COUNTRY` | the country the locale's territory names |
| `ARCH_OS_MICROCODE` | whatever `/proc/cpuinfo` says the processor is |
| `ARCH_OS_DESKTOP_AUTOLOGIN_ENABLED` | disk encryption — a password at boot makes a second one at login pointless |

The boot and root partitions are worked out the same way, from the disk.

## Language, and what follows from it

One answer — `ARCH_OS_LOCALE_LANG` — settles the system language, and with it
the keyboard, the console font, the mirror country and the time zone. None of
that can be guessed from the shape of a locale: `de_CH` is not `de`, `sv` is not
`se`, and a mirror list has never heard of `DE`. So it is looked up in two
tables, and each answer stays a question anyone can override.

| table | keyed by | says |
|---|---|---|
| `data/languages` | a language, or a locale where it differs | console keymap, xkb layout, console font |
| `data/countries` | the territory a locale ends in | the country as the mirror list spells it, and its time zone |

The same tables fill the lists those questions offer, so what a page shows beside
`auto` and what a task gets can never disagree. `data/x11-layouts` and
`data/x11-variants` are only a fallback: the Arch live image ships no
xkeyboard-config, so on the one machine the desktop keyboard is actually chosen
on there is nothing to ask.

### The first two pages

**The language of the interface** comes first, before anything else. It is the
runtime's own page, and this tree declares nothing to make it appear beyond the
catalogs under `locales/`. It settles the words on screen and nothing else:
installing a German system from an English installer is an ordinary thing to do,
and it is a row in the settings afterwards.

**The console keyboard** comes second: `ARCH_OS_VCONSOLE_KEYMAP` is `first: true`,
so it is asked before the network screen, before the preflight, before every
other question. It is the one answer that also has to take effect *here*, on the
live system, the moment it is given — hence `apply: load_console_keyboard` on it.
Until `loadkeys` has run, everything typed after it is typed on a layout nobody
chose, and a password typed on the wrong one is not the password. It has no
`default:` for exactly that reason: a default would answer it, and then it would
never be asked.

## Adding something

**A new option** — add it to `variables:` in `installer.yaml`. It is on the
settings page the moment it exists, and asked for if it is `required` and nothing
answers it. Guard the tasks that care with `conditions:`.

**A new step** — make a folder under `tasks/`, write the two files, and `make
check`. Nothing else has to be told about it.

**A new starting point** — an option under `presets:`. A page is offered once, on
a machine that has never answered anything, and what it fills in is an ordinary
answer from the next page on. One that fetches its answers instead of writing
them out names the question it asks with `asks:` and the shell that makes
something of the answer with `apply:`.

**Something in the recovery** — the logic goes in `recovery.sh` and the step that
calls it under `tasks/recovery-*/`, in a stage of the `recovery` mode. Its
questions go in `installer.yaml` with `mode: recovery` on them.

**A new language** —

```sh
make strings > locales/fr.yaml   # every word this tree says, empty
make check                       # reports coverage per language
```

The runtime's own words — key hints, buttons, the labels on a failure report —
are translated separately, in the runtime's own `locales/`.

## Requirements

To install: root, the Arch Linux live image, booted in UEFI mode with Secure Boot
off, and a network. `hooks/preflight.sh` checks all four before anything is asked
bar the keyboard.

To recover: root and the live image. Nothing else — a machine that needs
repairing is one whose network may be part of what broke, and everything the
recovery uses is already on its own disk.

## Trying it out

```sh
DEBUG=true make -C ../runtime run
```

Every wall steps aside and every task reports success without doing anything, so
the questions, the wording and the order of the tasks can be tried out on an
ordinary running system, as an ordinary user. It installs nothing. The guard is
`simulating && return 0` at the top of each task — see `lib.sh`.

## Where the answers go

`installer.conf` beside wherever the installer was started, written the moment
any value is given, and copied into the new system at the end. The password is
never in it: it is asked for immediately before the installation starts and
forgotten when it is over.

It is also the one way a script answers anything — `answer NAME value` in
`util.sh` appends a line, and the runtime reads the file back. That is how the
address a configuration was shared at becomes an answer, and how a configuration
fetched from one becomes two dozen of them.

## Credit

The Arch Linux logic here is a port of [murkl/arch-os](https://github.com/murkl/arch-os),
whose `installer.sh` this tree was carved out of. `recovery.sh` is the same for
[murkl/arch-os-recovery](https://github.com/murkl/arch-os-recovery), whose
questions are now pages of the interface rather than gum prompts.
