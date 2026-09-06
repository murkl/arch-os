# Arch OS Recovery

Everything this Recovery knows about Arch Linux. It is data — one YAML file and the folders beside it — and it does not run on its own: [Oak](https://github.com/murkl/oak) draws the interface, asks the questions and runs the tasks in order.

**Note:** _Putting Arch Linux on disk is a separate module: **[➜ Arch OS Installer](../installer)**_

```
make -C ../.. check                              # load both modules and lint every script
make -C ../.. run MODULE=recovery ARGS=--debug   # run it without touching this machine
```

## What is where

```
recovery.yaml            what this Recovery is, what it asks, what order it runs in
tasks/<id>/task.yaml     where that step belongs: its stage, its needs, its conditions
tasks/<id>/task.sh       what it does, plus any file it ships with, beside it
hooks/<name>.sh          everything around the work itself
lib.sh                   what more than one script has to agree about
locales/                 one <code>.po per language, and the template they come from
```

**Note:** _The shape and the rules are the Installer's: **[➜ Writing a Task](../installer/README.md#writing-a-task)**. Every key these files may use is in the **[Oak reference](https://github.com/murkl/oak/blob/main/docs/REFERENCE.md)**._

## What it does

Three stages, and after the first one every step is optional. The system is opened first, and what to repair is then a decision made with the disk right in front of you.

| Task | Stage | Description |
| --- | --- | --- |
| `open` | `open` | Unlocks and mounts at `/mnt`, the same way the system mounts itself |
| `rollback` | `repair` | Puts a snapshot in place of the root subvolume, btrfs only |
| `kernel` | `repair` | Rebuilds the kernel images and initramfs from the package cache, and re-signs them where the boot chain is signed |
| `shell` | `repair` | `arch-chroot`s into the repaired system, with the terminal handed over |
| `close` | `close` | Unmounts everything and locks the disk again |

**Note:** _Each of the three under `repair` has its own `confirm:`, so a run can stop after any of them. `needs:` is what puts them in that order — a shell is worth having once the boot files are back, not before._

## Nothing is downloaded

A machine that needs repairing may have a broken network as part of the problem, so this module never asks for one:

- There is no `online.sh` hook, which is what turns the network screen off
- The kernel images come from the repaired system's own pacman cache rather than a mirror

For the same reason `hooks/preflight.sh` checks less than the Installer's does: root and the live image, nothing about this machine's firmware, since this machine is not what is being set up.

## Two Views of one Disk

A btrfs installation is the running system, mounted at `/mnt`, sitting on a top level that holds `@` and the snapshots, mounted separately at `/run/arch-os-recovery`. A rollback happens through the second mount: `@` cannot be replaced while it is mounted as the root, and the top level has to stay available once `/mnt` is gone. It is kept out of the chroot on purpose.

**Note:** _The mount options are written out twice — here in `lib.sh` and in the Installer's `prepare-disk` task. This module puts a file system back exactly the way the Installer laid it out, so the two must not drift apart._

The repair logic itself lives in the tasks, not in `lib.sh`. Unlocking, rolling back and rebuilding are each one task's whole job. What `lib.sh` holds is only what more than one task has to agree about: where the system is mounted, what its partitions are called, and those mount options.

## Answers

`recovery.conf`, beside wherever the Recovery was started. Its own file, never the Installer's, so a repair leaves no trace in a configuration that later gets copied into an installed system.

| Variable | Description |
| --- | --- |
| `ARCH_OS_RECOVERY_KEYMAP` | The console keyboard, asked `first` and loaded immediately. The password below is typed on it |
| `ARCH_OS_RECOVERY_DISK` | The disk holding the installation to repair |
| `ARCH_OS_RECOVERY_ENCRYPTION_ENABLED` | Whether it is LUKS-encrypted. Read directly off the disk, no password needed |
| `ARCH_OS_RECOVERY_PASSWORD` | What unlocks it, asked right before the run starts and never written to a file |
| `ARCH_OS_RECOVERY_FILESYSTEM` | `btrfs` supports rollback, `ext4` is opened and worked on by hand |
| `ARCH_OS_RECOVERY_SNAPSHOT` | Asked mid-run by the rollback task, since nothing can list snapshots before the disk is open |

The two that are read off the disk fill in with the answer they would already have and stay questions anyway: behind LUKS nothing can be read until the password is given, and a disk laid out differently still has to be answerable by hand.

## Requirements

Root and the Arch Linux live image. Nothing else.
