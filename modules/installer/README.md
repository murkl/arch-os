# Arch OS Installer

Everything this Installer knows about Arch Linux. It is data, one YAML file and the folders beside it, and it does not run on its own: the [runtime](../../runtime) draws the interface, asks the questions and runs the tasks in order.

**Note:** _Repairing a system already on disk is a separate module: **[➜ Arch OS Recovery](../recovery)**_

```
make check                                              # load the module and lint every script
make -C ../../runtime run MODULE=installer ARGS=--debug # run it without touching this machine
```

## What is where

```
installer.yaml           what this Installer is, what it asks, what order it runs in
tasks/<id>/task.yaml     where that step belongs: its stage, its dependencies, its conditions
tasks/<id>/task.sh       what it does, plus any file it ships with, beside it
hooks/<name>.sh          everything around the work itself
lib.sh                   the small shared library every script in this module uses
data/                    the tables a language and a country are looked up in
locales/                 one <code>.po per language, and the template they are filled in from
```

**Note:** _Nothing in `installer.yaml` points at any of this. Each part is found by its own name._

A release is the runtime binary with `runtime.yaml` beside it and a `modules/` folder holding this module and the Recovery: one binary, two modules, and which one to open is a page in the interface.

## What a Run is called

`installer.yaml` sets `run: Installation`, which the interface reads out wherever it reports what is happening: the row that starts it, the final warning, the clock while it runs. `description:` next to it is the sentence shown under this module's row on the page that asks which module to open.

**Note:** _Leave `run` out and the runtime defaults to "Installation", which is correct here but wrong in the Recovery, which names its own run differently._

## Tasks

Every folder under `tasks/` is a step and nothing lists them elsewhere: the folder itself is the list. `installer.yaml` declares the stages top to bottom, every task belongs to one and `needs:` orders the tasks that share a stage.

```
# tasks/aur-helper/task.yaml
name: Install the AUR helper
stage: system
needs: [enable-multilib]
conditions: ARCH_OS_AUR_HELPER != none
```

| Stage | Description |
| --- | --- |
| `prepare` | The live system, made ready to install from |
| `disk` | Partitioned, encrypted, formatted, mounted. The only stage that destroys anything |
| `base` | The system on disk, configured, with an account created |
| `boot` | The boot loader and the kernel command line |
| `system` | Everything that gets switched on rather than installed |
| `desktop` | GNOME, its driver and whatever belongs to it |
| `finalize` | The last steps on the new system |
| `finish` | What is offered once installation is complete |

Three orderings matter and each is captured as a `needs:` or a stage:

1. The disk has to exist before anything is installed onto it
2. 32-bit support has to be enabled before any package that needs it is pulled in
3. The boot chain is signed last, since signing only holds if nothing rebuilds the kernel image afterwards

**Note:** _`make check` prints the order the whole module resolves to._

### Writing a Task

A task is a folder with two files in it. The runtime **sources** the script into a shell that already has an `ERR` trap and `lib.sh` loaded, so it needs no shebang, no `set -e`, no imports and no error handling. If a command fails, the task fails and the interface shows the file, the line, the command and the exit code.

```
# tasks/thing/task.sh
simulating && return 0

chroot_pacman_install git base-devel
arch-chroot "$MNT" systemctl enable something.service
cp "$(where)/thing.conf" "${MNT}/etc/thing.conf"
```

The first line is what turns `--debug` into a simulation instead of a real installation. It belongs at the top of every task, before the first command that changes anything. `where` returns the task's own folder.

Three rules:

- **Ask nothing.** Every question is declared in `installer.yaml` and asked by the interface, unless the task sets `tty: true`, which deliberately hands it the whole terminal
- **Print nothing for a person to read.** stdout and stderr go to the log. What is on screen is the task's name
- **Do one thing.** A task is one line in a list somebody is watching

`lib.sh` is kept deliberately small. What is in it is there because several tasks need the same answer and must not disagree about it: the kernel command line, the mount point, how a package is installed and retried. Everything else belongs in the task that does it, even if that means a longer script.

