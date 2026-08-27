# Arch OS Installer

Everything this installer knows about Arch Linux. It is data — one YAML file and
a folder of tasks — and it does not run on its own: the [runtime](../runtime)
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
installer.yaml           what the installer is, what it asks, what order it works in
tasks/<id>/task.yaml     where that unit belongs: its stage, its needs, its conditions
tasks/<id>/task.sh       what it does — and any file it ships with, beside it
tasks/_lib/              what they all share: lib.sh, the catalogs, static data
installer                the runtime (a build artefact, not part of the tree)
```

A folder under `tasks/` whose name starts with `_` is not a unit. Everything
else there is one, and nothing lists them: the folder is the list.

## The order things happen in

`installer.yaml` declares the stages, top to bottom. Every task names one,
and `needs:` orders the ones that share a stage — the same idea as a CI
pipeline, and for the same reason: what has to come first is a property of the
unit, not of a list somebody maintains by hand.

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

Three orderings are load bearing, and each is written down as a `needs:` or as a
stage: the disk exists before anything is installed onto it, 32-bit support is
switched on before any package that needs it is pulled in, and the boot chain is
signed last — signing only holds if nothing rebuilds the kernel image
afterwards.

`make check` prints the order the whole tree adds up to. It is the one thing
about an installer nobody writes down, so it is worth reading after every change.

## Writing a task

A unit is a folder with two files in it. The script is **sourced** by the runtime
into a shell that already carries an `ERR` trap and the shared library, so it
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

## Tasks that ask, and one that takes the terminal

Three keys change what a unit is rather than what it does:

```yaml
confirm: Restart into {{ARCH_OS_HOSTNAME}} now?   # a yes or no in the frame; no skips it
quits: true                                       # the program does not come back from this
tty: true                                         # hand it the terminal, and take it back after
```

That is how everything after the installation — a copy of the answers, a shell
in the new system, a restart, an unmount — is a task of the `finish` stage like
any other, rather than a page of its own.

## The way out

Not an exit but a question: the ISO boots to run this, so quitting by accident
would leave a machine that answers nothing. `leave:` in `installer.yaml` is what
replaces quitting —

```yaml
leave:
  restart: restart_machine
  shutdown: shutdown_machine
  console: Type installer at the prompt to start it again.
