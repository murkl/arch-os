# Arch OS Recovery

Everything this recovery module knows about Arch Linux. It's data — one YAML
file and the folders beside it — and it doesn't run on its own: the
[runtime](../../runtime) draws the interface, asks the questions, and runs
the tasks in order. Putting Arch Linux on disk is a separate module:
[`installer/`](../installer).

```sh
make check   # load the module and lint every script

# Run it without touching this machine
make -C ../../runtime run MODULE=recovery ARGS=--debug
```

## What is where

```
recovery.yaml            what this recovery is, what it asks, what order it runs in
tasks/<id>/task.yaml     where that step belongs: its stage, its dependencies, its conditions
tasks/<id>/task.sh       what it does, plus any file it ships with, beside it
hooks/<name>.sh          everything around the work itself
lib.sh                   the small shared library every script in this module uses
locales/                 one <code>.po per language this recovery speaks, and the template they're filled in from
```

Nothing in `recovery.yaml` points at any of this — each part is found by its
own name. The runtime picks up whichever single YAML file it finds in a
folder, which is what lets this module and the installer sit side by side as
two independent programs. Both are folders under `modules/`, which is the
whole of what a release offers; the interface asks which one to open.
`./runtime --recovery` opens this one directly, and on the ISO that's the
`recovery` command.

## What it does

`recovery.yaml` sets `run: Recovery`, which is the name the interface reads
out wherever it reports what's happening. Without it, the runtime would
default to "Installation" and describe a repair as one. `description:` next
to it is the sentence shown under this module's row on the page that asks
which module to open.

Three stages, and after the first one, every step is optional. The system
is opened first, and what to repair is then a decision made with the disk
right in front of you.

| stage | what it is |
|---|---|
| `open` | the installation unlocked (where encrypted) and mounted at `/mnt` |
| `repair` | rolled back, made bootable again, worked on by hand |
| `close` | unmounted, and the disk locked again |

| task | stage | |
|---|---|---|
| `open` | `open` | unlocks and mounts, the same way the system mounts itself |
| `rollback` | `repair` | puts a snapshot in place of the root subvolume, btrfs only |
| `kernel` | `repair` | rebuilds the kernel images and initramfs from the package cache, and re-signs them if the boot chain is signed |
| `shell` | `repair` | `arch-chroot`s into the repaired system, with the terminal handed over |
| `close` | `close` | unmounts everything and locks the disk |

Each of the three tasks under `repair` has its own `confirm:`, so a run can
stop after any of them. `needs:` is what puts them in that order — a shell
is worth having once the boot files are back, not before.

`make check` prints the order the whole module resolves to.

## Nothing is downloaded

A machine that needs repairing might have a broken network as part of the
problem, so this module never asks for one: there's no `online.sh` hook,
which is what turns the network screen off, and the kernel images come from
the repaired system's own pacman cache rather than a mirror.

For the same reason, `hooks/preflight.sh` checks less than the installer's
does: just root and the live image, nothing about this machine's firmware,
since this machine isn't what's being set up.

## Two views of one disk

A btrfs installation is the running system, mounted at `/mnt`, sitting on a
top level that holds `@` and the snapshots, mounted separately at
`/run/arch-os-recovery`. A rollback happens through the second mount: `@`
can't be replaced while it's mounted as the root, and the top level has to
stay available once `/mnt` is gone. It's kept out of the chroot on purpose.

The mount options match the installer's, written out here in `lib.sh` and in
the installer's `prepare-disk` task. The recovery module puts a file system
back exactly the way the installer laid it out, so the two must not drift
apart.

## Writing a task

The same as in the installer, and the rules are written down there:
[`installer/README.md`](../installer/README.md#writing-one). A task is a
folder with `task.yaml` and `task.sh` in it, the script is sourced into a
shell that already has `lib.sh` loaded and an `ERR` trap set, and
`simulating && return 0` is what turns `--debug` into a simulation instead
of a real repair.

The repair logic itself lives in those scripts, not in `lib.sh`: unlocking,
rolling back and rebuilding are each one task's whole job, so that's where
they're written. What `lib.sh` holds is only what more than one task needs
to agree on: where the system is mounted, what its partitions are called,
and the mount options a rollback has to restore exactly as it found them. A
task that ships a file of its own keeps it right beside itself —
`tasks/rollback/snapshots.sh` is the list of snapshots, named in
`recovery.yaml` as the answers to that question.

## Answers

`recovery.conf`, beside wherever the recovery was started — its own file,
never the installer's, so a repair leaves no trace in a configuration that
later gets copied into an installed system. Every answer is prefixed
`ARCH_OS_RECOVERY_*`; the encryption password isn't among them, since the
runtime never writes a secret to disk.

| | |
|---|---|
| `ARCH_OS_RECOVERY_KEYMAP` | the console keyboard, asked `first` and loaded immediately — the password below is typed on it |
| `ARCH_OS_RECOVERY_DISK` | the disk holding the installation to repair |
| `ARCH_OS_RECOVERY_ENCRYPTION_ENABLED` | whether it's LUKS-encrypted; read directly off the disk, no password needed |
| `ARCH_OS_RECOVERY_PASSWORD` | what unlocks it, asked right before the run starts |
| `ARCH_OS_RECOVERY_FILESYSTEM` | `btrfs` supports rollback; `ext4` is opened and worked on by hand |
| `ARCH_OS_RECOVERY_SNAPSHOT` | asked mid-run by the rollback task, since nothing can list snapshots before the disk is open |

The two that are read off the disk fill in with the answer they'd already
have and stay questions anyway: behind LUKS, nothing can be read until the
password is given, and a disk laid out differently still needs to stay
answerable by hand.

## A language

```sh
cp locales/recovery.pot locales/fr.po   # every string this module uses, none translated yet
make check                              # reports coverage per language
```

Fill in the `msgstr` lines and nothing else. `make locales` regenerates
`recovery.pot` from the module and updates every catalog against it — run
this whenever a question is added or reworded. The runtime's own strings are
translated separately, in its own `locales/`. See
[TRANSLATING.md](../TRANSLATING.md).

## The command line

Nothing on it belongs to this module. `arch-os --recovery` opens it, and
`--debug` beside it is the runtime's own switch — the same word in every
module, passed to every script here as `DEBUG`. Every answer, including the
disk password, is given inside the interface.

## Requirements

Root and the Arch Linux live image. Nothing else.
