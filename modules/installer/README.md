# Arch OS Installer

Everything this installer knows about Arch Linux. It's data — one YAML file
and the folders beside it — and it doesn't run on its own: the
[runtime](../../runtime) draws the interface, asks the questions, and runs
the tasks in order. Repairing a system already on disk is a separate module:
[`recovery/`](../recovery).

```sh
make check                                              # load the module and lint every script
make -C ../../runtime run MODULE=installer ARGS=--debug # run it without touching this machine
```

## What is where

```
installer.yaml           what this installer is, what it asks, what order it runs in
tasks/<id>/task.yaml     where that step belongs: its stage, its dependencies, its conditions
tasks/<id>/task.sh       what it does, plus any file it ships with, beside it
hooks/<name>.sh          everything around the work itself
lib.sh                   the small shared library every script in this module uses
data/                    the tables a language and a country are looked up in
locales/                 one <code>.po per language this installer speaks, and the template they're filled in from
```

Nothing in `installer.yaml` points at any of this — each part is found by
its own name. A release is the runtime binary with `runtime.yaml` beside it
and a `modules/` folder holding this module and recovery: one binary, two
modules, and which one to open is just a page in the interface.

## What a run is called

`installer.yaml` sets `run: Installation`, which the interface reads out
wherever it reports what's happening — the row that starts it, the final
warning, the clock while it runs. `description:` next to it is the sentence
shown under this module's row on the page that asks which module to open.

Leave `run` out and the runtime defaults to "Installation", which is correct
here but wrong in [`recovery/`](../recovery), which names its own run
differently.

## Tasks

Every folder under `tasks/` is a step, and nothing lists them elsewhere: the
folder itself is the list. `installer.yaml` declares the stages top to
bottom; every task belongs to one, and `needs:` orders the tasks that share
a stage.

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
| `base` | the system on disk, configured, with an account created |
| `boot` | the boot loader and the kernel command line |
| `system` | everything that gets switched on rather than installed |
| `desktop` | GNOME, its driver, and whatever belongs to it |
| `finalize` | the last steps on the new system |
| `finish` | what's offered once installation is complete |

Three orderings matter and are each captured as a `needs:` or a stage: the
disk has to exist before anything is installed onto it, 32-bit support has
to be enabled before any package that needs it is pulled in, and the boot
chain is signed last, since signing only holds if nothing rebuilds the
kernel image afterwards.

`make check` prints the order the whole module resolves to.

### Writing one

A task is a folder with two files in it. The runtime **sources** the script
into a shell that already has an `ERR` trap and `lib.sh` loaded, so it needs
no shebang, no `set -e`, no imports, and no error handling: if a command
fails, the task fails, and the interface shows the file, the line, the
command and the exit code.

```sh
# tasks/thing/task.sh
simulating && return 0

chroot_pacman_install git base-devel
arch-chroot "$MNT" systemctl enable something.service
cp "$(where)/thing.conf" "${MNT}/etc/thing.conf"
```

The first line is what turns `--debug` into a simulation instead of a real
installation. It belongs at the top of every task, before the first command
that changes anything. `where` returns the task's own folder.

`lib.sh` is kept deliberately small. What's in it is there because several
tasks need the same answer and must not disagree about it: the kernel
command line, the mount point, how a package is installed and retried.
Everything else belongs in the task that does it, even if that means a
longer script — a task nobody can read without opening a second file is a
task nobody will maintain.

Three rules:

- **Ask nothing.** Every question is declared in `installer.yaml` and asked
  by the interface, unless the task sets `tty: true`, which deliberately
  hands it the whole terminal.
- **Print nothing for a person to read.** stdout and stderr go to the log.
  What's on screen is just the task's name.
- **Do one thing.** A task is one line in a list somebody is watching.

