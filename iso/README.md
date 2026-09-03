# Arch OS ISO

Stock Arch `releng`, patched: boot → Plymouth → Arch OS. Nothing in between.

- The [runtime](../runtime) with the [installer](../installer) and the
  [recovery](../recovery) module beside it, at `/opt/arch-os`, started by a
  systemd unit on tty1 — no autologin, no shell, and a root shell handed back
  on that console whenever it stops. Started with no module named, so the
  first pages are the language and then the choice between the two modules
- `installer` and `recovery` on the path, so either can be started from that
  shell: both are that same choice already made, and both still ask for the
  language first. They keep their answers in `/opt/arch-os`, so a second run
  picks up where the first left off — `/etc/motd` and `/etc/issue` say so
- Plymouth boot splash with the Arch OS theme
- Nord palette and a console font, applied by the two launcher scripts: a
  console font holds at most 512 glyphs, and the interface draws itself
  using only what's guaranteed to be available
- Networking exactly as the Arch ISO ships it (iwd, systemd-networkd); the
  installer's preflight check suggests `iwctl` if none is found
- UEFI only, squashfs/zstd

## Building

```sh
make -C .. build   # assembles ../release: the binary, runtime.yaml, the modules folder
make -C .. iso     # the above, then this ISO, into ../dist
```

Or from here, once a release already exists:

```sh
make build          # or: RELEASE_DIR=../release SNAPSHOT_VERSION=1234abc ./build.sh
```

The `*.iso` and its `.sha256` land in `DIST_DIR`, `../dist` by default.
`SNAPSHOT_VERSION` defaults to the short commit SHA of `HEAD`.

The Plymouth theme comes from a
[plymouth-theme-arch-os](https://github.com/murkl/plymouth-theme-arch-os)
checkout beside this repository if one exists, and is fetched otherwise.
`PLYMOUTH_THEME_SRC` points at a different `src/`.

A build leaves nothing root-owned behind. `archiso/` is a fresh copy of the
stock profile on every run, removed on success and kept on failure — that's
the only place to inspect after a failed build. `download/` stays either
way; it holds the vendored theme, which is what lets the next build run
without a network connection.

## Booting it

```sh
make smoke                  # the newest image in ../dist
make smoke ISO=path/to.iso
```

Boots the image under QEMU and OVMF, waits for the first page to appear on
its console, then shuts the machine down. This checks what no linter can:
the boot entry, the initramfs and its Plymouth hook, the systemd unit on
tty1, the runtime, and the modules it loads.

Needs `qemu-base`, `edk2-ovmf`, `tesseract` and `tesseract-data-eng`. The
console screenshot is saved to `smoke/` — one frame on success, all of them
on failure. CI runs this on every image it builds.

## What is where

```
build.sh                                 assembles and runs mkarchiso
smoke.sh                                 boots a built image and waits for the first page
src/etc/systemd/system/arch-os.service   starts it on tty1
src/usr/local/bin/arch-os                the entry point; sets up the console first
src/usr/local/bin/installer              opens the installer module directly
src/usr/local/bin/recovery               opens the recovery module directly
src/usr/local/bin/arch-os-console-theme  applies the Nord palette to the console
```

`make lint` runs shellcheck and shfmt on every script here. `archiso` and
root access are only needed for `make build`; `make clean` removes
`archiso/`, `download/` and `smoke/`.
