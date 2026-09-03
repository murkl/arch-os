# Arch OS Installer

Everything this installer knows about Arch Linux. It is data, one YAML file and
the folders beside it, and it does not run on its own: the
[runtime](../../runtime) draws the interface, asks the questions and runs the tasks
in order. Repairing a system that is already on a disk is a module of its own:
[`recovery/`](../recovery).

```sh
make check                                              # load the module and lint every script
DEBUG=true make -C ../../runtime run MODULE=installer      # run it, without touching this machine
```

## What is where

```
installer.yaml           what this installer is, what it asks, what order it works in
tasks/<id>/task.yaml     where that unit belongs: its stage, its needs, its conditions
tasks/<id>/task.sh       what it does, and any file it ships with, beside it
hooks/<name>.sh          everything around the work itself
lib.sh                   the little every script of this module shares
data/                    the tables a language and a country are looked up in
locales/                 one <code>.po per language this installer speaks, and the template they are filled in from
```

Nothing points at any of this from `installer.yaml`: each part is found by its
own name. A release is the runtime binary with `runtime.yaml` beside it and a
`modules/` folder holding this one and the recovery: one binary, two modules,
and the question of which of them to open is a page of the interface's own.

## What a run is called

`installer.yaml` says `run: Installation`, which the interface reads out wherever
it says what is happening: the row that starts it, the last warning, the clock
while it runs. `description:` beside it is the sentence under this module's row
on the page that asks which to open.

Left out, the runtime falls back to the only thing an unnamed run can be and
calls it an installation, right here, wrong in [`recovery/`](../recovery),
which names its own run the same way.

## Tasks

Every folder under `tasks/` is a step, and nothing lists them: the folder is the
list. `installer.yaml` declares the stages top to bottom; every task names one,
and `needs:` orders the ones that share a stage.

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
| `disk` | partitioned, encrypted, formatted, mounted, the only stage that destroys anything |
| `base` | the system on the disk, configured, with an account on it |
| `boot` | the boot loader and the kernel command line |
| `system` | everything that is switched on rather than installed |
| `desktop` | GNOME, its driver, and what belongs to it |
| `finalize` | the last things done to the new system |
| `finish` | what is offered once it is installed |

Three orderings are load bearing, and each is written down as a `needs:` or as a
stage: the disk exists before anything is installed onto it, 32-bit support is
switched on before any package that needs it is pulled in, and the boot chain is
signed last: signing only holds if nothing rebuilds the kernel image afterwards.

`make check` prints the order the whole module adds up to.

### Writing one

A unit is a folder with two files in it. The script is **sourced** by the
runtime into a shell that already carries an `ERR` trap and `lib.sh`, so it
needs no shebang, no `set -e`, no imports and no error handling: if a command
fails, the task fails, and the interface shows the file, the line, the command
and the exit code.

```sh
# tasks/thing/task.sh
simulating && return 0

chroot_pacman_install git base-devel
arch-chroot "$MNT" systemctl enable something.service
cp "$(where)/thing.conf" "${MNT}/etc/thing.conf"
```

The first line is what makes `DEBUG=true` a simulation rather than an
installation. It belongs at the top of every task, before the first command that
changes anything. `where` is the unit's own folder.

`lib.sh` is deliberately small. What is in it is there because several tasks
need the same answer and must not disagree about it: the kernel command line,
the mount point, how a package is installed and retried. Everything else belongs
in the task that does it, even when that means a longer script: a task nobody
can read without opening a second file is a task nobody will change.

Three rules:

- **Ask nothing.** Every question is declared in `installer.yaml` and asked
  inside the interface, unless the task declares `tty: true`, which hands it
  the whole terminal on purpose.
- **Print nothing for a person to read.** stdout and stderr go to the log. What
  is on screen is the name of the task.
- **Do one thing.** A task is a line in a list somebody is watching.

