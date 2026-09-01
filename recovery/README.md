# Arch OS Recovery

Everything this recovery knows about Arch Linux. It is data — one YAML file and
the folders beside it — and it does not run on its own: the
[runtime](../runtime) draws the interface, asks the questions and runs the tasks
in order. Putting Arch Linux on a disk is a tree of its own, and a program of
its own: [`installer/`](../installer).

```sh
make check   # load the tree and lint every script

# Run it, without touching this machine
DEBUG=true make -C ../runtime run TREE=../recovery
```

## What is where

```
recovery.yaml            what this recovery is, what it asks, what order it works in
tasks/<id>/task.yaml     where that unit belongs: its stage, its needs, its conditions
tasks/<id>/task.sh       what it does
hooks/<name>.sh          everything around the work itself
lib.sh                   what every script of this tree shares
locales/                 one <code>.yaml per language this recovery speaks
```

Nothing points at any of this from `recovery.yaml`: each part is found by its own
name. The runtime takes the one YAML file it finds in a folder, which is what
lets this tree and the installer's sit side by side and stay two programs. A
release holds both, and one binary: `./installer -dir recovery` is this one, and
on the ISO that is the `recovery` command.

## What it does

`recovery.yaml` declares exactly one `mode:` — `Recovery`, with the last warning
and the stages under it. There is nothing to choose, so nobody is asked; it is
there for the name. Without it the runtime falls back to the only thing an
unnamed run can be and calls a repair an installation.

Three stages, and after the first one every step is offered rather than done.
The system is opened, and what to repair is then a decision with the disk in
front of you.

| stage | what it is |
|---|---|
| `open` | the installation unlocked where it is encrypted, and mounted at `/mnt` |
| `repair` | rolled back, made bootable again, worked in by hand |
| `close` | unmounted, and the disk locked again |

| task | stage | |
|---|---|---|
| `open` | `open` | unlock and mount, the way the system mounts itself |
| `rollback` | `repair` | put a snapshot in place of the root subvolume — btrfs only |
| `kernel` | `repair` | rebuild the kernel images and ram disks from the package cache |
| `shell` | `repair` | `arch-chroot` into the repaired system, with the terminal handed over |
| `close` | `close` | unmount everything and lock the disk |

Each of the three under `repair` has a `confirm:` of its own, so a run can stop
after any of them. `needs:` is what puts them in that order: a shell is worth
having after the boot files are back, not before.

`make check` prints the order the whole tree adds up to.

## Nothing is downloaded

A machine that needs repairing is one whose network may be part of what broke,
so this tree never asks for one: there is no `online.sh` hook, which is what
turns the network screen off, and the kernel images come out of the repaired
system's own pacman cache rather than off a mirror.

For the same reason `hooks/preflight.sh` asks less than the installer's: root
and the live image, and nothing about this machine's firmware — it is not what
is being set up.

## Two views of one disk

A btrfs installation is the system as it runs, mounted at `/mnt`, and the top
level holding `@` and the snapshots, mounted at `/run/arch-os-recovery`. A
rollback happens in the second: `@` cannot be replaced while it is the root that
is mounted, and the top level has to survive `/mnt` going away. It is kept out
of the chroot on purpose.

The mount options are the installer's, written out in both `lib.sh` files. The
recovery puts a file system back the way the installation laid it out, so the
two lines must not drift apart.

## Writing a task

Same as in the installer, and the rules are written down there:
[`installer/README.md`](../installer/README.md#writing-one). A unit is a folder
with `task.yaml` and `task.sh` in it, the script is sourced into a shell that
already carries `lib.sh` and an `ERR` trap, and `simulating && return 0` is what
makes `DEBUG=true` a simulation rather than a repair.

## Answers

`recovery.conf`, beside wherever the recovery was started — its own file, never
the installer's, so a repair leaves no trace in a configuration that gets copied
into an installed system. Every answer is `ARCH_OS_RECOVERY_*`; the encryption
password is not among them, because the runtime never writes a secret down.

| | |
|---|---|
| `ARCH_OS_RECOVERY_KEYMAP` | the console keyboard, asked `first` and loaded at once — the password below is typed on it |
| `ARCH_OS_RECOVERY_DISK` | the disk holding the installation to repair |
| `ARCH_OS_RECOVERY_ENCRYPTION_ENABLED` | whether it is LUKS; read off the disk, which needs no password |
| `ARCH_OS_RECOVERY_PASSWORD` | what unlocks it, asked immediately before the run |
| `ARCH_OS_RECOVERY_FILESYSTEM` | `btrfs` rolls back, `ext4` opens and is worked in by hand |
| `ARCH_OS_RECOVERY_SNAPSHOT` | asked mid-run by the rollback: nothing can list them before the disk is open |

The two that are read off the disk fill in the answer their question opens on
and are still questions: behind LUKS nothing can be read until the password has
been given, and a disk laid out some other way has to stay answerable by hand.

## A language

```sh
make strings > locales/fr.yaml   # every word this tree says, empty
make check                       # reports coverage per language
```

The runtime's own words are translated separately, in its own `locales/`.

## Requirements

Root and the Arch Linux live image. Nothing else.
