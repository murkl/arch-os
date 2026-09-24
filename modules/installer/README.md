# Arch OS Installer

Everything this Installer knows about Arch Linux. It is data - one YAML file and the folders beside it - and it does not run on its own: [Oak](https://github.com/murkl/oak) draws the interface, asks the questions and runs the tasks in order.

**Note:** _Repairing a system already on disk and writing the device this boots from are separate modules: **[➜ Recovery](../recovery)** · **[➜ Create boot medium](../imager)**_

**Note:** _What this puts on a disk and why: **[➜ Arch OS Reference](../../docs/REFERENCE.md)**. What a declaration may contain, and the contract every `.sh` here follows: **[➜ Oak Reference](https://github.com/murkl/oak/blob/main/docs/REFERENCE.md)**._

```
make -C ../.. check                               # load every module and lint every script
make -C ../.. run MODULE=installer ARGS=--debug   # run it without touching this machine
```

## What is where

```
module.yaml                     what this Installer is, what it asks, what order it runs in
module.sh                       what more than one script has to agree about
tasks/@<stage>/<id>/task.yaml   what that step is: its needs, conditions and offers
tasks/@<stage>/<id>/task.sh     what it does
tasks/@<stage>/<id>/test.sh     optional: how to tell, on the machine, that it took
tasks/@<stage>/<id>/data/       every file it writes into the new system, named after it, filled by render
hooks/@<hook>/<id>/hook.yaml    a moment Oak runs itself, rather than as part of the work
data/                           the tables a language and a country are looked up in
locales/                        one <code>.po per language, and the template they come from
```

## Stages

One folder per stage under `tasks/`, marked with `@`; `module.yaml` orders them, `needs:` orders the tasks sharing one.

| Stage | Description |
| --- | --- |
| `prepare` | The live system, made ready to install from, the Recovery image at hand |
| `disk` | Partitioned, encrypted, formatted, mounted - the only stage that destroys anything |
| `base` | The system on disk, configured, with an account |
| `boot` | The images the firmware starts, the loader, and the Recovery beside them |
| `system` | Everything switched on rather than installed |
| `desktop` | GNOME, its driver, whatever belongs to it |
| `finalize` | The last steps on the new system |
| `handover` | What is offered once installed, and the ways out |

**Note:** _`make inspect` prints the order the whole module resolves to._

## Hooks

Oak's own moments, not this module's work: one folder per hook, one per step, `hook.yaml` and `hook.sh`.

| Hook | Description |
| --- | --- |
| `@preflight` | root, then UEFI with Secure Boot off, then a network |
| `@online`, `@wlan-device`, `@wlan-networks`, `@wlan-connect` | Finding and joining a wireless network |
| `@restart`, `@shutdown` | The two ways this machine is put down, each closing the target first |

**Note:** _The third way out is `console:` in `module.yaml`: the Installer closes, the machine keeps running. See **[iso/](../../iso)**._

## auto and none

Two words the lists in `module.yaml` share. `auto`: worked out by `module.sh` before any task runs. `none`: an explicit empty answer.

| On `auto` | Resolves to |
| --- | --- |
| `ARCH_OS_VCONSOLE_KEYMAP` | The chosen language's keyboard, then the live image's own, then `us` |
| `ARCH_OS_DESKTOP_KEYBOARD_LAYOUT` | The same, in xkb's naming |
| `ARCH_OS_VCONSOLE_FONT` | A font that can draw the chosen script |
| `ARCH_OS_REFLECTOR_COUNTRY` | The country of the chosen time zone |

## Read, not asked

What the machine can say for itself is never a question.

| What | Read from |
| --- | --- |
| `ARCH_OS_VIRTUAL_MACHINE` | `systemd-detect-virt`: guest tools inside a virtual machine, the question about running them outside one |
| Microcode | `/proc/cpuinfo` |
| Graphics driver | Every graphics card in sysfs - see **[➜ Packages](../../docs/REFERENCE.md#packages)** |
| Automatic login | Disk encryption: on behind it, off without it |

## Language

One answer, `ARCH_OS_LOCALE_LANG`, settles keyboard, console font and time zone - none of which follow from the locale code itself (`de_CH` is not `de`), so each is looked up in `data/` and stays overridable. The mirror country follows the time zone rather than the language: `en_US` is typed on every continent, and the time zone is the one answer that says where the machine stands.

| Table | Keyed by | Provides |
| --- | --- | --- |
| `data/languages` | Language, or locale where it differs | Keymap, xkb layout, console font |
| `data/countries` | The locale's territory, or the time zone's in `zone.tab` | Time zone, mirror country |

**Note:** _`data/x11-layouts` and `data/x11-variants` are a fallback only - the official Arch live image ships no xkeyboard-config._

The console keyboard is asked `first` and takes effect immediately: a password typed on the wrong layout is not the password.

## Sharing a Configuration

`installer.conf` can be uploaded to **[paste.rs](https://paste.rs)** and comes back as a scannable code - the `share-config` task (`task.sh` uploads, `import.sh` fetches). Opens on **no**, right after the installation is done.

**Note:** _Uploaded without its `ARCH_OS_CONFIG_*` lines. No password, but hostname, username, disk and language are in it - **anyone holding the address can read it**. The disk is left out when it is fetched again: it names a path on the machine it was answered on, so the next one asks for its own._

## Adding something

| You want to add | How |
| --- | --- |
| An option | A row under `variables:`. Guard dependent tasks with `conditions:` |
| A step | A folder under its stage, `task.yaml` + `task.sh`, a `test.sh` where there is something to read back |
| A starting point | An option under `presets:`. Fetched ones name their question with `asks:` and their shell with `apply:` |
| A language | **[➜ Contributing](../../docs/CONTRIBUTING.md#adding-a-language)** |
| Something in the Recovery | **[➜ Recovery](../recovery)**, none of it lives here |

## Requirements

A booted **Arch Linux live image** - `requires:` in `module.yaml`. On it: root, UEFI with Secure Boot off, a network - `hooks/@preflight/`, in that order.

**Note:** _`--debug` offers every module and simulates its work._

## Answers

`installer.conf`, beside wherever the Installer was started, copied into the new system at the end. The password is never in it, and never on the settings page.

The Recovery on its partition is handed two of them to start with: the language this run was read in, as Oak recorded it in `oak.conf`, and the console keyboard - `RECOVERY_SEED` in `module.sh`.
