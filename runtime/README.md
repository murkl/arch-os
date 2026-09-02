# runtime — the program the trees beside it are run by

A single Go binary that draws an interface, asks questions, keeps the answers
and runs shell in order, reporting exactly where it broke. It is built as
`installer-linux-amd64` and a release ships it under whatever name that release
goes by — `archos`, in this one.

It installs nothing, and it knows nothing about Arch Linux, disks, packages or
desktops — there is not one of those words in the source. What is asked, what
the answers mean and what the shell does is **one yaml and the folders beside
it**. Started without one, the binary says so and stops.

```
archos                     # runs the tree beside the binary, or asks which of several
archos -check              # loads them, reports what they hold, changes nothing
archos -strings            # prints the translation template for one tree
archos -dir /path/to/tree  # runs that one and asks nothing
archos -version
```

## The tree

Only the declaration has to be there; everything else is found by its own name,
so a tree turns a part of the program off by leaving it out.

```
<name>.yaml              the whole declaration: what it is, what it asks, what order it works in
tasks/<id>/task.yaml     where that unit belongs
tasks/<id>/task.sh       what it does
hooks/<name>.sh          everything around the installation itself, one script per hook
lib.sh                   sourced before every script of this tree
locales/<code>.po        one catalog per language it speaks, beside the template it is filled in from
```

The declaration is **the one `.yaml` file in the folder's top level**, whatever
it is called — `installer.yaml`, `recovery.yaml`. Naming it after what it
declares is what lets two trees sit beside each other and still be told apart;
two of them in one folder is refused rather than resolved. The answer file and
the log are named after it too, so `recovery.yaml` answers into `recovery.conf`
and logs into `recovery.log`.

### A release is a binary and the trees beside it

The binary looks **next to itself** and nowhere else. What it finds there is
either a tree, or a folder of them:

```
archos          the binary
installer/      one program — installer.yaml and the folders beside it
recovery/       another — recovery.yaml and its own
```

Several is a question, and it is the first page of the program: each tree's own
`title` and `description`, in the order the folders are named. One is no
question at all and is opened on the way in. Nothing about a tree is read from
the outside — the folder names decide the order and nothing else.

Until one is chosen the frame is dressed by the first of them: the trees of one
release are one product, one wordmark and one colour. From the moment one is
opened, everything — the answers, the log, the words on screen — is that tree's.

`-dir` names one tree outright and skips the question, which is what the
`installer` and `recovery` commands on the ISO are.

### The declaration

```yaml
title: Arch OS Installer
description: Put Arch Linux on this machine.   # its row on the page that asks which program
run: Installation        # what one run of it is called

accent: "#1793d1"        # the one colour the interface is built from
logo: |                  # everything above the blank line is a dim eyebrow
  Arch Linux

  ██████ …               # the wordmark, swept in behind the accent

language: ARCH_OS_LOCALE_LANG # optional: an answer that also settles the words on screen

stages: [prepare, disk, base, finish]   # the order the installation happens in

confirm: |               # the last thing read before anything changes
  Arch Linux will be installed on {{ARCH_OS_DISK}}.

console: Type installer to start it again.   # optional: read on the way out

presets:                 # pages of starting points, offered on a machine with no answers
  - id: system
    title: Setup
    description: What kind of system to install.
    options:
      - id: desktop
        title: Desktop
        description: A full GNOME desktop.
        values:
          ARCH_OS_DESKTOP: gnome
      - id: shared
        title: Online                    # a starting point fetched rather than written out
        description: Take the answers from a configuration somebody shared.
        asks: ARCH_OS_CONFIG_SOURCE      # the one question choosing this row puts
        apply: ./tasks/share/import.sh   # shell that turns that answer into answers

variables:
  - name: ARCH_OS_USERNAME     # reaches every script as an environment variable
    title: User name
    description: |             # shown on the page that asks it
      The account you will log in with.
    group: Identity            # the heading its run of rows sits under
    required: true             # required and unanswered is what makes it ask
    pattern: '^[a-z_][a-z0-9_-]*$'
    error: Lower case letters, digits, - and _ only.
```