```

— so ctrl+c, the row that says quit, backing off the first page and the end of
an installation all land on the same three answers. The two functions live in
`_lib/lib.sh`, unmount whatever the installation had open, and do nothing at all
under `DEBUG=true`.

`console:` runs nothing: the installer closes and the machine keeps running. It
is declared because on this image there *is* something behind the interface —
the systemd unit that started the installer hands tty1 to a root shell when it
stops, whether it stopped because somebody chose this row or because it crashed.
`installer` there starts it again, out of `/opt/installer` and from the answers
already given, because the prompt and the unit run the same script. The sentence
above is what the interface prints on the way out; `/etc/motd` says it again on
the way in. See [iso/](../iso).

## `auto` and `none`

The two words the lists in `installer.yaml` share. `auto` says this machine works
the answer out; `none` is the empty answer said out loud. `_lib/lib.sh` resolves
both before any task runs, so nothing downstream ever tests for either word —
and each stays a variable anyone can answer outright.

| on `auto` | comes to |
|---|---|
| `ARCH_OS_VCONSOLE_KEYMAP` | the keyboard the language is typed on, then the live image's own, then `us` |
| `ARCH_OS_DESKTOP_KEYBOARD_LAYOUT` | the same keyboard in xkb's names |
| `ARCH_OS_VCONSOLE_FONT` | the font that can draw the language's script |
| `ARCH_OS_REFLECTOR_COUNTRY` | the country the locale's territory names |
| `ARCH_OS_MICROCODE` | whatever `/proc/cpuinfo` says the processor is |
| `ARCH_OS_DESKTOP_AUTOLOGIN_ENABLED` | disk encryption — a password at boot makes a second one at login pointless |

The boot and root partitions are worked out the same way, from the disk.

The first four come out of the language, and out of the tables in `_lib/data`
rather than out of the shape of a locale's name: `de_CH` is not `de`, `sv` is not
`se`, and a mirror list has never heard of `DE`. The same tables fill the lists
those questions offer, so what a page shows beside `auto` and what a task gets
can never disagree.

## The first two pages

**The language of the interface** comes first, before anything else — it is the
runtime's own page, and this tree declares nothing to make it appear beyond the
catalogs under `_lib/locales`. It settles the words on screen and nothing else:
it is a setting of the program, not an answer about the machine, and it is a row
in the settings afterwards. Installing a German system from an English installer
is an ordinary thing to do.

**The console keyboard** comes second: `ARCH_OS_VCONSOLE_KEYMAP` is `first: true`,
so it is asked before the network screen, before the preflight, before every
other question. It is the one answer that also has to take effect *here*, on the
live system, the moment it is given — hence `apply: load_console_keyboard` on it.
Until `loadkeys` has run, everything typed after it is typed on a layout nobody
chose, and a password typed on the wrong one is not the password. It has no
`default:` for exactly that reason: a default would answer it, and then it would
never be asked.

Everything else about the region is an ordinary question in the opening run —
the system language, the console font, the time zone, the mirror country. Each
follows the language on `auto`, and each can be answered outright:

| what it settles | how |
|---|---|
| the system language and its formats | `ARCH_OS_LOCALE_LANG` — every locale the system can generate, as plain codes: `de_DE`, `en_GB`. Press `/` to narrow the list |
| the keyboard, the console font, the mirror country | `auto`, above — they follow from the language |
| the time zone | asked, opening on the zone the chosen country keeps |

`_lib/data/regions` is what lets the time zone follow the language: one row per
locale, naming the zone the country behind it keeps. It is a suggestion — the
row the list opens on — never an answer.

## Adding a preset

`presets:` is a list of pages, each one question and the options it is answered
with. A page is offered once, on a machine that has never answered anything, and
what it fills in is an ordinary answer from the next page on — visible on the
settings page, changeable like anything else.

```yaml
presets:
  - id: system
    title: Setup
    description: Choose what kind of system to install.
    options:
      - id: minimal
        title: Minimal
        description: Arch Linux on the console only.
        values:
          ARCH_OS_DESKTOP_ENABLED: false
```

An option that names no values fills in nothing, and then the questions behind
it are simply asked.

## Adding something

**A new option** — add it to `variables:` in `installer.yaml`. It is on the
settings page the moment it exists, and asked for if it is `required` and nothing
answers it. Guard the tasks that care with `conditions:`.

**A new step** — make a folder under `tasks/`, write the two files, and `make
check`. Nothing else has to be told about it.

**A new language** —

```sh
make strings > tasks/_lib/locales/fr.yaml   # every word this tree says, empty
make check                                  # reports coverage per language
```

The runtime's own words — key hints, buttons, the labels on a failure report —
are translated separately, in the runtime's own `locales/`.

## Requirements

Root, the Arch Linux live image, booted in UEFI mode with Secure Boot off, and a
network. The `preflight` task checks all four before anything is asked bar the
keyboard; it belongs to no stage, which is what makes it run first.

## Trying it out

```sh
DEBUG=true make -C ../runtime run
```

Every wall in the preflight steps aside and every task reports success without
doing anything, so the questions, the wording and the order of the tasks can be
tried out on an ordinary running system, as an ordinary user. It installs
nothing. The guard is `simulating && return 0` at the top of each task — see
`tasks/_lib/lib.sh`.

## Where the answers go

`installer.conf` beside wherever the installer was started, written the moment
any value is given, and copied into the new system at the end. The password is
never in it: it is asked for immediately before the installation starts and
forgotten when it is over.

## Credit

The Arch Linux logic here is a port of [murkl/arch-os](https://github.com/murkl/arch-os),
whose `installer.sh` this tree was carved out of.
