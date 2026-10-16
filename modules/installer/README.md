# Arch OS Installer

Installs Arch Linux. The module is data: one YAML file and the folders beside it. [Oak](https://github.com/murkl/oak) draws the interface, asks the questions and runs the tasks in order.

**Note:** _Repairing an installation and writing the boot device are separate modules: **[➜ Recovery](../recovery)** · **[➜ Create boot medium](../imager)**_

**Note:** _What it puts on a disk and why: **[➜ Arch OS Reference](../../docs/REFERENCE.md)**. What a declaration may contain, and the contract every `.sh` follows: **[➜ Oak Reference](https://github.com/murkl/oak/blob/main/docs/REFERENCE.md)**._

```
make -C ../.. check                               # load every module and lint every script
make -C ../.. run MODULE=installer ARGS=--debug   # run it without touching this machine
```

## What Is Where

```
module.yaml                     what the Installer is, what it asks, the order it works in, its rules
tasks/@<stage>/<id>/task.yaml   a step: its needs, conditions and pages
tasks/@<stage>/<id>/task.sh     what the step does, with everything only it needs
tasks/@<stage>/<id>/test.sh     optional: how to tell on the machine that it worked
tasks/@<stage>/<id>/data/       every file the step writes into the new system, named after it, filled by render
actions/<id>/action.yaml        an action: its pages, and what a no means
actions/<id>/action.sh          what the action does, and nothing else
data/                           the tables languages and countries are looked up in, and data/check.sh, which checks them
locales/                        one <code>.po per language, and the template they come from
```

**Note:** _Shared code and every function the YAML calls live in **[oak.sh](../../oak.sh)** beside `oak.yaml`. An action the Recovery has too (Wi-Fi, the ways out, sharing the log, the shell) is a folder in each module, and both call the same function there._

## Stages

One folder per stage under `tasks/`, marked with `@`. `module.yaml` orders the stages, `needs:` orders the tasks within one.

| Stage | Tasks |
| --- | --- |
| `prepare` | `mirrors`, `recovery-image`, then `partition`, the one task that destroys data, once everything that can fail has run |
| `system` | `pacstrap`, then `config`, `tweaks`, `bootloader`, `recovery` and `user`: the system on disk, configured and bootable |
| `features` | One task per setting that switches something on: `multilib`, `aur`, `bootsplash`, `containers`, `editor`, `firewall`, `housekeeping`, `manager`, `shell`, `ssh`, `vm-guest` |
| `desktop` | `gnome` first, then `backup`, `browser`, `flatpak`, `graphics`, `recovery-app`, `samba` |
| `finish` | `orphans`, `snapper`, `secure-boot`, and `copy-config` last, which says the system is installed |

**Note:** _`make inspect` prints the order the whole module resolves to._

## Actions

Scripts outside the work, each with its own pages. `action.yaml` says how it behaves, `action.sh` only does it. `module.yaml` names each under the rule it runs by.

| Rule | Actions |
| --- | --- |
| `offer-if` | `live-image`: a booted Arch Linux live image |
| `start-if` | `root`, `uefi`, `secure-boot-off`, then `internet`, which opens `wifi` right away where there is a card and waits for a cable otherwise |
| `on-settings` | `wifi`: **Configure Wi-Fi** in **Setup**, offered where `wifi-card` finds a card and `no-cable` finds no internet over a cable. An open or known network is joined when chosen. One that wants a passphrase opens `wifi-passphrase` |
| `on-leave` | `restart`, `shutdown`: the two ways to put the machine down |
| `on-failure` | `share-log`: uploads the log of a run whose script broke and shows it as a code. A run stopped in plain words offers none, see **[errors](../../docs/CONTRIBUTING.md#when-something-goes-wrong)** |
| `on-success` | `chroot`, `share-config`: a shell in the new system, and its answers uploaded. Both are rows on the page a finished run ends on, which opens on **Continue** |

The online starting point under `presets:` names `import-config`, which fetches the answers.

**Note:** _A cable needs no action: it comes up by itself and is preferred over Wi-Fi while both are up. The third way out is Oak's own **Exit**: the Installer closes and the machine keeps running. See **[iso/](../../iso)**._

## auto and none

Two values the lists in `module.yaml` share. `auto` is worked out in `oak.sh` where a task reads the answer, see `vconsole_keymap` and its neighbours. `none` is an explicit empty answer.

| On `auto` | Resolves to |
| --- | --- |
| `ARCH_OS_VCONSOLE_KEYMAP` | The chosen language's keyboard, then the live system's, then `us` |
| `ARCH_OS_DESKTOP_KEYBOARD_LAYOUT` | The same, in xkb's naming |
| `ARCH_OS_VCONSOLE_FONT` | A font that can draw the chosen script |
| `ARCH_OS_REFLECTOR_COUNTRY` | The country of the chosen time zone |

## Read, Not Asked

What can be read from the machine is never asked.

| What | Read from |
| --- | --- |
| `ARCH_OS_VIRTUAL_MACHINE` | `systemd-detect-virt`: guest tools inside a virtual machine |
| Microcode | `/proc/cpuinfo` |
| Graphics driver | Every graphics card in sysfs, see **[➜ Packages](../../docs/REFERENCE.md#packages)** |
| Automatic login | Disk encryption with one password: on behind it, off otherwise |

## Language

One answer, `ARCH_OS_LOCALE_LANG`, sets keyboard, console font and time zone. None of them follows from the locale code (`de_CH` is not `de`), so each is looked up in `data/` and stays changeable. The mirror country follows the time zone, not the language: `en_US` is typed on every continent, and the time zone is the one answer that says where the machine is.

| Table | Keyed by | Provides |
| --- | --- | --- |
| `data/languages` | Language, or locale where it differs | Keymap, xkb layout, console font |
| `data/countries` | The locale's territory, or the time zone's in `zone.tab` | Time zone, mirror country |

**Note:** _`data/x11-layouts` and `data/x11-variants` are only a fallback: the official Arch live image ships no xkeyboard-config._

The console keyboard is asked `first` and loaded at once: a password typed on the wrong layout is not the password.

## Sharing a Configuration

`installer.conf` can go to **[paste.rs](https://paste.rs)** and comes back as a code you can scan. `actions/share-config`, on the page a finished run ends on, uploads it. `actions/import-config`, behind the online starting point, fetches it.

**Note:** _Uploaded without its `ARCH_OS_CONFIG_*` lines. It holds no password, but hostname, username, disk and language: **anyone with the address can read it**. The import leaves out the disk, a path on the machine it was answered on, and the kernel parameters, which nobody should take on from someone else's code._

## Adding Something

| You want to add | How |
| --- | --- |
| An option | A row under `variables:`. Guard the tasks that depend on it with `conditions:` |
| A step | A folder under its stage with `task.yaml` and `task.sh`, and a `test.sh` where there is something to read back |
| A check, a row or a way out | A folder under `actions/`, named under `rules:` in `module.yaml`. What another module does too is a function in `oak.sh` that both call |
| A starting point | An entry under `presets:`. A fetched one names the action that fetches it with `action:` |
| A language | **[➜ Contributing](../../docs/CONTRIBUTING.md#adding-a-language)** |
| Something in the Recovery | **[➜ Recovery](../recovery)**, none of it lives here |

## Requirements

A booted **Arch Linux live image** (`rules: offer-if` in `module.yaml`). On it: root, then UEFI with Secure Boot off, then the internet (`rules: start-if`, in that order).

**Note:** _`--debug` offers every module and simulates its work._

## Answers

`installer.conf`, beside wherever the Installer was started, and copied into the new system at the end. The password is never in it and never shown in **Setup**.

The Recovery on its partition gets two answers to start with: the language this run was read in, as Oak recorded it in `oak.conf`, and the console keyboard. See `tasks/@system/recovery`.
