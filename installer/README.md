# Arch OS Installer

Installs Arch OS. The module is data: one YAML file and a folder per task. The **[runtime](../runtime)** draws the interface, asks the questions and runs the tasks in order.

**Note:** _Repairing an installation is a separate module: **[➜ Recovery](../recovery)**_

**Note:** _What it puts on a disk and why: **[➜ Reference](../docs/REFERENCE.md)**. What a declaration may contain, and the contract every `.sh` follows: **[➜ Runtime](../runtime/README.md)**._

```
make -C .. check                                 # load every module and check every script
make -C .. run MODULE=installer ARGS=--dry-run   # run it without touching this machine
```

## What Is Where

```
module.yaml           what the Installer is and asks, its actions, and its tasks in the order they run
tasks/<id>/task.sh    what a task does, with everything only it needs
tasks/<id>/test.sh    optional: how to tell on the machine that it worked
tasks/<id>/data/      every file the task writes into the new system, named after it, filled by render
data/                 the tables languages and countries are looked up in, and data/check.sh, which checks them
```

**Note:** _Every function `module.yaml` names lives in **[lib.sh](../lib.sh)** beside `product.yaml`. An action the Recovery has too (Wi-Fi, the ways out, sharing the log, the shell) is declared once in **[product.yaml](../product.yaml)**. Every text is translated in **[locales/](../locales)**._

## Stages

Each stage lists its tasks under `stages:` in `module.yaml`. The stages run in order, `needs:` orders the tasks within one.

| Stage | Tasks |
| --- | --- |
| `prepare` | `mirrors`, `recovery-image`, then `partition`, the one task that destroys data, once everything that can fail has run |
| `system` | `pacstrap`, then `config`, `tweaks`, `bootloader`, `recovery` and `user`: the system on disk, configured and bootable |
| `features` | One task per setting that turns something on: `multilib`, `aur`, `bootsplash`, `containers`, `editor`, `firewall`, `housekeeping`, `manager`, `shell`, `ssh`, `vm-guest` |
| `desktop` | `gnome` first, then `backup`, `browser`, `flatpak`, `graphics`, `manager-app`, `recovery-app`, `samba` |
| `finish` | `orphans`, `snapper`, `secure-boot`, and `copy-config` last, so the log holds everything |

**Note:** _The runtime's tests load the module as a run does and fail on a stage, a need or a condition that does not resolve._

## Actions

Work outside the run, each with its own pages. Its entry under `actions:` declares how it behaves, the function it names under `run:` only acts. `module.yaml` names where each runs.

| Where | Actions |
| --- | --- |
| `requires` | `live-image`, `root`, `uefi`, `secure-boot-off`, then `internet`, which opens `wifi` right away where there is a card and waits for a cable otherwise |
| `dashboard` | `wifi`: **Connect to Wi-Fi**, offered where `wifi-card` finds a card and `no-cable` finds no wired internet. An open or known network is joined when chosen. A network with a password opens `wifi-passphrase` |
| `on: leave` | `restart`, `shutdown`: restarts or powers off the machine |
| `on: failure` | `share-log`: uploads the log of a run with a broken script and shows it as a QR code. A run that stopped on purpose offers none. **[➜ When Something Goes Wrong](../docs/CONTRIBUTING.md#when-something-goes-wrong)** |
| `on: success` | `chroot`, `share-config`: a shell in the new system, and its answers uploaded. Both are rows on the page a finished run ends on, which opens on **Continue** |

The online profile under `presets:` names `import-config`, which fetches the answers.

**Note:** _A cable needs no action: it connects automatically and is preferred over Wi-Fi while both are up. The third way out is the runtime's own **Exit**: the Installer closes and the machine keeps running. **[➜ ISO](../iso)**_

## auto and none

Two values the lists in `module.yaml` share. `auto` is resolved in `lib.sh` where a task reads the answer, see `vconsole_keymap` and its neighbors. `none` is an explicit empty answer.

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
| Graphics driver | Every graphics card in sysfs, see **[➜ Packages](../docs/REFERENCE.md#packages)** |
| Automatic login | Disk encryption with one password turns it on, otherwise off |

## Language

One answer, `ARCH_OS_LOCALE_LANG`, sets keyboard, console font and time zone. None of them follows from the locale code (`de_CH` is not `de`), so each is looked up in `data/` and stays changeable. The mirror country follows the time zone, not the language: `en_US` is used on every continent, and the time zone is the one answer that says where the machine is.

| Table | Keyed by | Provides |
| --- | --- | --- |
| `data/languages` | Language, or locale where it differs | Keymap, xkb layout, console font |
| `data/countries` | The locale's territory, or the time zone's in `zone.tab` | Time zone, mirror country |

**Note:** _`data/x11-layouts` and `data/x11-variants` are only a fallback: the official Arch live image ships no xkeyboard-config._

The console keyboard is asked `first` and loaded at once: a password typed on the wrong layout is not the password.

## Sharing a Configuration

`installer.conf` can be uploaded to **[paste.rs](https://paste.rs)** and comes back as a QR code. `share-config`, on the page a finished run ends on, uploads it. `import-config`, behind the online profile, fetches it.

**Note:** _Uploaded without its `ARCH_OS_CONFIG_*` lines. It holds no password, but hostname, username, disk and language: **anyone with the address can read it**. The import leaves out the disk, a path on the machine it was answered on, and the kernel parameters, which nobody should take on from someone else's code._

## Adding Something

| You want to add | How |
| --- | --- |
| An option | A row under `settings:`, its list or suggestion a function in `lib.sh`. Guard the tasks that depend on it with `when:` |
| A task | An entry under its stage in `module.yaml` and a folder `tasks/<id>/` with `task.sh`, and a `test.sh` where there is something to read back |
| A check, a row or a way out | An entry under `actions:` with the function of `lib.sh` it runs, named under `requires:` or `on:`. One the Recovery has too goes into `product.yaml` |
| A profile | An entry under `presets:`. A fetched one names the action that fetches it with `action:` |
| A language | **[➜ Contributing](../docs/CONTRIBUTING.md#adding-a-language)** |
| Something in the Recovery | **[➜ Recovery](../recovery)**, none of it lives here |

## Requirements

A booted **Arch Linux live image**, root on it, UEFI with Secure Boot off, then the internet: `requires:` in `module.yaml`, in that order.

**Note:** _`--dry-run` skips them and simulates the work._

## Answers

`installer.conf`, beside wherever the Installer was started, and copied into the new system at the end. Passwords are never in it and never shown on the dashboard.

The Recovery on its partition gets two answers to start with: the language this run was read in and the console keyboard. See `tasks/recovery`.
