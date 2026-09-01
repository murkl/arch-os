# Arch OS ISO

<p><img src="./screenshot.png"></p>

Stock Arch `releng`, patched: boot ➜ Plymouth ➜ the installer. Nothing in
between.

- The [runtime](../runtime) and the [setup](../setup) tree, installed at
  `/opt/installer`, started directly by a systemd unit on tty1 — no autologin,
  no shell, and a root shell handed back on that same console whenever the
  installer stops: because somebody chose to leave it, or because it crashed
- `installer` on the path, which is how it is started again from that shell —
  the same script the unit runs, so both keep their answers in `/opt/installer`
  and a second run picks up where the first left off. `/etc/motd` and
  `/etc/issue` say so, and so does the installer on its way out
- Plymouth bootsplash with the Arch OS theme
- Nord palette and a console font, put on by the `installer` script itself and
  so by every start of it, so the installer looks like itself on a bare VT — a
  console font holds at most 512 glyphs, and the interface draws itself out of
  what one is guaranteed to have
- Networking left exactly as the Arch ISO ships it (iwd, systemd-networkd);
  the installer's own preflight check says to use `iwctl` if there is none
- UEFI only, squashfs/zstd

## Building

```sh
make -C .. build   # assembles ../release: the binary and the installer tree
make -C .. iso     # the above, then this ISO, into ../dist
```

Run from here directly once a release exists:

```sh
make build          # or: RELEASE_DIR=../release SNAPSHOT_VERSION=1234abc ./build.sh
```

The generated `*.iso` (and its `.sha256`) land in `DIST_DIR`, which defaults to
`../dist` — the folder for what is downloaded rather than executed, where the
installer tarball goes too. `SNAPSHOT_VERSION` defaults to the short commit SHA
of `HEAD`, the same scheme [runtime](../runtime) uses for the binary.

The Plymouth theme is taken from a
**[plymouth-theme-arch-os](https://github.com/murkl/plymouth-theme-arch-os)**
checkout beside this repository when there is one, and fetched otherwise.
Point `PLYMOUTH_THEME_SRC` at a `src/` directory to build against a different
one.

A build leaves nothing behind. `archiso/` is a copy of the stock profile made
fresh every run, so a build that worked takes it with it; a build that failed
keeps it — there is nothing else to read a failure out of — but hands it back to
whoever started the build rather than leaving it owned by root. `download/` is
the exception on purpose: it is the vendored theme, and it is what lets the next
build run without a network.

## Booting it

```sh
make smoke                  # the newest image in ../dist
make smoke ISO=path/to.iso
```

Boots the image under qemu and OVMF and waits for the installer's first page to
appear on its console — no installation happens, and the machine is switched off
the moment the page is recognised. What that proves is the part no linter sees:
the boot entry, the initramfs and its plymouth hook, the systemd unit on tty1,
the runtime, and the tree it loads.

Needs `qemu-base`, `edk2-ovmf`, `tesseract` and `tesseract-data-eng`. The
console it photographed is left in `smoke/` — one frame on success, all of them
on a failure. CI runs this on every image it builds, before anything is
promoted.

## What is where

```
build.sh                                   assembles and runs mkarchiso
smoke.sh                                   boots a built image and waits for the installer
src/etc/systemd/system/installer.service   starts the installer on tty1
src/usr/local/bin/installer                the one way in: the unit and the prompt both run this, and it dresses the console first
src/usr/local/bin/installer-console-theme  paints the console in the Nord palette
```

`make lint` shellchecks and shfmts every script here; `archiso` itself, and
root, are only needed for `make build`. `make clean` takes back `archiso/`,
`download/` and `smoke/`.