`confirm` is filled in from the answers, so it names the disk it is about rather
than warning in the abstract.

`description` and `run` are two different things and a tree needs both once a
release holds several: one is what the program *is*, read on the page that asks
which to open; the other is what one *run* of it is called, read wherever the
interface says what is happening — the row that starts it, the last warning, the
clock while it runs. A tree that names no run is an installation as far as the
runtime is concerned, which is right for one kind of tree and wrong for the rest.

### `hooks/`

Bash called by its own name. Nothing declares them: a script under one of these
names is the declaration, and any other name there is refused when the tree
loads.

| | |
|---|---|
| `preflight.sh` | can this machine be installed onto at all — a wall, run before all but the `first` questions |
| `online.sh` | is there internet; without it the network screen never appears |
| `wlan-device.sh` | the wireless device to use |
| `wlan-networks.sh` | the networks in range, one SSID per line |
| `wlan-connect.sh` | join one, with `WLAN_DEVICE`, `WLAN_SSID` and `WLAN_PASSPHRASE` in the environment |
| `restart.sh` | put this machine down and start it again |
| `shutdown.sh` | switch it off |

The preflight is a wall: what it writes to stderr is what the user reads.

`restart.sh` and `shutdown.sh` are what make leaving the interface a question
rather than an exit. A tree with them is saying the machine booted to run this
installer, so every way out — ctrl+c, the row that says quit, backing off the
first page, the end of an installation — lands on a page offering them. A tree
with neither exits the way any program does, which is right for an installer
somebody started from a shell they are still sitting in.

**`console:`** is the third way out, and the only one that runs nothing: the
program stops and the machine keeps running. Declare it where there is something
behind the interface to stop into. Its value is the sentence printed once the
frame is gone.

### `task.yaml`

```yaml
name: Install the graphics driver    # the line somebody reads while they wait
stage: desktop                       # one of the stages, which is what puts it in the run
needs: [desktop-gnome]               # ordered after these, inside the same stage
conditions:                          # every one has to hold, or it is not in the run at all
  - ARCH_OS_DESKTOP != none
  - ARCH_OS_DESKTOP_GRAPHICS_DRIVER != none
```

Seven more keys change what a unit *is* rather than what it does:

| | |
|---|---|
| `asks: VAR` | the run stops and asks for that value before this one runs |
| `confirm:` | asked as a yes or no in the frame before it runs; declining skips it |
| `default: no` | that offer opens on no instead of on yes |
| `report:` | the run stops on a page of this one's own once it has run |
| `shows: VAR` | that answer put on the page as a code to scan |
| `quits: true` | the program does not come back from this one — a reboot |
| `tty: true` | the interface stands aside and the script has the terminal, whole |

**`asks:`** is for the value that could not have been known before the work
started — the snapshot to go back to, once the disk holding them is open. The
question stands where the list of tasks was, and comes before `confirm:`, so an
offer can name what was just chosen. The variable it names must be one with a
set of answers and never a secret. Being named by a task is the whole
declaration: the value is left out of the opening questions and off the settings
page, and it is asked every time.

**`report:`** is the milestone a list of task names cannot say on its own: the
work is done, and everything after it is offered rather than needed. The first
paragraph is the headline, and `{{VAR}}` is filled in from the answers.

**`shows:`** puts one answer on that page twice: drawn large as a code to scan,
and printed under it as itself — for the value whose use is on a different
machine from the one showing it. A frame with no room for a whole code draws
none rather than one that will not scan.

The value is read back out of the answer file once the task has run, which is
also how the task puts it there:

```sh
printf "MY_LINK='%s'\n" "$url" >>"$INSTALLER_CONF"
```

That file is the only channel, and it is not a new one: it is shell, `KEY='value'`
to a line. A value that comes back empty is not a failure — the page shows its
words and no code.

Nothing lists the tasks: the folder is the list, and the order comes out of the
stages and the needs. A cycle, an unknown stage or a need pointing at nothing is
a message at startup rather than an installation that stops halfway.

### The shape of a question

Decided by the declaration rather than by a switch:

