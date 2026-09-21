# Create boot medium

Everything this module knows about making a bootable device. It is data - one YAML file and the folders beside it - and it does not run on its own: [Oak](https://github.com/murkl/oak) draws the interface, asks the questions and runs the tasks in order.

**Note:** _The folder is `imager`, named after **Create boot medium**, its `title:`._

**Note:** _Putting Arch Linux on disk and repairing one already there are separate modules: **[➜ Installer](../installer)** · **[➜ Recovery](../recovery)**_

**Note:** _What it writes and why: **[➜ Arch OS Reference](../../docs/REFERENCE.md#the-boot-medium)**. The task contract: **[➜ AGENTS.md](../../AGENTS.md)**._

```
make -C ../.. check                            # load every module and lint every script
make -C ../.. run MODULE=imager ARGS=--debug   # run it without touching this machine
```

## What is where

```
module.yaml                     what this module is, what it asks, what order it runs in
module.sh                       what more than one script has to agree about
tasks/@<stage>/<id>/task.yaml   what that step is: its needs, conditions and offers
tasks/@<stage>/<id>/task.sh     what it does
tasks/@<stage>/<id>/test.sh     how to tell, on the machine, that it took
hooks/@<hook>/<id>/hook.yaml    a moment Oak runs itself, rather than as part of the work
locales/                        one <code>.po per language, and the template they come from
```

## What it does

| Task | Stage | Description |
| --- | --- | --- |
| `image` | `download` | Fetches the image, unless the folder already holds it |
| `checksum` | `verify` | Compares it against the checksum the release publishes, discards it if they disagree. Where there is none to compare against, it asks |
| `device` | `write` | Checks the device, unmounts it, copies the image on |

Three steps, three distinct failures: nothing arrived, what arrived is broken, or it could not be written.

**Note:** _`checksum` has no `test.sh` - the task itself already is the test, line for line._

## The Image is not a Question

Which image gets written is not asked: it is the one this program came from. `version:` in `oak.yaml` says which, and where it fetches from.

**Note:** _The asset is picked by what its name ends in, so renaming a download only touches the **[Makefile](../../Makefile)**._

### Where it lands

**Download folder**, suggested as `XDG_DOWNLOAD_DIR` or `~/Downloads`. The image is kept, so a second run costs no bandwidth.

An `arch-os-<version>-x86_64.iso` already in that folder is not downloaded again. The number it is then held to is the checksum GitHub publishes for that release, so this module and the release page check the same one - and the release carries no checksum file of its own.

- A checksum mismatch discards the image rather than keeping a broken one
- Where no checksum can be fetched - the release is not out yet, or it cannot be reached - the run stops and asks, and only a yes writes the image. That is how an image built here rather than downloaded reaches a device
- Every request is HTTPS, redirects included

## Where it runs

`requires:` splits the three modules: Installer and Recovery need a booted live image to work on; this one needs anywhere else - it is the machine that *makes* that image. So it is the only module offered on an ordinary desktop.

`hooks/@preflight/`:

| Check | Why |
| --- | --- |
| `escalation` | A way to become root for the write - already root, or `sudo` exists |
| `device` | Nothing plugged in, no answer can help |

**Note:** _Whether the image can be fetched is not checked here - it depends on the download folder, which is not yet answered when `@preflight` runs. The download task says so instead._

## Root, and only where it is Needed

This module runs as you, not root - unlike the other two, which run on an already-root live image. `as_root` lives only in the write task and wraps three commands:

| Command | Why |
| --- | --- |
| `umount` | Releasing what the desktop mounted |
| `dd` | Writing the block device |
| `partprobe` | Re-reading the partition table |

Everything else - listing, downloading, checksumming - runs as you. `tty: true` on the write task hands `sudo` and `dd` the real terminal.

## Answers

`imager.conf`, beside wherever the program was started.

| Variable | Description |
| --- | --- |
| `ARCH_OS_DOWNLOAD_DIR` | Where the image lives. Suggested as `XDG_DOWNLOAD_DIR`, or `~/Downloads` |
| `ARCH_OS_IMAGE_DEVICE` | The USB device to write. Only USB disks are offered |
| `ARCH_OS_IMAGE_UNVERIFIED` | Whether to write an image no checksum could be fetched for. Asked mid-run, and only then |

**Note:** _The device is read back from `lsblk` immediately before writing - `/dev/sdb` is a path, not a stick._

## Requirements

A Linux machine that is not the live image, a big enough USB device, and either the image already downloaded or a network. Root only for the write. Needs `coreutils`, `util-linux`, `curl` - any Linux machine already has them.
