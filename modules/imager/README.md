# Create Boot Medium

Writes the Arch OS ISO to a USB device. The module is data: one YAML file and the folders beside it. [Oak](https://github.com/murkl/oak) draws the interface, asks the questions and runs the tasks in order.

**Note:** _The folder is `imager`, the module's title is **Create boot medium**._

**Note:** _Installing Arch Linux and repairing an installation are separate modules: **[➜ Installer](../installer)** · **[➜ Recovery](../recovery)**_

**Note:** _What it writes and why: **[➜ Arch OS Reference](../../docs/REFERENCE.md#the-boot-medium)**. The task contract: **[➜ Oak Reference](https://github.com/murkl/oak/blob/main/docs/REFERENCE.md#what-a-script-receives)**._

```
make -C ../.. check                            # load every module and lint every script
make -C ../.. run MODULE=imager ARGS=--debug   # run it without touching this machine
```

## What Is Where

```
module.yaml                       what the module is, what it asks, the order it works in, its rules
tasks/@<stage>/<id>/task.yaml     a step: its conditions and pages
tasks/@<stage>/<id>/task.sh       what the step does
actions/<id>/action.yaml          an action: its pages, and what a no means
actions/<id>/action.sh            what the action does, and nothing else
locales/                          one <code>.po per language, and the template they come from
```

**Note:** _Shared code and every function the YAML calls live in **[oak.sh](../../oak.sh)** beside `oak.yaml`._

## Stages

| Stage | Task | Description |
| --- | --- | --- |
| `download` | `image` | Downloads the image unless the folder already has it, and puts the checksum its release publishes beside it. Shows curl's progress under the step (`progress: true`) |
| `verify` | `checksum` | Checks the image against that checksum and deletes it if they differ. Only with **Verify checksum** on |
| `write` | `device` | Checks the device, unmounts it and copies the image onto it |

What can be expected is said in plain words, under `errors:` beside each task: no internet, a folder that cannot be written, a damaged image, a stick that is gone, too small or still in use. Only a script that breaks shows where, with **Share the log**.

**Note:** _No task has a `test.sh`, so **Verify steps** is not offered here. The checksum is the download's test, and booting from the device is the write's._

## The Image

It writes the ISO of the release that `version:` in `oak.yaml` names, downloaded from its release page.

**Note:** _The download is picked by the end of its name, so renaming it touches only the **[Makefile](../../Makefile)**._

### Where It Lands

In the **Download folder**, `~/Downloads` unless **Setup** names another. It is not asked: the only question is the device. The image stays there, so a second run downloads nothing.

An `arch-os-<version>-x86_64.iso` already in that folder is not downloaded again. It is checked against the checksum GitHub publishes for that release, so this module and the release page check the same number, and the release needs no checksum file. The checksum is read once per run and saved beside the image as `arch-os-<version>-x86_64.iso.sha256`, which `sha256sum -c` reads too.

- A checksum mismatch deletes the image instead of keeping a broken one
- If no checksum can be fetched, because the release is not out yet or cannot be reached, nothing is written, and the page names the setting that lets it through
- **Verify checksum** off writes the image in the folder as it is, without asking the release anything. That is how an image you built yourself gets onto a stick. It is on by default, and a setting instead of a question in the middle of the run, so it reads in the interface's language
- Every request is HTTPS, redirects included

## Where It Runs

`rules: offer-if` keeps the three modules apart. Installer and Recovery need a booted live image to work on. This one needs anything else (`actions/installed-system`), since it makes that image. So it is the only module offered on an ordinary desktop.

What the work needs before it starts, under `rules: start-if`:

| Action | Why |
| --- | --- |
| `sudo` | A way to become root for the write: already root, or `sudo` exists |
| `usb` | Without a stick no answer helps. Plugging one in continues by itself |

Each answers only yes or no, and its `error:` says what a no means, in the interface's language. `share-log`, under `rules: on-failure`, is the same as the Installer's and the Recovery's.

**Note:** _Whether the image can be fetched is not checked here. It depends on the download folder, which is not answered yet when these run. The download task says so instead._

## Root Only Where Needed

This module runs as you, not as root, unlike the other two on a live image that is root already. `as_root` in `oak.sh` is called only by the write task, for three commands:

| Command | Why |
| --- | --- |
| `umount` | Releases what the desktop mounted |
| `dd` | Writes the block device |
| `blockdev` | Rereads the partition table |

Everything else (listing, downloading, checking) runs as you.

The interface keeps the screen the whole time. Whether `sudo` wants a password is read from the machine (`ARCH_OS_IMAGE_SUDO`, from `sudo -nk true`). Where it does, **Your password** is asked right before the run like any password that already exists: once, never written down, and tried with `sudo` on the page where you type it. A wrong one is refused there, not after the download. `as_root` hands it to `sudo -S` on stdin. The step shows `dd`'s last line (`progress: true`).

## Answers

`imager.conf`, beside wherever the program was started.

| Variable | Description |
| --- | --- |
| `ARCH_OS_DOWNLOAD_DIR` | Where the image lives. `~/Downloads` unless changed in **Setup**. `~/` stands for your home |
| `ARCH_OS_IMAGE_DEVICE` | The USB device to write. Asked each time you choose **Start**, before the password, and never written to the file. Only USB disks are offered, and none the running system has mounted outside `/run/media`, `/media` or `/mnt` |
| `ARCH_OS_IMAGE_VERIFY` | Whether the image is checked against the checksum its release publishes before it is written. On unless turned off |
| `ARCH_OS_IMAGE_SUDO` | Read, not asked: whether writing the device needs a password. Not as root, and not where a sudo rule says so |
| `ARCH_OS_IMAGE_PASSWORD` | Your password for `sudo`, only where it wants one. Asked right before the run and never written to the file |

**Note:** _The device is checked against `lsblk` right before the write: `/dev/sdb` is a path, not a stick._

## Requirements

A Linux machine that is not the live image, a USB device large enough, and either the image already downloaded or a network. Root only for the write. It needs `coreutils`, `util-linux` and `curl`, which every Linux machine has.
