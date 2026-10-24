# Arch OS Installer

Installs Arch OS. The module is data: one YAML file and a folder per task. The **[runtime](../runtime)** draws the pages, asks the questions and runs the tasks.

**Note:** _Repair: **[➜ Recovery](../recovery)**. What lands on the disk and why: **[➜ Reference](../docs/REFERENCE.md)**. Declaration format and script contract: **[➜ Runtime](../runtime/README.md)**_

```
make -C .. check                                 # load every module, check every script
make -C .. run MODULE=installer ARGS=--dry-run   # run without touching this machine
```

## Layout

```
module.yaml           settings, actions and tasks in run order
tasks/<id>/task.sh    a task's work, with everything only it needs
tasks/<id>/test.sh    optional, checks the result on the machine
tasks/<id>/data/      files the task writes into the new system, named after the target, filled by render
data/                 language and country tables, checked by data/check.sh
```

**Note:** _Functions named in `module.yaml` live in **[lib.sh](../lib.sh)**. Actions shared with the Recovery (Wi-Fi, ways out, log sharing, shell) live in **[product.yaml](../product.yaml)**. Translations live in **[locales/](../locales)**._

## Stages

Stages run in order, `needs:` orders the tasks within one.

| Stage | Tasks |
| --- | --- |
| `prepare` | `mirrors`, then `partition`, the one task that destroys data, after everything that can fail |
| `system` | `pacstrap`, then `config`, `network`, `tweaks`, `bootloader`, `recovery` and `user`: a configured, bootable system |
| `features` | One task per setting: `multilib`, `aur`, `bootsplash`, `containers`, `editor`, `firewall`, `housekeeping`, `manager`, `shell`, `ssh`, `vm-guest` |
| `desktop` | `gnome` first, then `backup`, `browser`, `flatpak`, `graphics`, `manager-app`, `recovery-app`, `samba` |
| `finish` | `orphans`, `snapper`, `secure-boot`, and `copy-config` last, so the log is complete |

## Actions

| Where | Actions |
| --- | --- |
| `requires` | `live-image`, `root`, `uefi`, `secure-boot-off`, then `internet`, which opens `wifi` at once where there is a card and waits for a cable otherwise. `--dry-run` skips them |
| `dashboard` | `wifi`: **Connect to Wi-Fi**, where `wifi-card` finds a card and `no-cable` no wired internet. An open or known network connects at once, one with a password opens `wifi-passphrase` |
| `on: leave` | `restart`, `shutdown` |
| `on: failure` | `share-log`: uploads the log of a broken script as a QR code. **[➜ Errors](../docs/CONTRIBUTING.md#errors)** |
| `on: success` | `chroot`, `share-config`: a shell in the new system, and the answers uploaded |

The **Shared configuration** profile under `presets:` runs `import-config`. **[➜ Answers](../docs/REFERENCE.md#answers)**

**Note:** _A cable connects automatically and wins over Wi-Fi. **Exit** closes the Installer and leaves the machine running. **[➜ ISO](../iso)**_

## auto and none

`auto` resolves in `lib.sh` where a task reads the answer, see `vconsole_keymap`. `none` is an explicit empty answer.

| On `auto` | Resolves to |
| --- | --- |
| `ARCH_OS_VCONSOLE_KEYMAP` | Keyboard of the chosen language, then of the live system, then `us` |
| `ARCH_OS_DESKTOP_KEYBOARD_LAYOUT` | The same, in xkb naming |
| `ARCH_OS_VCONSOLE_FONT` | A font for the script of the chosen language |

## Detected

| What | Source |
| --- | --- |
| `ARCH_OS_VIRTUAL_MACHINE` | `systemd-detect-virt`, for the guest tools |
| Microcode | `/proc/cpuinfo` |
| Graphics driver | Every graphics card in sysfs. **[➜ Packages](../docs/REFERENCE.md#packages)** |
| Automatic login | On with disk encryption and one password |

## Language

`ARCH_OS_LOCALE_LANG` presets keyboard, console font and time zone, each changeable. None follows from the locale code (`de_CH` is not `de`), so `data/` maps them. Mirrors stay worldwide unless a country is chosen.

| Table | Key | Provides |
| --- | --- | --- |
| `data/languages` | Language, or locale where it differs | Keymap, xkb layout, console font |
| `data/countries` | Territory of the locale | Time zone, reflector's country name |

The console keyboard is asked `first` and loaded at once: a password typed on the wrong layout is not the password.

## Extending

| Addition | How |
| --- | --- |
| Option | A row under `settings:`, list or suggestion as a function in `lib.sh`. Dependent tasks get `when:` |
| Task | An entry under its stage in `module.yaml` and `tasks/<id>/task.sh`, plus `test.sh` where a result can be read back |
| Check, row or way out | An entry under `actions:` with its `lib.sh` function, named under `requires:` or `on:`. Shared with the Recovery: `product.yaml` |
| Profile | An entry under `presets:`. A fetched one names its action with `action:` |
| Language | **[➜ Contributing](../docs/CONTRIBUTING.md#adding-a-language)** |

## Answers

`installer.conf` beside the started Installer, copied into the new system at the end. Never holds a password.

The Recovery on its partition gets two answers from the start: the interface language and the console keyboard. See `tasks/recovery`.
