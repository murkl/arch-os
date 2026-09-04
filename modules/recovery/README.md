# Arch OS Recovery

Everything this Recovery knows about Arch Linux. It is data, one YAML file and the folders beside it, and it does not run on its own: [Oak](https://github.com/murkl/oak) draws the interface, asks the questions and runs the tasks in order.

**Note:** _Putting Arch Linux on disk is a separate module: **[➜ Arch OS Installer](../installer)**_

```
make check                                             # load the module and lint every script
make -C ../.. run MODULE=recovery ARGS=--debug        # run it without touching this machine
```

## What is where

```
recovery.yaml            what this Recovery is, what it asks, what order it runs in
tasks/<id>/task.yaml     where that step belongs: its stage, its dependencies, its conditions
tasks/<id>/task.sh       what it does, plus any file it ships with, beside it
hooks/<name>.sh          everything around the work itself
lib.sh                   the small shared library every script in this module uses
locales/                 one <code>.po per language, and the template they are filled in from
```

**Note:** _Nothing in `recovery.yaml` points at any of this. Each part is found by its own name._

Both modules are folders under `modules/`, which is the whole of what a release offers, and the interface asks which one to open. `./oak --recovery` opens this one directly, and on the ISO that is the `recovery` command.

## What it does

`recovery.yaml` sets `run: Recovery`, which is the name the interface reads out wherever it reports what is happening. Without it Oak would default to "Installation" and describe a repair as one.

Three stages, and after the first one every step is optional. The system is opened first and what to repair is then a decision made with the disk right in front of you.

| Stage | Description |
| --- | --- |
| `open` | The installation unlocked (where encrypted) and mounted at `/mnt` |
| `repair` | Rolled back, made bootable again, worked on by hand |
| `close` | Unmounted, and the disk locked again |

| Task | Stage | Description |
| --- | --- | --- |
| `open` | `open` | Unlocks and mounts, the same way the system mounts itself |
| `rollback` | `repair` | Puts a snapshot in place of the root subvolume, btrfs only |
| `kernel` | `repair` | Rebuilds the kernel images and initramfs from the package cache, and re-signs them if the boot chain is signed |
| `shell` | `repair` | `arch-chroot`s into the repaired system, with the terminal handed over |
| `close` | `close` | Unmounts everything and locks the disk |

**Note:** _Each of the three tasks under `repair` has its own `confirm:`, so a run can stop after any of them. `needs:` is what puts them in that order: a shell is worth having once the boot files are back, not before. `make check` prints the order the whole module resolves to._

## Nothing is downloaded

A machine that needs repairing might have a broken network as part of the problem, so this module never asks for one:

- There is no `online.sh` hook, which is what turns the network screen off
- The kernel images come from the repaired system's own pacman cache rather than a mirror

For the same reason `hooks/preflight.sh` checks less than the Installer's does: just root and the live image, nothing about this machine's firmware, since this machine is not what is being set up.

## Two Views of one Disk

A btrfs installation is the running system, mounted at `/mnt`, sitting on a top level that holds `@` and the snapshots, mounted separately at `/run/arch-os-recovery`. A rollback happens through the second mount: `@` cannot be replaced while it is mounted as the root, and the top level has to stay available once `/mnt` is gone. It is kept out of the chroot on purpose.

**Note:** _The mount options match the Installer's, written out here in `lib.sh` and in the Installer's `prepare-disk` task. This module puts a file system back exactly the way the Installer laid it out, so the two must not drift apart._

## Writing a Task

The same as in the Installer and the rules are written down there: **[➜ Writing a Task](../installer/README.md#writing-a-task)**

A task is a folder with `task.yaml` and `task.sh` in it, the script is sourced into a shell that already has `lib.sh` loaded and an `ERR` trap set, and `simulating && return 0` is what turns `--debug` into a simulation instead of a real repair.

The repair logic itself lives in those scripts, not in `lib.sh`. Unlocking, rolling back and rebuilding are each one task's whole job, so that is where they are written. What `lib.sh` holds is only what more than one task needs to agree on: where the system is mounted, what its partitions are called, and the mount options a rollback has to restore exactly as it found them.

**Note:** _A task that ships a file of its own keeps it right beside itself. `tasks/rollback/snapshots.sh` is the list of snapshots, named in `recovery.yaml` as the answers to that question._

## Answers

`recovery.conf`, beside wherever the Recovery was started. Its own file, never the Installer's, so a repair leaves no trace in a configuration that later gets copied into an installed system.

| Variable | Description |
| --- | --- |
| `ARCH_OS_RECOVERY_KEYMAP` | The console keyboard, asked `first` and loaded immediately. The password below is typed on it |
| `ARCH_OS_RECOVERY_DISK` | The disk holding the installation to repair |
| `ARCH_OS_RECOVERY_ENCRYPTION_ENABLED` | Whether it is LUKS-encrypted. Read directly off the disk, no password needed |
| `ARCH_OS_RECOVERY_PASSWORD` | What unlocks it, asked right before the run starts |
| `ARCH_OS_RECOVERY_FILESYSTEM` | `btrfs` supports rollback, `ext4` is opened and worked on by hand |
| `ARCH_OS_RECOVERY_SNAPSHOT` | Asked mid-run by the rollback task, since nothing can list snapshots before the disk is open |

**Note:** _The encryption password is not written to `recovery.conf`, since Oak never writes a secret to disk._

The two that are read off the disk fill in with the answer they would already have and stay questions anyway: behind LUKS nothing can be read until the password is given, and a disk laid out differently still needs to stay answerable by hand.

## Adding a Language

```
cp locales/recovery.pot locales/fr.po   # every string this module uses, none translated yet
make check                              # reports coverage per language
```

Fill in the `msgstr` lines and nothing else. `make locales` regenerates `recovery.pot` from the module and updates every catalog against it.

**[➜ See Translating](../../docs/TRANSLATING.md)**

## The Command Line

Nothing on it belongs to this module. On the ISO, `recovery` is `arch-os --recovery`: Oak with this module already named. `--debug` beside it is Oak's own switch, the same word in every module, passed to every script here as `DEBUG`.

**Note:** _Every answer, including the disk password, is given inside the interface._

## Requirements

Root and the Arch Linux live image. Nothing else.
