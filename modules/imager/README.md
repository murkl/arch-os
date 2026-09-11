# Arch OS Imager

Everything this Imager knows about making a bootable device. It is data — one YAML file and the folders beside it — and it does not run on its own: [Oak](https://github.com/murkl/oak) draws the interface, asks the questions and runs the tasks in order.

**Note:** _Putting Arch Linux on disk is a separate module: **[➜ Arch OS Installer](../installer)**_

```
make -C ../.. check                            # load every module and lint every script
make -C ../.. run MODULE=imager ARGS=--debug   # run it without touching this machine
```

## What is where

```
module.yaml                     what this Imager is, what it asks, what order it runs in
module.sh                       what more than one script has to agree about
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
| `image` | `fetch` | Downloads the image this program belongs to and checks it against the checksum published beside it |
| `device` | `write` | Unmounts whatever the desktop mounted, copies the image onto the device and waits for the drive to take it |

## The Image is not a Question

Which image gets written is not asked, because it is not a matter of opinion: it is the one this program came out of. `version:` in `oak.yaml` beside the binary is the only place that is written down, and the release it names is where the image is fetched from.

A binary from last month writing this month's image would be two versions on one machine, and only one of those pairs was ever tested together.

**Note:** _The asset is picked out of that release by what its name ends in, so renaming a download stays a change to the **[Makefile](../../Makefile)** that builds it and nothing here._

It is downloaded beside the program, where Oak keeps the answers and the log, so a second run — a wrong device, a stick pulled out halfway — costs the download only the first time. A file that fails its checksum is thrown away rather than kept, so the next run fetches it again instead of finding the broken one and skipping the download.

## Where it runs

`offered:` in `module.yaml` is what decides whether this row is on the page at all, and it is the division between the three modules: the Installer and the Recovery belong **only** on a booted Arch Linux live image, because that is where there is a machine to work on. This one belongs **only** anywhere else, because this is the machine that makes that image — and because downloading two gigabytes into a live system means downloading them into its memory.

So on an ordinary desktop this is the only module on offer, and Oak opens it on the way in without a list of one row. A run started with `--debug` is offered every module whatever they say, and simulates.

**Note:** _Each module carries that rule itself. Nothing anywhere lists which module belongs on which machine, which is what makes adding a fourth one a folder and nothing else._

An Arch image is a hybrid ISO: it already carries the partition table and both boot paths a firmware looks for, so writing it is one raw copy and nothing else. What is left for `hooks/@preflight/` is what has to be true once this module has been chosen:

| Check | Why |
| --- | --- |
| `root` | Writing a block device needs it, and nothing here can ask for it later |
| `device` | A machine with nothing plugged in cannot be helped by any answer |
| `image` | Either the image is already here or GitHub can be reached. Not "is there internet": an image already on this machine is written without one |

## Answers

`imager.conf`, beside wherever the Imager was started.

| Variable | Description |
| --- | --- |
| `ARCH_OS_IMAGE_DEVICE` | The USB device to write to. Only disks on a USB bus are offered, so the disk this machine boots from cannot be chosen by accident |

## Requirements

Root, a Linux machine that is not the live image, a USB device, and either the image already beside the program or a network to fetch it over.
