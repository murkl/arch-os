# Contributing

`main` is the only long-lived branch. Every change branches off it and comes back as one commit, and a release is one more pull request.

## Doing the Work

```
make check                   # the whole gate, as CI runs it
make fmt                     # every file formatted, by cargo fmt and shfmt
make run                     # the Installer, out of the sources
make run MODULE=recovery     # ...the Recovery
make run ARGS=--dry-run      # ...without touching the machine
make build                   # the program, with every module inside it
make iso                     # the program, the Recovery image and the ISO that carries it
make iso ISO_RECOVERY=false  # ...the ISO as a release builds it, which fetches the Recovery
make image                   # ...only the images, from the program already built
make smoke                   # boot the newest of both and work their first page with the keyboard
make e2e                     # install the newest ISO, boot, repair, boot again, start and rewrite its Recovery
make e2e START=desktop       # ...the Desktop starting point, booted to GNOME's login screen
make clean                   # remove every build output
```

```
sudo pacman -S --needed make rust shellcheck shfmt zsh yamllint actionlint zizmor \
    gettext diffutils gitleaks kbd terminus-font archiso systemd-ukify qemu-base edk2-ovmf tesseract tesseract-data-eng openssh libisoburn
```

**Note:** _CI installs the same packages and runs the same commands in an Arch container. There is no second definition of green._

### Where a Change Belongs

- Packages, tasks, questions: **[installer](../installer)**
- Repairing a system: **[recovery](../recovery)**
- Writing the boot device: **[get.sh](../get.sh)**
- Functions both modules use: **[lib.sh](../lib.sh)**, checked by **[lib.check.sh](../lib.check.sh)**
- Product name and look: **[product.yaml](../product.yaml)**
- The words on screen, in German: **[locales/de.po](../locales/de.po)**
- The bootable images, the ISO and the Recovery: **[iso](../iso)**
- The interface itself: **[runtime](../runtime)**, in Rust, built into the images with everything above inside it

**Note:** _What Arch OS puts on a disk and why: **[➜ Reference](REFERENCE.md)**. What a module may declare and the contract its scripts follow: **[➜ Runtime](../runtime/README.md)**._

## Writing a Task

### Files a Task Ships

Every file a task writes into the new system lies in `data/` beside `task.sh`, named after the file it becomes. `render` from `lib.sh` fills it, `where` names the folder.

```
render "$(where)/main.conf" KERNEL="$KERNEL" CMDLINE="$cmdline" >"${MNT}/boot/loader/entries/main.conf"
```

- `{{NAME}}` is the only placeholder, filled from `NAME=value` and never from the environment. Every `$` stays for whatever reads the file later
- An unfilled placeholder, an unused value and a stray `{{` fail the task. Values are filled once, left to right
- A file without placeholders goes through `render` too, so one added later cannot reach a disk unfilled
- Not `envsubst`: it reads the environment, fills an unset variable with nothing, and without a list of names fills every `${…}`
- The boot entries' templates lie in `recovery/data/boot/`, since the Recovery writes them again through `boot_entries`
- `make lint` refuses a `{ … } >"${MNT}/…"` block

Where a program reads a directory, the file goes there. These have none:

| File | How | Why |
| --- | --- | --- |
| `/etc/pacman.conf` | Edited | One `Include =` per file, see `pacman_include`. A glob stops pacman once it matches nothing |
| `/etc/locale.gen` | Edited | `locale-gen` reads nothing else, and a glibc update runs it again |
| `/etc/environment` | Edited | `pam_env` reads nothing else, and `sudo` takes the editor from it |
| `/etc/nsswitch.conf` | Edited | glibc reads nothing else |
| `/etc/gdm/custom.conf` | Written whole, with automatic login only | GDM reads nothing else |
| `/etc/xdg/reflector/reflector.conf` | Written whole | `reflector.service` names it on its command line and in its sandbox |

### Closing the Target

Swap off, sync, unmount, lock: in the Installer before it partitions, in the Recovery before it opens the disk. A second attempt starts from whatever the first left.