| declaration | what is drawn |
|---|---|
| nothing further | a text box |
| `values: [btrfs, ext4]` | a list |
| `command: timedatectl list-timezones` | a list, from what the command printed |
| `type: bool` | Yes / No, in the interface's language |
| `type: secret` | a password field, asked twice, never written down |

Further fields: `default` (any scalar — `true`, `8`, `pc105`), `prefill` (shell
printing a suggestion), `apply` (shell run when the answer takes effect), `first`
(asked before everything else), `free` (a row under a list that opens a text
box), and `conditions`.

`true` and `false` are read out loud as Yes and No wherever they turn up, so
`values: [auto, true, false]` is a bool with a third answer beside it.

A **secret** is the one required value that does not stop the program from being
ready. It is never written to the answer file, so it would be missing at every
start; instead it is asked for immediately before the run that needs it, used,
and forgotten.

**`apply`** is for the answer that changes the machine the installer is running
on rather than the one being installed:

```yaml
apply: loadkeys "$ARCH_OS_VCONSOLE_KEYMAP"
```

It runs the moment the answer is given, and once at startup for an answer this
run began with, so a restart stands where the last one left off. A failure is a
warning in the log; the answer stands either way.

**`first: true`** puts a question before everything else — before the network
screen, before the preflight, before the presets. It is what makes the keyboard
a passphrase is typed on a settled thing rather than a guess, and it is a
promise to make sparingly: every question here is asked before the check that
says this machine cannot be installed onto at all.

An options command may hand back a value and the text it is chosen by, separated
by a **tab** — everything before the tab is stored, everything after it is read:

```sh
lsblk -dn -o PATH,SIZE,MODEL | awk '{printf "%s\t%s  %s %s\n", $1, $1, $2, $3}'
# /dev/nvme0n1<TAB>/dev/nvme0n1  1.8T WD Black
```

An empty value in front of the tab is a real answer — "no variant", "the
default" — not a blank line.

### `conditions`

One condition, or a list of them where every one has to hold:

```
VAR == value
VAR != value
```

Deliberately not an expression language. Three tokens cover every guard an
installer needs, they read as a sentence, and they are checked against the
declared variables when the tree is opened — so a renamed variable is a message
at startup, never a task that silently never runs. There is no `or`: a row that
belongs under two unrelated circumstances is two rows.

### Shell fields

`command:`, `prefill:` and `apply:` take either shell or a file: a single line
beginning with `./` or `../` names one, anything else is the shell itself. So a
one-line option list stays in the YAML beside its variable, and a long one moves
into a file.

## What the interface does

In this order, and each page shown only if there is something on it:

- **What to do**, if there is more than one tree beside the binary. Everything
  after it belongs to whichever was chosen.
- **Language**, on a machine that has never answered anything, if more than one
  is on offer. Afterwards it is a row in the settings.
- **The `first` questions**, unnumbered — the few that cannot wait, because
  everything after them is typed on the keyboard they settle.
- **Network**, if the tree has an `online.sh` hook.
- **The check**, if the tree has a `preflight.sh` hook. A failure here is a wall.
- **Presets**, one page for each the tree declares. A set of answers, not a state
  the program stays in: every value one fills in is an ordinary value from the
  next page on. Offered
  once, on a machine that has never answered anything. A row with **`asks:`** is
  the same idea reached the long way round — one question, and the shell in its
  **`apply:`** turns that answer into answers by writing them into the answer
  file. The row is not got past until that has worked.
- **The questions** that are required, mean something, and have no acceptable
  answer yet — one to a page, numbered, in declaration order.
- **Install** or **Settings**, once nothing is left open.
- **Settings** — every answer on one page with what it is set to. `/` narrows it
  by name or by heading.
- **Installing** — a list of tasks filling in from the top, and nothing else. Not
  one line of what any script printed: a package manager's progress bars are
  noise with escape codes in them, and all of it goes to the log. A task that
  asks stops the list to ask; a declined one keeps its row, marked as passed
  over. A task with a `report:` stops it to say something.
- **A failure** — what the tool said, then which script, which line, which
  command, which exit code, then where the rest is written down.