Anything a task can't do because there's no user session yet (GNOME
settings live in the session's own database) goes through
`on_first_login`, which collects those lines into a script that runs once at
the first login and then removes itself.

### Keys that change what a task is

```yaml
asks: ARCH_OS_CONFIG_SOURCE                       # a value asked mid-run, before the confirmation
confirm: Restart into {{ARCH_OS_HOSTNAME}} now?   # a yes/no shown before the task runs; no skips it
default: no                                       # which of the two options that confirmation defaults to
report: |                                         # the run pauses on a page of its own
  Arch OS is installed
shows: ARCH_OS_CONFIG_URL                         # an answer shown on that page as a scannable code
quits: true                                       # the program doesn't return after this task
tty: true                                         # hand it the terminal, and take it back afterward
```

That's how everything after installation — copying the answers, sharing them
online, opening a shell in the new system, restarting, unmounting — ends up
as a task in the `finish` stage rather than a page of its own.

`asks:` is for a value there's nothing to choose from until the run reaches
that task — the recovery module's snapshot list is the example this exists
for. `report:` marks the moment the work is done and everything after it is
optional: a plain list of task names can't express that on its own.

## Sharing a configuration

The finished `installer.conf` can be uploaded to [paste.rs](https://paste.rs)
— no account, no key — and its address comes back as a scannable code. Both
ends live in the `share-config` task:

| | |
|---|---|
| `task.sh` | uploads the file and records the address as `ARCH_OS_CONFIG_URL`; never fails an installation that has already succeeded |
| `import.sh` | fetches one and appends it to the answer file, given either the full link or just the code at the end of it |

The upload is the `share-config` task: a `confirm:` that defaults to **no**,
asked immediately after the page confirming the installation is done.
There's no setting for it anywhere else — a switch among the earlier answers
would collect consent before there was anything to consent to. Say no and
nothing is sent.

What gets uploaded is the answer file with its `ARCH_OS_CONFIG_*` lines
stripped out. The password isn't in it (the runtime never writes a secret to
disk), but the hostname, username, disk and language are. **Anyone holding
the address can read it.**

The other end is the third preset, `Online (paste.rs)`: it asks for the
code, `import.sh` turns it into answers, and from the next page on those
answers behave exactly like any other.

## Hooks

Bash scripts the runtime calls by name. A hook that exists gets used; one
that doesn't turns off that part of the interface. Any other file name
under `hooks/` is rejected when the module loads.

| | |
|---|---|
| `preflight.sh` | checks root, the live image, UEFI, Secure Boot off, and a network connection |
| `online.sh` | whether there's internet |
| `wlan-device.sh` | which wireless device to use |
| `wlan-networks.sh` | scans and prints one SSID per line |
| `wlan-connect.sh` | joins one, with `WLAN_DEVICE`, `WLAN_SSID` and `WLAN_PASSPHRASE` in the environment |
| `restart.sh` | close the target system and reboot |
| `shutdown.sh` | close the target system and power off |

The last two are what turn leaving the installer into a choice rather than a
plain exit: since the ISO boots specifically to run this, quitting by
accident would leave a machine that hasn't answered anything. Both call
`unmount_target` first, so a machine shutting down doesn't take a
half-written file system with it, and both do nothing at all under
`--debug`.

The third way out is `console:` in `installer.yaml`, which runs nothing: the
installer closes and the machine keeps running. See [iso/](../iso).

## `auto` and `none`

Two words shared by the lists in `installer.yaml`. `auto` means this machine
works the answer out for itself; `none` means an explicit empty answer.
`lib.sh` resolves both before any task runs, so nothing downstream ever has
to test for either word.

| on `auto` | resolves to |
|---|---|
| `ARCH_OS_VCONSOLE_KEYMAP` | the keyboard the chosen language is typed on, then the live image's own, then `us` |
| `ARCH_OS_DESKTOP_KEYBOARD_LAYOUT` | the same keyboard, in xkb's naming |
| `ARCH_OS_VCONSOLE_FONT` | a font that can draw the chosen language's script |
| `ARCH_OS_REFLECTOR_COUNTRY` | the country the locale's territory names |
| `ARCH_OS_MICROCODE` | whatever `/proc/cpuinfo` reports the processor as |
| `ARCH_OS_DESKTOP_AUTOLOGIN_ENABLED` | follows disk encryption — a password at boot makes a second one at login pointless |

The boot and root partitions are worked out the same way, from the disk.

## Language, and what follows from it

One answer, `ARCH_OS_LOCALE_LANG`, settles the system language and, with it,
the keyboard, the console font, the mirror country and the time zone. None
of that follows automatically from the shape of a locale code: `de_CH` isn't
`de`, `sv` isn't `se`, and a mirror list has never heard of `DE`. So each is
looked up in a table, and every result stays a question the user can
override.

| table | keyed by | provides |
|---|---|---|
| `data/languages` | a language, or a locale where it differs | console keymap, xkb layout, console font |
| `data/countries` | the territory a locale ends in | the country as the mirror list spells it, and its time zone |

`data/x11-layouts` and `data/x11-variants` are only a fallback: the Arch
live image ships no xkeyboard-config, so on the one machine where the
desktop keyboard is actually chosen, there's nothing else to ask.

The **console keyboard** question is `first: true`, so it's asked before the
network screen, before the preflight check, before everything else, and it
takes effect on the live system the instant it's given, through
`apply: load_console_keyboard`. A password typed on the wrong layout isn't
the password.

## Adding something

**An option**: add it to `variables:` in `installer.yaml`. It appears on the
settings page as soon as it exists, and is asked for if it's `required` and
still unanswered. Guard any task that depends on it with `conditions:`.

**A step**: create a folder under `tasks/`, write the two files, and run
`make check`. Nothing else needs to know about it.

**A starting point**: an option under `presets:`. One that fetches its
answers instead of listing them names the question it asks with `asks:` and
the shell that turns the answer into more answers with `apply:`.

**Something in recovery**: none of that lives here — see
[`recovery/`](../recovery), a module of its own.

**A language**:

```sh
cp locales/installer.pot locales/fr.po   # every string this module uses, none translated yet
make check                               # reports coverage per language
```

Fill in the `msgstr` lines and nothing else. `make locales` regenerates
`installer.pot` from the module and updates every catalog against it — run
this whenever a question is added or reworded. The runtime's own strings are
translated separately, in its own `locales/`. See
[TRANSLATING.md](../TRANSLATING.md).

## The command line

Nothing on it belongs to this module. `arch-os --installer` opens it, and
`--debug` beside it is the runtime's own switch — the same word in every
module, passed to every script here as `DEBUG`, which is what `simulating`
checks.

Answers are given inside the interface. A machine set up more than once can
start from an `installer.conf` beside it, or from a shared configuration,
which is a row on the setup page.

## Requirements

Root, the Arch Linux live image, booted in UEFI mode with Secure Boot off,
and a network connection. `hooks/preflight.sh` checks all four before the
first question is asked.

## Where the answers go

`installer.conf`, beside wherever the installer was started, written the
moment any value is given and copied into the new system at the end. The
password is never in it: it's asked for right before installation starts and
forgotten once it's over.

It's also the only way a script can record an answer of its own: a task
appends a `NAME='value'` line to it (see the `share-config` task), and the
runtime reads that file back.