- `umount -R`, never `-A`, which reaches beyond the target and in the Recovery would take the rollback's snapshots
- `fuser -M`, without which a target that is not a mount point resolves to the live system
- Whatever still holds the target is logged, then killed
- Done means on the disk: the Installer's last task and the Recovery's rollback and rebuild end with `sync`, or a power cut leaves FAT with empty boot files

### When Something Goes Wrong

| Kind | Example | On the page |
| --- | --- | --- |
| Expected | No internet, a wrong disk, a damaged download | A headline and what to do, translated. Nothing to share |
| A script that broke | A package Arch renamed, a tool that changed its output | Module, task, line, command and output, and **Share the log** |

A script stops on what it expects with `exit` and a status, which `errors:` in `module.yaml` puts into words: `3` no internet, `4` GitHub not answering, `5` the AUR not answering. Statuses from `10` up belong to the task or action that uses them. **[➜ Stopping on Purpose](../runtime/README.md#stopping-on-purpose)**

## Translating

**The English sentence is the key.** One catalog per language, `locales/<code>.po`, holds every text on screen: the runtime's and both modules'. A catalog without a translation shows the English, so a translation is useful from its first line.

- `make check` holds every catalog to every text. A text reworded on screen, in the YAML or in the runtime, fails until its entry is reworded too, and so does an entry nothing uses any more. The failing test lists them
- `{{ARCH_OS_DISK}}` stays as it is, braces and name, and so do the blank lines between paragraphs
- A text of several paragraphs is one entry: `msgid ""`, then one line a paragraph, with `\n` as the file shows it

### Adding a Language

```
cp locales/de.po locales/fr.po
```

Translate every `msgstr` and open a pull request. The language shows up on the first page as soon as its catalog exists.

- `msgid "English"` translates to your language's own name: `Deutsch`, `Français`
- A `msgstr` left English shows English, nothing breaks

### What the Console Can Draw

Before GNOME exists there is one console font with at most 512 glyphs: **Latin with its accents, Greek and Cyrillic**. Arabic, Hebrew, Chinese, Japanese, Korean, Vietnamese and the Indic scripts cannot be drawn on a Linux virtual console at all, so open an issue before you start on one.

**Note:** _`make check` reads the product, the catalogs, the library and every module against the glyph tables of the fonts **[iso/font.sh](../iso/font.sh)** builds, so a character that would be a box fails at your desk._

## Pictures in the Docs

All are generated, so none outlives the interface it shows. CI never renders them: you run them by hand and commit them with the change.

```
docs/screenshots.sh 2.1.0   # every page in screenshots.yaml, showing that version
docs/banner.sh              # the banner, from two of them and the tagline in README.md
docs/svg.py                 # the download button and the requirements, with their text alternatives in README.md
```

- `screenshots.sh`'s version defaults to the next patch's pre-release. Name the release the change heads for, so `main` shows it
- They need `chromium`, `imagemagick`, `python-fonttools`, `python-pyte`, `python-yaml` and `ttf-firacode-nerd`, none of which a build or `make check` needs, and systemd as PID 1, which `localectl` and `timedatectl` ask
- Every run starts with `--dry-run`, so nothing is partitioned, mounted or restarted. Which pages are taken and every answer given is in **[screenshots.yaml](screenshots.yaml)**
- `installing.png` catches a run while it is going, so it differs from run to run

## Workflow

```mermaid
flowchart LR
    M["main"] -->|branch off| B["feat/…"]
    B -->|pull request| I["Title · Check · Image"]
    I -->|squash merge| M2["main"]
    M2 --> P["Release pull request<br/>version · changelog"]
    P -->|merge| R["Release<br/>tag · images · page"]

    style R fill:#1793d1,stroke:#1793d1,color:#fff
```

1. **Branch off `main`.** Name the branch after what it does: `feat/wireless-settings`, `fix/helix-test`. Nothing reads the name
2. **Open a pull request right away**, as a draft while it is not done. A branch is checked through its pull request, never on its own. Every push is built, booted and installed, which takes about 30 minutes
3. **Squash merge**, or switch on auto-merge. `main` takes the pull request once `Check`, `Image` and `Title` have passed, as one commit under its title, and deletes the branch

- The commits inside the branch are yours to shape. Only the title reaches `main`
- A draft gets the same run and cannot be merged. Marking it ready starts nothing, since it changes no code
- A pull request that changes only `docs/`, Markdown or `LICENSE` is checked, never built: none of it reaches an image

## The Title

The title is the one line `main` keeps. The next version and the changelog are read from it, so it follows **[Conventional Commits](https://www.conventionalcommits.org)**: a type, a colon, what changed.

| Title | Version | On the Release Page |
| --- | --- | --- |
| `fix: the Recovery finds a kernel on a separate /boot` | 2.0.0 → 2.0.1 | Bug Fixes |
| `feat: join a wireless network before the first download` | 2.0.0 → 2.1.0 | Features |
| `feat!: one answer file per module` | 2.0.0 → 3.0.0 | ⚠ BREAKING CHANGES |
| `docs:` `refactor:` `test:` `build:` `ci:` `chore:` | none | nothing |

- Write it for someone installing or repairing a machine. `Title` refuses a title without a type, and checks it again whenever it is edited
- Merging shows the title and an empty description. Leave both as they are, with two exceptions typed into the description:
  - `BREAKING CHANGE: …` tells the release page what somebody has to do
  - `Release-As: 3.0.0` sets a version that is chosen rather than counted

**Note:** _A title that turns out wrong after the merge is corrected in the description of the merged pull request. The next release run reads this instead of the commit:_

```
BEGIN_COMMIT_OVERRIDE
fix: the corrected line
END_COMMIT_OVERRIDE
```

## What CI Runs

| Job | When | Does |
| --- | --- | --- |
| `Title` | A pull request is opened, pushed to or edited | Checks the title |
| `Check` | A pull request, a release, every Monday, on demand | `make check` |
| `Image` | As `Check`, where the change reaches the image | Builds the program, the Recovery image and the ISO, boots both, and installs, repairs and boots a Core from the ISO. Then starts its Recovery and writes it again from the ISO. Every Monday and on demand also the Desktop starting point, booted to GNOME's login screen |
| `Release` | A push to `main` | The release pull request, or once that is merged, the tag and the draft page |
| `Publish` | A release | Attaches the files `Image` booted to the page, signed, and publishes it |

- A merge into `main` runs `Release` alone: its pull request has passed `Check` and `Image` already
- A run started by hand offers its images for download: `gh workflow run CI --ref <branch>`

## Releasing

Nothing is typed and nothing is tagged by hand.

1. **Every merge that releases something** opens or updates the pull request `chore(main): release 2.1.0`. It raises the version in `.release-please-manifest.json` and writes that version's section of **[CHANGELOG.md](../CHANGELOG.md)**
2. **Merging it is the release.** It starts no run of its own, so an admin merges it past the checks: `gh pr merge <number> --squash --admin`. The run on `main` tags `v2.1.0`, checks, builds and boots the images as that version, attaches them to the release page and publishes it

- Merges collect in the release pull request until it is merged. When to release is a decision, not a schedule
- The page carries `arch-os-2.1.0-x86_64.iso` and `arch-os-2.1.0-recovery-x86_64.tar`, both with signed build provenance. The ISO leaves the Recovery out to stay under GitHub's 2 GiB per file: its Installer fetches the `.tar`, and an installed Recovery updates itself from it
- Every other build is named after a pre-release of the next patch: `arch-os-2.0.1-dev-x86_64.iso`. `make build VERSION=2.1.0` names a build after any version, which it stamps into the program

**Note:** _The page stays a draft until every file is attached. A run that fails on the way leaves a draft: re-run its failed jobs._

## The Repository

What GitHub holds this repository to lives in **[.github/settings/](../.github/settings)**, not in clicks. An admin logged in with `gh` applies it:

```
make github
```

| File | Says |
| --- | --- |
| `repository.json` | Squash merges only, under the pull request's title alone; auto-merge allowed; a merged branch is deleted |
| `ruleset.json` | `main` takes only a pull request that has passed `Check`, `Image` and `Title`. An admin may merge one past them, which the release pull request needs. No force push, no deletion |
| `actions.json` | A workflow's token can only read unless it says otherwise, and may open the release pull request |

Run it again after changing one of them. The script is the same in every project released this way, and `ruleset.json` names each project's checks. No CodeQL: the only language it finds here is the workflows, which zizmor checks in `make check`.