- **The way out**, where the tree declared one: a restart, a shutdown, and —
  where the tree named a console to stop into — closing the installer with the
  machine left running.

Every answer is written to the answer file the moment it is given, so an
interruption costs nothing.

## Files it writes

Beside whoever started the program — never inside the tree, which may be a
read-only medium or a git checkout — and named after the tree, so two of them
started from the same folder keep their own:

```
./installer.conf   every answer, as KEY='value' — shell, editable by hand
./installer.log    everything: the runtime's own progress and every line a script printed
```

That is `installer.yaml`'s pair; `recovery.yaml` beside it writes
`recovery.conf` and `recovery.log`. `-conf` or `INSTALLER_CONF` moves them.

## What a script is handed

Every declared variable under its own name, answered or not, plus:

| | |
|---|---|
| `INSTALLER_DIR` | the tree, absolute |
| `INSTALLER_CONF` | the answer file |
| `INSTALLER_LOG` | the log |
| `INSTALLER_LANG` | the language showing |
| `INSTALLER_VERSION` | the runtime's version |

Scripts are **sourced** into a shell that already carries an `ERR` trap and,
where the tree declares one, the shared library. They need no preamble, no
`set -e`, no imports, no error handling: if a command fails, the task fails, and
the user is told the file, the line, the command and the exit code. The one
idiom this rests on — `[ "$X" = true ] && do_it` leaving a non-zero status when
the test is false — is not a failure and never reported as one.

Scripts ask nothing and print nothing for a person to read. The single exception
is a `tty: true` task, which is a session somebody is sitting in front of rather
than a step.

## Translations

The source string is the key. A line of Go says `T("Back")` and a catalog
answers with `"Zurück"`; a catalog with nothing to say about it leaves the
English standing. So a half-finished translation is useful from its first line.

The catalogs are **gettext `.po` files**, one per language, filled in from a
`.pot` template beside them — the format every translation platform reads, and
the one where the msgid a translator is shown is the English sentence itself.
Both templates are generated and neither is edited by hand: the runtime's out of
the Go sources, a tree's out of the loaded tree. `make locales` writes them and
brings every catalog up to them.

Two independent catalogs are merged: the runtime's own, compiled into the binary
under `locales/`, and the tree's own `locales/` beside its declaration. Adding a
language is adding a file.

```sh
cp locales/archos.pot locales/fr.po   # a language nobody has started yet
make locales                          # every template, and every catalog brought up to it
archos -check                         # reports coverage per language
```

A catalog names its own language in it, as the translation of `English` — that
is what the picker lists, so a language is always offered in its own words. See
[TRANSLATING.md](../TRANSLATING.md).

The language is chosen on the first run, changed in the settings, and otherwise
read from `LC_ALL`, `LC_MESSAGES` or `LANG`.

**`language:`** ties it to one of the tree's own answers instead. The value is
matched against the catalogs the way a machine's own locale is — `de_DE` is
German — so a tree that asks where a machine is has asked which language it
speaks: the opening page of languages is not shown, and neither is the language
row in the settings.

## Building

```sh
make build                  # bin/installer-linux-amd64, and its checksum
make run                    # straight from source, against ../installer
make run TREE=../recovery   # the other tree
make check                  # gofmt, vet, staticcheck, test, build — before a commit
```

`run` takes one tree, so the page that asks which of several to open is not on
its way. That page needs the trees beside a binary, which is what a build makes:
`make build` at the repository root, then `release/archos`.

The binary is static and has no runtime dependencies of its own. It has to live
beside the trees it runs, since that is where it looks for them.

## Layout

```
main.go              find the trees, load them, open the interface
internal/spec        the tree, read into memory, checked over and put in order
internal/store       the answers, and the file they survive a restart in
internal/exec        the only place a process is started, and the failure shape
internal/runner      what a question offers, which tasks this run consists of
internal/wlan        joining a wireless network, the way the tree's hooks say to
internal/i18n        the message catalogs
internal/logging     the single sink for everything a run records
locales/             the runtime's own words, compiled in
tools/potgen/        reads every T("…") out of the sources and writes the template
tui/                 the interface: one frame, a stack of pages, no page draws its own
```