**Note:** _Anything a task cannot do because there is no user session yet (GNOME settings live in the session's own database) goes through `on_first_login`, which collects those lines into a script that runs once at the first login and then removes itself._

### Keys that change what a Task is

```
asks: ARCH_OS_CONFIG_SOURCE                       # a value asked mid-run, before the confirmation
confirm: Restart into {{ARCH_OS_HOSTNAME}} now?   # a yes/no shown before the task runs, no skips it
default: no                                       # which of the two that confirmation defaults to
report: |                                         # the run pauses on a page of its own
  Arch OS is installed
shows: ARCH_OS_CONFIG_URL                         # an answer shown on that page as a scannable code
quits: true                                       # the program does not return after this task
tty: true                                         # hand it the terminal, and take it back afterwards
```

That is how everything after installation (copying the answers, sharing them online, opening a shell in the new system, restarting, unmounting) ends up as a task in the `finish` stage rather than a page of its own.

- `asks:` is for a value there is nothing to choose from until the run reaches that task. The Recovery's snapshot list is the example it exists for
- `report:` marks the moment the work is done and everything after it is optional, which a plain list of task names cannot express on its own

## Sharing a Configuration

The finished `installer.conf` can be uploaded to **[paste.rs](https://paste.rs)** (no account, no key) and its address comes back as a scannable code. Both ends live in the `share-config` task:

| File | Description |
| --- | --- |
| `task.sh` | Uploads the file and records the address as `ARCH_OS_CONFIG_URL`. Never fails an installation that has already succeeded |
| `import.sh` | Fetches one and appends it to the answer file, given either the full link or just the code at the end of it |

The upload is a `confirm:` that defaults to **no**, asked immediately after the page confirming the installation is done. There is no setting for it anywhere else: a switch among the earlier answers would collect consent before there was anything to consent to. Say no and nothing is sent.

**Note:** _What gets uploaded is the answer file with its `ARCH_OS_CONFIG_*` lines stripped out. The password is not in it, but the hostname, username, disk and language are. **Anyone holding the address can read it.**_

The other end is the third preset, `Online (paste.rs)`: it asks for the code, `import.sh` turns it into answers, and from the next page on those answers behave like any other.

## Hooks

Bash scripts the runtime calls by name. A hook that exists gets used, one that does not turns off that part of the interface. Any other file name under `hooks/` is rejected when the module loads.

| Hook | Description |
| --- | --- |
| `preflight.sh` | Checks root, the live image, UEFI, Secure Boot off and a network connection |
| `online.sh` | Whether there is internet |
| `wlan-device.sh` | Which wireless device to use |
| `wlan-networks.sh` | Scans and prints one SSID per line |
| `wlan-connect.sh` | Joins one, with `WLAN_DEVICE`, `WLAN_SSID` and `WLAN_PASSPHRASE` in the environment |
| `restart.sh` | Close the target system and reboot |
| `shutdown.sh` | Close the target system and power off |

The last two turn leaving the Installer into a choice rather than a plain exit: the ISO boots specifically to run this, so quitting by accident would leave a machine that has answered nothing.

**Note:** _Both call `unmount_target` first, so a machine shutting down does not take a half-written file system with it, and both do nothing at all under `--debug`._

The third way out is `console:` in `installer.yaml`, which runs nothing: the Installer closes and the machine keeps running. See **[iso/](../../iso)**.

## auto and none

Two words shared by the lists in `installer.yaml`. `auto` means this machine works the answer out for itself, `none` means an explicit empty answer. `lib.sh` resolves both before any task runs, so nothing downstream ever has to test for either word.

| On `auto` | Resolves to |
| --- | --- |
| `ARCH_OS_VCONSOLE_KEYMAP` | The keyboard the chosen language is typed on, then the live image's own, then `us` |
| `ARCH_OS_DESKTOP_KEYBOARD_LAYOUT` | The same keyboard, in xkb's naming |
| `ARCH_OS_VCONSOLE_FONT` | A font that can draw the chosen language's script |
| `ARCH_OS_REFLECTOR_COUNTRY` | The country the locale's territory names |
| `ARCH_OS_MICROCODE` | Whatever `/proc/cpuinfo` reports the processor as |
| `ARCH_OS_DESKTOP_AUTOLOGIN_ENABLED` | Follows disk encryption. A password at boot makes a second one at login pointless |

**Note:** _The boot and root partitions are worked out the same way, from the disk._

## Language, and what follows from it

One answer, `ARCH_OS_LOCALE_LANG`, settles the system language and with it the keyboard, the console font, the mirror country and the time zone. None of that follows automatically from the shape of a locale code: `de_CH` is not `de`, `sv` is not `se` and a mirror list has never heard of `DE`. So each is looked up in a table and every result stays a question the user can override.

| Table | Keyed by | Provides |
| --- | --- | --- |
| `data/languages` | A language, or a locale where it differs | Console keymap, xkb layout, console font |
| `data/countries` | The territory a locale ends in | The country as the mirror list spells it, and its time zone |

**Note:** _`data/x11-layouts` and `data/x11-variants` are only a fallback: the Arch live image ships no xkeyboard-config._

The console keyboard question is `first: true`, so it is asked before the network screen, before the preflight check and before everything else. It takes effect on the live system the instant it is given, through `apply: load_console_keyboard`. A password typed on the wrong layout is not the password.

## Adding something

| You want to add | How |
| --- | --- |
| An option | Add it to `variables:` in `installer.yaml`. Guard any task that depends on it with `conditions:` |
| A step | Create a folder under `tasks/`, write the two files, run `make check` |
| A starting point | An option under `presets:`. One that fetches its answers names the question with `asks:` and the shell that turns it into more answers with `apply:` |
| Something in the Recovery | None of that lives here, see **[Arch OS Recovery](../recovery)** |

Adding a language:

```
cp locales/installer.pot locales/fr.po   # every string this module uses, none translated yet
make check                               # reports coverage per language
```

Fill in the `msgstr` lines and nothing else. `make locales` regenerates `installer.pot` from the module and updates every catalog against it.

**[➜ See Translating](../../TRANSLATING.md)**

## The Command Line

Nothing on it belongs to this module. On the ISO, `installer` is `arch-os --installer`: the runtime with this module already named. `--debug` beside it is the runtime's own switch, the same word in every module, passed to every script here as `DEBUG`, which is what `simulating` checks.

**Note:** _Answers are given inside the interface. A machine set up more than once can start from an `installer.conf` beside it, or from a shared configuration, which is a row on the setup page._

## Requirements

Root, the Arch Linux live image, booted in UEFI mode with Secure Boot off, and a network connection.

**Note:** _`hooks/preflight.sh` checks all four before the first question is asked._

## Where the Answers go

`installer.conf`, beside wherever the Installer was started, written the moment any value is given and copied into the new system at the end. The password is never in it: it is asked for right before installation starts and forgotten once it is over.

**Note:** _It is also the only way a script can record an answer of its own: a task appends a `NAME='value'` line to it (see the `share-config` task) and the runtime reads that file back._
