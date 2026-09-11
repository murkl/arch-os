# Arch OS Installer

Everything this Installer knows about Arch Linux. It is data — one YAML file and the folders beside it — and it does not run on its own: [Oak](https://github.com/murkl/oak) draws the interface, asks the questions and runs the tasks in order.

**Note:** _Repairing a system already on disk is a separate module: **[➜ Arch OS Recovery](../recovery)**_

```
make -C ../.. check                               # load both modules and lint every script
make -C ../.. run MODULE=installer ARGS=--debug   # run it without touching this machine
```

## What is where

```
module.yaml                     what this Installer is, what it asks, what order it runs in
module.sh                       what more than one script has to agree about
tasks/<id>/task.yaml            what that step is: its stage, needs, conditions and offers
tasks/<id>/task.sh              what it does, plus any file it ships with, beside it
tasks/<id>/test.sh              optional: how to tell, on the machine, that it took
hooks/@<hook>/<id>/hook.yaml    a moment Oak runs itself, rather than as part of the work
hooks/@<hook>/<id>/hook.sh      what that step does, where its yaml does not say so itself
data/                           the tables a language and a country are looked up in
locales/                        one <code>.po per language, and the template they come from
```

**Note:** _Nothing in `module.yaml` points at any of this — each part is found by its own name. Every key those files may use is in the **[Oak reference](https://github.com/murkl/oak/blob/main/docs/REFERENCE.md)**._

## Stages

Every folder under `tasks/` is one task, flat. Nothing lists them elsewhere: the folders are the list. Which phase a task belongs to is the `stage:` in its `task.yaml`; `module.yaml` declares those stages top to bottom, and `needs:` orders the tasks that share one.

| Stage | Description |
| --- | --- |
| `prepare` | The live system, made ready to install from |
| `disk` | Partitioned, encrypted, formatted, mounted. The only stage that destroys anything |
| `base` | The system on disk, configured, with an account created |
| `boot` | The boot loader and the kernel command line |
| `system` | Everything that gets switched on rather than installed |
| `desktop` | GNOME, its driver and whatever belongs to it |
| `finalize` | The last steps on the new system |
| `finish` | What is offered once the installation is complete |

Three orderings matter, and each is a stage or a `needs:`:

1. The disk has to exist before anything is installed onto it
2. 32-bit support has to be enabled before any package that needs it is pulled in
3. The boot chain is signed last, since signing only holds if nothing rebuilds the kernel image afterwards

**Note:** _`make check` prints the order the whole module resolves to._

## Hooks

`hooks/` is the module's other half, and a folder of its own because it answers to something else: a task is this Installer's work — listed, ordered, guarded — while a hook is its answer to a question Oak asks at a moment of Oak's choosing. One folder per hook, one per step inside it, `hook.yaml` and `hook.sh`.

| Hook | Description |
| --- | --- |
| `@preflight` | Four checks, in order, before the first question: root, the live image, UEFI with Secure Boot off, and a network |
| `@online`, `@wlan-device`, `@wlan-networks`, `@wlan-connect` | Finding and joining a wireless network |
| `@restart`, `@shutdown` | The two ways this machine is put down, each closing the target first |

The last two turn leaving the Installer into a choice rather than a plain exit: the ISO boots specifically to run this. Both call `close_target` first, so a machine shutting down does not take a half-written file system with it, and both do nothing under `--debug`.

**Note:** _The third way out is `console:` in `module.yaml`, which runs nothing: the Installer closes and the machine keeps running. See **[iso/](../../iso)**._

## Writing a Task

A folder under `tasks/`, holding `task.yaml` and `task.sh`. Oak runs the script in a shell that already carries `module.sh` and an `ERR` trap, so it needs no shebang, no `set -e` and no error handling.

```
# tasks/thing/task.sh
simulating && return 0

chroot_pacman_install git base-devel
arch-chroot "$MNT" systemctl enable something.service
cp "$(where)/thing.conf" "${MNT}/etc/thing.conf"
```

A step short enough to read at a glance skips the file and writes its shell in the YAML instead, which is what the two-line ones here do:

```yaml
# tasks/thing/task.yaml
title: Install the thing
stage: system
execute: |
  simulating && return 0

  chroot_pacman_install thing
```

`simulating && return 0` is the first line of every task, before anything that changes the machine — that is what turns `--debug` into a simulation. `where` returns the task's own folder.

`module.sh` is deliberately small: only what several tasks must agree about, such as the mount point, the kernel command line and how a package is installed and retried, plus the functions `module.yaml` calls by name for its lists. Everything else belongs in the task that does it, even when that makes the script longer.

**Note:** _Anything that needs a desktop session which does not exist yet — GNOME settings live in the session's own database — goes through `on_first_login`, which collects those lines into a script that runs once at the first login and then removes itself._

**[➜ See AGENTS.md](../../AGENTS.md#shell-the-task-contract)** for the whole contract.

## Checking a Step

A task may also say how to tell, on the machine itself, that the work took. That is a `test.sh` beside `task.sh`, or a `test:` in the YAML for something short:

```
# tasks/thing/test.sh
arch-chroot "$MNT" systemctl is-enabled something.service >/dev/null
[ -f "${MNT}/etc/thing.conf" ]
```

It runs right after the task, and it has one rule: **it reads and nothing else**. No `simulating` guard either — a simulated run writes nothing, so Oak runs no checks at all in one.

Check the outcome, not the steps that produced it: the service is enabled, the account has a password, the loader is installed. A check that restates the script line by line is a second copy of the task, and it is the copy that goes stale.

A check that disagrees does not fail the installation — the task itself already said it worked. They are collected and read once, on the page the run ends with. The switch that turns the whole of it off is in the settings.

## auto and none

Two words shared by the lists in `module.yaml`. `auto` means this machine works the answer out for itself, `none` means an explicit empty answer. `module.sh` resolves both before any task runs, so nothing downstream ever tests for either word.

| On `auto` | Resolves to |
| --- | --- |
| `ARCH_OS_VCONSOLE_KEYMAP` | The keyboard the chosen language is typed on, then the live image's own, then `us` |
| `ARCH_OS_DESKTOP_KEYBOARD_LAYOUT` | The same keyboard, in xkb's naming |
| `ARCH_OS_VCONSOLE_FONT` | A font that can draw the chosen language's script |
| `ARCH_OS_REFLECTOR_COUNTRY` | The country the locale's territory names |
| `ARCH_OS_MICROCODE` | Whatever `/proc/cpuinfo` reports the processor as |
| `ARCH_OS_DESKTOP_AUTOLOGIN_ENABLED` | Follows disk encryption — a password at boot makes a second one at login pointless |

**Note:** _The boot and root partitions are worked out the same way, from the disk._

## Language, and what follows from it

One answer, `ARCH_OS_LOCALE_LANG`, settles the system language and with it the keyboard, the console font, the mirror country and the time zone. None of that follows from the shape of a locale code — `de_CH` is not `de`, `sv` is not `se`, and a mirror list has never heard of `DE` — so each is looked up in a table, and every result stays a question the user can override.

| Table | Keyed by | Provides |
| --- | --- | --- |
| `data/languages` | A language, or a locale where it differs | Console keymap, xkb layout, console font |
| `data/countries` | The territory a locale ends in | The country as the mirror list spells it, and its time zone |

**Note:** _`data/x11-layouts` and `data/x11-variants` are only a fallback: the Arch live image ships no xkeyboard-config._

The console keyboard is asked `first`, before the network screen and before the preflight check, and takes effect on the live system the instant it is given through `apply: load_console_keyboard`. A password typed on the wrong layout is not the password.

## Sharing a Configuration

The finished `installer.conf` can be uploaded to **[paste.rs](https://paste.rs)** — no account, no key — and its address comes back as a scannable code. Both ends live in the `share-config` task:

| File | Description |
| --- | --- |
| `task.sh` | Uploads the file and records the address as `ARCH_OS_CONFIG_URL`. Never fails an installation that has already succeeded |
| `import.sh` | Fetches one and appends it to the answer file, given either the full address or just the code at the end of it |

The upload is a `confirm:` that opens on **no**, asked immediately after the page saying the installation is done. There is no setting for it anywhere else: a switch among the earlier answers would collect consent before there was anything to consent to.

**Note:** _What is uploaded is the answer file without its `ARCH_OS_CONFIG_*` lines. The password is not in it, but the hostname, username, disk and language are. **Anyone holding the address can read it.**_

## Adding something

| You want to add | How |
| --- | --- |
| An option | A row under `variables:` in `module.yaml`. Guard any task that depends on it with `conditions:` |
| A step | A folder under `tasks/` with `task.yaml` and `task.sh` in it — and a `test.sh` where there is something to read back — then `make check` |
| A starting point | An option under `presets:`. One that fetches its answers names the question with `asks:` and the shell that turns it into more answers with `apply:` |
| A language | **[➜ See Contributing](../../docs/CONTRIBUTING.md#adding-a-language)** |
| Something in the Recovery | **[➜ Arch OS Recovery](../recovery)**, none of it lives here |

## Requirements

Root, the Arch Linux live image, booted in UEFI mode with Secure Boot off, and a network connection. The four steps under `hooks/@preflight/` check them in that order, before the first question is asked.

## Where the Answers go

`installer.conf`, beside wherever the Installer was started, written the moment any value is given and copied into the new system at the end. The password is never in it: it is asked for right before the installation starts and forgotten once it is over.

**Note:** _It is also the only way a script records an answer of its own: a task appends a `NAME='value'` line to `$MODULE_CONF` — see the `share-config` task — and Oak reads that file back._
