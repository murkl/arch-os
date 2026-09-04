# Arch OS ISO

Stock Arch `releng`, patched: boot → Plymouth → Arch OS. Nothing in between.

- Arch OS Installer included
- Arch OS Recovery included
- Arch OS Bootsplash (Plymouth)
- Nord palette and console font applied before the interface draws
- Networking exactly as the Arch ISO ships it (iwd, systemd-networkd)
- UEFI only, squashfs/zstd

## How it starts

The [Oak](https://github.com/murkl/oak) binary with the [Installer](../modules/installer) and the [Recovery](../modules/recovery) module beside it lives at `/opt/arch-os` and is started by a systemd unit on tty1. No autologin, no shell. A root shell is handed back on that console whenever it stops.

It starts with no module named, so the first pages are the language and then the choice between the two.

| Command | Description |
| --- | --- |
| `installer` | Opens the Installer module directly |
| `recovery` | Opens the Recovery module directly |
| `iwctl` | Join a wireless network |

**Note:** _Both keep their answers in `/opt/arch-os`, so a second run picks up where the first left off. `/etc/motd` and `/etc/issue` say so._

## Build bootable ISO

```
make -C .. build   # assembles ../release: the binary, oak.yaml, the modules folder
make -C .. iso     # the above, then this ISO, into ../dist
```

Or from here, once a release already exists:

```
make build          # or: RELEASE_DIR=../release SNAPSHOT_VERSION=1234abc ./build.sh
```

**Note:** _The generated `*.iso` file and its `.sha256` can be found in the `../dist` directory. `SNAPSHOT_VERSION` defaults to the short commit SHA of `HEAD`._

The Bootsplash theme comes from a **[plymouth-theme-arch-os](https://github.com/murkl/plymouth-theme-arch-os)** checkout beside this repository if one exists, and is fetched otherwise. `PLYMOUTH_THEME_SRC` points at a different `src/`.

A build leaves nothing root-owned behind:

- `archiso/` is a fresh copy of the stock profile on every run, removed on success and kept on failure
- `download/` stays either way and holds the vendored theme, which is what lets the next build run without a network connection

## Boot the ISO

```
make smoke                  # the newest image in ../dist
make smoke ISO=path/to.iso
```

Boots the image under QEMU and OVMF, waits for the first page to appear on its console, then shuts the machine down. This checks what no linter can: the boot entry, the initramfs and its Plymouth hook, the systemd unit on tty1, the binary and the modules it loads.

**Note:** _Needs `qemu-base`, `edk2-ovmf`, `tesseract` and `tesseract-data-eng`. The console screenshot is saved to `smoke/`, one frame on success and all of them on failure. CI runs this on every image it builds._

## What is where

```
build.sh                                 assembles and runs mkarchiso
smoke.sh                                 boots a built image and waits for the first page
src/etc/systemd/system/arch-os.service   starts it on tty1
src/usr/local/bin/arch-os                the entry point, sets up the console first
src/usr/local/bin/installer              opens the Installer module directly
src/usr/local/bin/recovery               opens the Recovery module directly
src/usr/local/bin/arch-os-console-theme  applies the Nord palette to the console
```

**Note:** _`make lint` runs shellcheck and shfmt on every script here. `archiso` and root access are only needed for `make build`. `make clean` removes `archiso/`, `download/` and `smoke/`._
