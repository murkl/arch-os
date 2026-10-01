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
module.yaml                     what this Installer is, what it asks, what order it runs in, its rules
tasks/@<stage>/<id>/task.yaml   what that step is: its needs, conditions and offers
tasks/@<stage>/<id>/task.sh     what it does - everything only it needs is in here
tasks/@<stage>/<id>/test.sh     optional: how to tell, on the machine, that it took
tasks/@<stage>/<id>/data/       every file it writes into the new system, named after it, filled by render
actions/<id>/action.yaml        an action: one page at most, and what a no means
actions/<id>/action.sh          what it does, and nothing else
data/                           the tables a language and a country are looked up in
locales/                        one <code>.po per language, and the template they come from
```

**Note:** _What several scripts share, here or in another module, and every function the yaml calls, is in **[oak.sh](../../oak.sh)** beside `oak.yaml`. An action the Recovery has too - the wireless network, the ways out, sharing the log, the shell - is a folder in each, and its `action.sh` calls the same function there._

## Stages

One folder per stage under `tasks/`, marked with `@`; `module.yaml` orders them, `needs:` orders the tasks sharing one.

| Stage | Tasks |
| --- | --- |
| `prepare` | `mirrors`, `recovery-image`, then `partition` - the one task that destroys anything, once everything that can fail first has |
| `system` | `pacstrap`, `config`, `user`, `tweaks`, then `bootloader` and `recovery`: the system on disk, configured and bootable |
| `features` | One task per setting that switches something on: `multilib`, `aur`, `bootsplash`, `containers`, `editor`, `firewall`, `housekeeping`, `manager`, `shell`, `ssh`, `vm-guest`, `vm-host` |
| `desktop` | `gnome` first, then `graphics`, `browser`, `backup`, `flatpak`, `recovery-app`, `samba` |
| `finish` | `first-login`, `orphans`, `snapper`, `secure-boot`, and `copy-config` last, which says the system is installed |

**Note:** _`make inspect` prints the order the whole module resolves to._

## Actions

Scripts run outside the work, one page at most each: `action.yaml` says how it behaves, `action.sh` only does it. `module.yaml` names each under the rule it runs by.

| Rule | Actions |
| --- | --- |
| `offer-if` | `live-image`: a booted Arch Linux live image |
| `start-if` | `root`, `uefi`, `secure-boot-off`, then `internet`, which opens `wifi` on failure where there is a card and waits for a cable otherwise |
| `menu` | `wifi`: **Wireless network**, offered if `wifi-card` finds a card. An open or known network joins as it is chosen; one that wants a passphrase opens `wifi-passphrase` on failure |
| `on-leave` | `restart`, `shutdown`: the two ways this machine is put down |
| `on-failure` | `share-log`: the log of a run that failed, put online and drawn as a code |
| `on-success` | `chroot`, `share-config`: a shell in the new system, and its answers put online - rows on the page a finished run ends on, which opens on **Continue** |

The online starting point under `presets:` names `import-config`, which fetches the answers.

**Note:** _A cable needs no action: it comes up by itself and is preferred over a wireless network while both are up. The third way out is Oak's own **Exit**: the Installer closes, the machine keeps running. See **[iso/](../../iso)**._

## auto and none

Two words the lists in `module.yaml` share. `auto`: worked out in `oak.sh` where a task reads the answer - `vconsole_keymap` and its neighbours. `none`: an explicit empty answer.

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

`installer.conf` can be uploaded to **[paste.rs](https://paste.rs)** and comes back as a scannable code: `actions/share-config` on the page a finished run ends on uploads it, `actions/import-config` behind the online starting point fetches it.

**Note:** _Uploaded without its `ARCH_OS_CONFIG_*` lines. No password, but hostname, username, disk and language are in it - **anyone holding the address can read it**. The disk is left out when it is fetched again: it names a path on the machine it was answered on, so the next one asks for its own._

## Adding something

| You want to add | How |
| --- | --- |
| An option | A row under `variables:`. Guard dependent tasks with `conditions:` |
| A step | A folder under its stage, `task.yaml` + `task.sh`, a `test.sh` where there is something to read back |
| A check, a row or a way out | A folder under `actions/`, named under `rules:` in `module.yaml`. What another module does alike is a function in `oak.sh` both call |
| A starting point | An entry under `presets:`. A fetched one names the action that fetches it with `action:` |
| A language | **[➜ Contributing](../../docs/CONTRIBUTING.md#adding-a-language)** |
| Something in the Recovery | **[➜ Recovery](../recovery)**, none of it lives here |

## Requirements

A booted **Arch Linux live image** - `rules: offer-if` in `module.yaml`. On it: root, then UEFI with Secure Boot off, then the internet - `rules: start-if`, in that order.

**Note:** _`--debug` offers every module and simulates its work._

## Answers

`installer.conf`, beside wherever the Installer was started, copied into the new system at the end. The password is never in it, and never on the settings page.

The Recovery on its partition is handed two of them to start with: the language this run was read in, as Oak recorded it in `oak.conf`, and the console keyboard - see `tasks/@system/recovery`.
