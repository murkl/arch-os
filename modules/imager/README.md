# Create boot medium

Everything this module knows about making a bootable device. It is data — one YAML file and the folders beside it — and it does not run on its own: [Oak](https://github.com/murkl/oak) draws the interface, asks the questions and runs the tasks in order.

**Note:** _The folder is `imager`, which is what `--module=imager` opens and what `imager.conf` and `imager.log` are named after. **Create boot medium** is its `title:`, and what the row a person presses says._

**Note:** _Putting Arch Linux on disk is a separate module: **[➜ Arch OS Installer](../installer)**_

```
make -C ../.. check                            # load every module and lint every script
make -C ../.. run MODULE=imager ARGS=--debug   # run it without touching this machine
```

## What is where

```
module.yaml                     what this module is, what it asks, what order it runs in
module.sh                       what more than one script has to agree about
requires.sh                     what a machine has to be for this module to be offered on it
tasks/@<stage>/<id>/task.yaml   what that step is: its needs, conditions and offers
tasks/@<stage>/<id>/task.sh     what it does
tasks/@<stage>/<id>/test.sh     how to tell, on the machine, that it took
hooks/@<hook>/<id>/hook.yaml    a moment Oak runs itself, rather than as part of the work
locales/                        one <code>.po per language, and the template they come from
```

**Note:** _The shape and the rules are the Installer's: **[➜ Writing a Task](../installer/README.md#writing-a-task)**. Every key these files may use is in the **[Oak reference](https://github.com/murkl/oak/blob/main/docs/REFERENCE.md)**._

## What it does

| Task | Stage | Description |
| --- | --- | --- |
| `image` | `download` | Fetches the image this program belongs to and the checksum published beside it, whichever of the two is missing |
| `checksum` | `verify` | Reads the image back and compares it against that checksum, discarding both files if they disagree |
| `device` | `write` | Checks that the answer still names a USB device big enough, unmounts whatever the desktop mounted and copies the image onto it |

Three steps rather than one, because each of them can fail on its own and says something different when it does: nothing arrived, what arrived is broken, or it could not be written. The middle one is also the only wait in the run with no progress to show — two gigabytes read back — and a step somebody is watching is a step they can be told the reason for.

**Note:** _`checksum` is the one task here with no `test.sh`. What a test would read is the image against the checksum, which is that task line for line, and a second copy of a task is the copy that goes stale._

## The Image is not a Question

Which image gets written is not asked, because it is not a matter of opinion: it is the one this program came out of. `version:` in `oak.yaml` beside the binary is the only place that is written down, and the release it names is where the image is fetched from.

A binary from last month writing this month's image would be two versions on one machine, and only one of those pairs was ever tested together.

**Note:** _The asset is picked out of that release by what its name ends in, so renaming a download stays a change to the **[Makefile](../../Makefile)** that builds it and nothing here._

Where it lands **is** a question: **Download folder**, suggested as the folder the program was started in, where Oak already keeps the answers and the log — so everything one run leaves behind is removed with one folder. Both files are reused, so a second run — a wrong device, a stick pulled out halfway — costs the download only the first time. A pair that fails the checksum is thrown away rather than kept, so the next run fetches it again instead of finding the broken one and skipping the download.

The checksum ships in the same release as the image, so what it catches is a download that went wrong on the way and not a release that was wrong to begin with. Every request the module makes is HTTPS and stays HTTPS after a redirect, so the answer cannot be swapped for somebody else's on the way.

## Where it runs

`requires.sh`, beside `module.yaml`, is what decides whether this row is on the page at all, and it is the division between the three modules: the Installer and the Recovery belong **only** on a booted Arch Linux live image, because that is where there is a machine to work on. This one belongs **only** anywhere else, because this is the machine that makes that image — and because downloading two gigabytes into a live system means downloading them into its memory.

So on an ordinary desktop this is the only module on offer, and Oak opens it on the way in without a list of one row. A run started with `--debug` is offered every module whatever they say, and simulates.

**Note:** _Each module carries that rule itself. Nothing anywhere lists which module belongs on which machine, which is what makes adding a fourth one a folder and nothing else._

An Arch image is a hybrid ISO: it already carries the partition table and both boot paths a firmware looks for, so writing it is one raw copy and nothing else. What is left for `hooks/@preflight/` is what has to be true once this module has been chosen:

| Check | Why |
| --- | --- |
| `escalation` | There is a way to become root for the write — either this already is root, or there is a `sudo` to ask |
| `device` | A machine with nothing plugged in cannot be helped by any answer |
| `image` | Either the image is already here or GitHub can be reached. Not "is there internet": an image already on this machine is written without one |

## Root, and only where it is Needed

This module runs as whoever started it. That is what separates it from the other two: they run on a booted live image, where everything is root already and there is no home to leave anything in, while this one runs on somebody's own machine — and a root process there leaves two gigabytes in their home that only root can delete again, with the program's own answers and log beside them.

So `as_root` lives in the write task, the one step that cannot do without it, and wraps three commands there and nothing else:

| Command | Why |
| --- | --- |
| `umount` | Releasing what the desktop mounted from the device |
| `dd` | Writing a block device |
| `partprobe` | Making the kernel read the new partition table |

Everything else — listing the disks, reading their size, both downloads, checking the checksum and reading the label back afterwards — is done as the person at the machine. The test uses `lsblk` rather than `blkid` for exactly that reason: it reads what udev already recorded, so nothing has to ask for a password where nobody is typing.

The write task is the one step with `tty: true`. `sudo` draws its prompt on the terminal and reads the password from it, and `dd` reports its progress on stderr, which Oak otherwise collects into the log — so the interface steps aside for the length of it and the script takes `/dev/tty` explicitly.

**Note:** _Whether this particular person may use `sudo` is not part of `@preflight/`: asking means asking for their password, and that stage runs before anybody has said they want to write anything. `sudo` answers it itself, on the terminal, at the moment it is needed._

## Answers

`imager.conf`, beside wherever the program was started.

| Variable | Description |
| --- | --- |
| `ARCH_OS_DOWNLOAD_DIR` | Where the image and its checksum are kept, created if it is not there. Defaults to the folder the program was started in |
| `ARCH_OS_IMAGE_DEVICE` | The USB device to write to. Only disks on a USB bus are offered, so the disk this machine boots from cannot be chosen by accident |

The device is read back out of `lsblk` again by the task that writes, immediately before it does: `/dev/sdb` is a path and not a stick, and an answer kept from an earlier run can name a disk that is no longer the one it was chosen as.

## Requirements

A Linux machine that is not the live image, a USB device big enough for the image, and either the image already in the download folder or a network to fetch it over. Root only for the write itself, asked for when that step comes.

Everything it calls comes from `coreutils`, `util-linux` and `curl`, which any Linux machine already has.