Anything a task cannot do because there is no user session yet (GNOME settings
live in the session's own database) goes through `on_first_login`, which
collects the lines into a script that runs once at the first login and then
removes itself.

### Keys that change what a unit is

```yaml
asks: ARCH_OS_CONFIG_SOURCE                       # a value, asked mid-run, before the offer
confirm: Restart into {{ARCH_OS_HOSTNAME}} now?   # a yes or no in the frame; no skips it
default: no                                       # which of the two that offer opens on
report: |                                         # the run stops on a page of this one's own
  Arch OS is installed
shows: ARCH_OS_CONFIG_URL                         # an answer on that page, as a code to scan
quits: true                                       # the program does not come back from this
tty: true                                         # hand it the terminal, and take it back after
```

That is how everything after the installation (a copy of the answers, sharing
them online, a shell in the new system, a restart, an unmount) is a task of the
`finish` stage rather than a page of its own.

`asks:` is for a value there is nothing to choose from until the run reaches
that task, the recovery's snapshot list is the case it exists for. `report:`
marks the moment the work is done and everything after it is an offer: a list
of task names cannot say that on its own.

## Sharing a configuration

The finished `installer.conf` can go to [paste.rs](https://paste.rs), no
account, no key, and its address comes back as a code to scan. Both ends are in
the `share-config` task:

| | |
|---|---|
| `task.sh` | uploads and records the address as `ARCH_OS_CONFIG_URL`; never fails an installation that has already worked |
| `import.sh` | fetches one and appends it to the answer file, from either the whole link or the code at the end of it |

The upload is the `share-config` task: a `confirm:` opening on **no**, asked
immediately after the page that says the installation is finished. There is no
setting for it anywhere: a switch among the answers would collect the consent
an hour before there was anything to consent to. Say no and nothing is sent.

What goes up is the answer file with its own `ARCH_OS_CONFIG_*` lines stripped.
The password is not in it (the runtime never writes a secret down), but the
host name, the user name, the disk and the language are. **Anybody holding the
address can read it.**

The other end is the third starting point, `paste.rs - Online`: it asks for the
code, `import.sh` turns it into answers, and from the next page on nothing about
them is any different.

## Hooks

Bash the runtime calls by name. A hook that is there is used; one that is not
turns that part of the interface off. Any other file name under `hooks/` is
refused when the module loads.

| | |
|---|---|
| `preflight.sh` | root, the live image, UEFI, Secure Boot off and a network |
| `online.sh` | whether there is internet |
| `wlan-device.sh` | the wireless device to use |
| `wlan-networks.sh` | scan, wait, and print one SSID per line |
| `wlan-connect.sh` | join one, with `WLAN_DEVICE`, `WLAN_SSID` and `WLAN_PASSPHRASE` in the environment |
| `restart.sh` | close the target and reboot |
| `shutdown.sh` | close the target and switch off |

The last two are what make leaving the installer a question rather than an exit:
the ISO boots to run this, so quitting by accident would leave a machine that
answers nothing. Both call `unmount_target` first, so a machine on its way down
does not take a half-written file system with it, and both do nothing at all
under `DEBUG=true`.

The third way out is `console:` in `installer.yaml`, and it runs nothing: the
installer closes and the machine keeps running. See [iso/](../iso).

## `auto` and `none`

The two words the lists in `installer.yaml` share. `auto` says this machine
works the answer out; `none` is the empty answer said out loud. `lib.sh`
resolves both before any task runs, so nothing downstream tests for either word.

| on `auto` | comes to |
|---|---|
| `ARCH_OS_VCONSOLE_KEYMAP` | the keyboard the language is typed on, then the live image's own, then `us` |
| `ARCH_OS_DESKTOP_KEYBOARD_LAYOUT` | the same keyboard in xkb's names |
| `ARCH_OS_VCONSOLE_FONT` | the font that can draw the language's script |
| `ARCH_OS_REFLECTOR_COUNTRY` | the country the locale's territory names |
| `ARCH_OS_MICROCODE` | whatever `/proc/cpuinfo` says the processor is |
| `ARCH_OS_DESKTOP_AUTOLOGIN_ENABLED` | disk encryption, a password at boot makes a second one at login pointless |

The boot and root partitions are worked out the same way, from the disk.

## Language, and what follows from it

One answer, `ARCH_OS_LOCALE_LANG`, settles the system language, and with it
the keyboard, the console font, the mirror country and the time zone. None of
that follows from the shape of a locale: `de_CH` is not `de`, `sv` is not `se`,
and a mirror list has never heard of `DE`. So it is looked up in two tables, and
each answer stays a question anyone can override.

| table | keyed by | says |
|---|---|---|
| `data/languages` | a language, or a locale where it differs | console keymap, xkb layout, console font |
| `data/countries` | the territory a locale ends in | the country as the mirror list spells it, and its time zone |

`data/x11-layouts` and `data/x11-variants` are only a fallback: the Arch live
image ships no xkeyboard-config, so on the one machine the desktop keyboard is
actually chosen on there is nothing to ask.

The **console keyboard** is `first: true`, so it is asked before the network
screen, before the preflight, before every other question, and it takes effect
on the live system the moment it is given, through
`apply: load_console_keyboard`. A passphrase typed on the wrong layout is not
the passphrase.

## Adding something

**An option**: add it to `variables:` in `installer.yaml`. It is on the
settings page the moment it exists, and asked for if it is `required` and
nothing answers it. Guard the tasks that care with `conditions:`.

**A step**: make a folder under `tasks/`, write the two files, and `make
check`. Nothing else has to be told about it.

**A starting point**: an option under `presets:`. One that fetches its answers
instead of writing them out names the question it asks with `asks:` and the
shell that makes something of the answer with `apply:`.

**Something in the recovery**: none of it is here. That is
[`recovery/`](../recovery), a module of its own.

**A language**:

```sh
cp locales/installer.pot locales/fr.po   # every word this module says, none of them translated
make check                               # reports coverage per language
```

Fill in the `msgstr` lines and nothing else. `make locales` regenerates
`installer.pot` from the module and brings every catalog up to it, which is what
has to run after a question is added or reworded. The runtime's own words are
translated separately, in its own `locales/`. See
[TRANSLATING.md](../TRANSLATING.md).

## Requirements

Root, the Arch Linux live image, booted in UEFI mode with Secure Boot off, and a
network. `hooks/preflight.sh` checks all four, before the first question.

## Where the answers go

`installer.conf`, beside wherever the installer was started, written the moment
any value is given and copied into the new system at the end. The password is
never in it: it is asked for immediately before the installation starts and
forgotten when it is over.

It is also the one way a script answers anything: a task appends a
`NAME='value'` line to it (see the `share-config` task) and the runtime reads
the file back.
