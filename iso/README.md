# Arch OS ISO

Stock Arch `releng`, patched: boot ➜ Plymouth ➜ Arch OS. Nothing in between.

- The [runtime](../runtime) with the [installer](../installer) and the
  [recovery](../recovery) tree beside it at `/opt/archos`, started by a systemd
  unit on tty1, no autologin, no shell, and a root shell handed back on that
  console whenever it stops. Started with no argument, so the first page is the
  question of which of the two to open
- `archos`, `installer` and `recovery` on the path, which is how any of them is
  started from that shell: the first asks, the other two are that question
  already answered. All of them keep their answers in `/opt/archos`, so a second
  run picks up where the first left off. `/etc/motd` and `/etc/issue` say so
- Plymouth boot splash with the Arch OS theme
- Nord palette and a console font, put on by the two launcher scripts: a
  console font holds at most 512 glyphs, and the interface draws itself out of
  what one is guaranteed to have
- Networking exactly as the Arch ISO ships it (iwd, systemd-networkd); the
  installer's preflight says to use `iwctl` if there is none
- UEFI only, squashfs/zstd

## Building

```sh
make -C .. build   # assembles ../release: the binary and both trees beside it
make -C .. iso     # the above, then this ISO, into ../dist
```

Or from here, once a release exists:

```sh
make build          # or: RELEASE_DIR=../release SNAPSHOT_VERSION=1234abc ./build.sh
```

The `*.iso` and its `.sha256` land in `DIST_DIR`, default `../dist`.
`SNAPSHOT_VERSION` defaults to the short commit SHA of `HEAD`.

The Plymouth theme comes from a
[plymouth-theme-arch-os](https://github.com/murkl/plymouth-theme-arch-os)
checkout beside this repository when there is one, and is fetched otherwise.
`PLYMOUTH_THEME_SRC` points at a different `src/`.

A build leaves nothing root-owned behind. `archiso/` is a fresh copy of the
stock profile every run, removed on success and kept on failure, there is
nothing else to read a failure out of. `download/` stays either way; it is the
vendored theme, and it is what lets the next build run without a network.

## Booting it

```sh
make smoke                  # the newest image in ../dist
make smoke ISO=path/to.iso
```

Boots the image under qemu and OVMF and waits for the first page to appear on
its console, then switches the machine off. That proves the part no linter sees:
the boot entry, the initramfs and its plymouth hook, the systemd unit on tty1,
the runtime, and the trees it loads.

Needs `qemu-base`, `edk2-ovmf`, `tesseract` and `tesseract-data-eng`. The
console it photographed is left in `smoke/`, one frame on success, all of them
on a failure. CI runs this on every image it builds.

## What is where

```
build.sh                                 assembles and runs mkarchiso
smoke.sh                                 boots a built image and waits for the first page
src/etc/systemd/system/archos.service    starts it on tty1
src/usr/local/bin/archos                 the way in, it dresses the console first
src/usr/local/bin/installer              straight into the installer tree
src/usr/local/bin/recovery               straight into the recovery tree
src/usr/local/bin/archos-console-theme   paints the console in the Nord palette
```

`make lint` shellchecks and shfmts every script here. `archiso` and root are
only needed for `make build`; `make clean` takes back `archiso/`, `download/`
and `smoke/`.
