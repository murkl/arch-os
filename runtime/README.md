# runtime: the program the modules beside it are run by

A single Go binary that draws an interface, asks questions, keeps the answers
and runs shell in order, reporting exactly where it broke. It is built as
`runtime-linux-amd64` and a release ships it beside its modules as `runtime`.

It installs nothing, and it knows nothing about Arch Linux, disks, packages or
desktops: there is not one of those words in the source. What the product is
called, what it looks like and what it offers is `runtime.yaml`; what is asked,
what the answers mean and what the shell does is **one folder per module**.
Started without them, the binary says so and stops.

```
runtime                     # asks the language, then which module to open
runtime --installer         # that one outright, past the question
runtime -check              # loads everything, reports what it holds, changes nothing
runtime --installer -check  # just that one
runtime --installer -strings   # its translation template
runtime -dir /path/to/release  # look there instead of beside the binary
runtime -version
```

## The runtime

The binary looks **next to itself** and nowhere else, for `runtime.yaml` and the
module folders it lists:

```
runtime         the binary
runtime.yaml    what the product is called, what it looks like, what it offers
installer/      one module: installer.yaml and the folders beside it
recovery/       another: recovery.yaml and its own
```

```yaml
name: Arch OS            # over the pages drawn before a module has been opened
accent: "#1793d1"        # the one colour the interface is built from
logo: |                  # everything above the blank line is a dim eyebrow
  Arch Linux

  ██████ …               # the wordmark, swept in behind the accent

modules:                 # what it offers, in the order it offers them
  - installer
  - recovery
```

`modules:` is the whole of the list. A folder that is not on it is not part of
this product, and adding one is a line here and a folder — nothing in the
binary knows any module by name. Each name is both the folder and the word that
opens it outright: `runtime --installer`, which is what the `installer` and
`recovery` commands on the ISO are.

Nothing here is compiled in. A different name, a different colour and a
different list of modules is a different product out of the same binary.

## A module

Only the declaration has to be there; everything else is found by its own name,
so a module turns a part of the program off by leaving it out.

```
<name>.yaml              the whole declaration: what it is, what it asks, what order it works in
tasks/<id>/task.yaml     where that unit belongs
tasks/<id>/task.sh       what it does
hooks/<name>.sh          everything around the work itself, one script per hook
lib.sh                   sourced before every script of this module
locales/<code>.po        one catalog per language it speaks, beside the template it is filled in from
```

The declaration is **the one `.yaml` file in the folder's top level**, whatever
it is called: `installer.yaml`, `recovery.yaml`. Naming it after the folder is
the convention and is what lets two modules sit open in an editor and still be
told apart; two of them in one folder is refused rather than resolved.

The **folder name is the module's identity**: what `runtime.yaml` lists, what
the command line names, and what its answers and its log are called. The
`installer` module answers into `installer.conf` and logs into `installer.log`.

### The order of the opening

The language leads, then the module, then everything that module wants settled:

```
language → which module → its `first:` questions → network → preflight → presets → hub
```

The language is the runtime's own answer rather than any module's — it is
settled before there is a module to settle anything, the question of which
module to open is itself read in it, and every module is read in it afterwards.
It is kept in `runtime.conf` beside the modules' own answer files, and written
into whichever module is opened so that every script it runs is told what is on
screen. A module that ties it to one of its own answers (`language:` below) can
still change it from there.

Naming a module on the command line answers the second question, never the
first: the language page is drawn either way.

### The declaration

```yaml
title: Arch OS Installer
description: Put Arch Linux on this machine.   # its row on the page that asks which program
run: Installation        # what one run of it is called

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

`description` and `run` are two different things and a module needs both once a
runtime offers several: one is what the module *is*, read on the page that asks
which to open; the other is what one *run* of it is called, read wherever the
interface says what is happening: the row that starts it, the last warning, the
clock while it runs. A module that names no run is an installation as far as the
runtime is concerned, which is right for one kind of module and wrong for the
rest.

### `hooks/`

Bash called by its own name. Nothing declares them: a script under one of these
names is the declaration, and any other name there is refused when the module
loads.

| | |
|---|---|
| `preflight.sh` | can this machine be installed onto at all, a wall, run before all but the `first` questions |
| `online.sh` | is there internet; without it the network screen never appears |
| `wlan-device.sh` | the wireless device to use |
| `wlan-networks.sh` | the networks in range, one SSID per line |
| `wlan-connect.sh` | join one, with `WLAN_DEVICE`, `WLAN_SSID` and `WLAN_PASSPHRASE` in the environment |
| `restart.sh` | put this machine down and start it again |
| `shutdown.sh` | switch it off |

The preflight is a wall: what it writes to stderr is what the user reads.

`restart.sh` and `shutdown.sh` are what make leaving the interface a question
rather than an exit. A module with them is saying the machine booted to run it,
so every way out (ctrl+c, esc during a run, the row that says quit, backing off
the first page, the end of an installation) lands on a page offering them. That
page is drawn *over* whatever was happening: a run carries on behind it and the
header keeps counting, and only choosing one of its rows stops anything. A
module with neither exits the way any program does, which is right for something
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
| `quits: true` | the program does not come back from this one, a reboot |
| `tty: true` | the interface stands aside and the script has the terminal, whole |

**`asks:`** is for the value that could not have been known before the work
started: the snapshot to go back to, once the disk holding them is open. The
question stands where the list of tasks was, and comes before `confirm:`, so an
offer can name what was just chosen. The variable it names must be one with a
set of answers and never a secret. Being named by a task is the whole
declaration: the value is left out of the opening questions and off the settings
page, and it is asked every time.

**`report:`** is the milestone a list of task names cannot say on its own: the
work is done, and everything after it is offered rather than needed. The first
paragraph is the headline, and `{{VAR}}` is filled in from the answers.

**`shows:`** puts one answer on that page twice: drawn large as a code to scan,
and printed under it as itself, for the value whose use is on a different
machine from the one showing it. A frame with no room for a whole code draws
none rather than one that will not scan.

The value is read back out of the answer file once the task has run, which is
also how the task puts it there:

```sh
printf "MY_LINK='%s'\n" "$url" >>"$MODULE_CONF"
```

That file is the only channel, and it is not a new one: it is shell, `KEY='value'`
to a line. A value that comes back empty is not a failure: the page shows its
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

Further fields: `default` (any scalar, `true`, `8`, `pc105`), `prefill` (shell
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

**`first: true`** puts a question before everything else: before the network
screen, before the preflight, before the presets. It is what makes the keyboard
a passphrase is typed on a settled thing rather than a guess, and it is a
promise to make sparingly: every question here is asked before the check that
says this machine cannot be installed onto at all.

An options command may hand back a value and the text it is chosen by, separated
by a **tab**: everything before the tab is stored, everything after it is read:

```sh
lsblk -dn -o PATH,SIZE,MODEL | awk '{printf "%s\t%s  %s %s\n", $1, $1, $2, $3}'
# /dev/nvme0n1<TAB>/dev/nvme0n1  1.8T WD Black
```

An empty value in front of the tab is a real answer ("no variant", "the
default"), not a blank line.

### `conditions`

One condition, or a list of them where every one has to hold:

```
VAR == value
VAR != value
```

Deliberately not an expression language. Three tokens cover every guard an
installer needs, they read as a sentence, and they are checked against the
declared variables when the module is opened, so a renamed variable is a message
at startup, never a task that silently never runs. There is no `or`: a row that
belongs under two unrelated circumstances is two rows.

### Shell fields

`command:`, `prefill:` and `apply:` take either shell or a file: a single line
beginning with `./` or `../` names one, anything else is the shell itself. So a
one-line option list stays in the YAML beside its variable, and a long one moves
into a file.

## What the interface does

In this order, and each page shown only if there is something on it:

- **Language**, if more than one is on offer. It is the runtime's own question
  and comes before everything, the question below included. Afterwards it is a
  row in the settings.
- **What to do**, if the runtime offers more than one module and none was named
  on the command line. Everything after it belongs to whichever was chosen.
- **The `first` questions**, unnumbered: the few that cannot wait, because
  everything after them is typed on the keyboard they settle.
- **Network**, if the module has an `online.sh` hook.
- **The check**, if the module has a `preflight.sh` hook. A failure here is a
  wall.
- **Presets**, one page for each the module declares. A set of answers, not a state
  the program stays in: every value one fills in is an ordinary value from the
  next page on. Offered
  once, on a machine that has never answered anything. A row with **`asks:`** is
  the same idea reached the long way round: one question, and the shell in its
  **`apply:`** turns that answer into answers by writing them into the answer
  file. The row is not got past until that has worked.
- **The questions** that are required, mean something, and have no acceptable
  answer yet, one to a page, numbered, in declaration order.
- **Install** or **Settings**, once nothing is left open.
- **Settings**: every answer on one page with what it is set to. `/` narrows it
  by name or by heading.
- **Installing**: a list of tasks filling in from the top, and nothing else. Not
  one line of what any script printed: a package manager's progress bars are
  noise with escape codes in them, and all of it goes to the log. A task that
  asks stops the list to ask; a declined one keeps its row, marked as passed
  over. A task with a `report:` stops it to say something.
- **A failure**: what the tool said, then which script, which line, which
  command, which exit code, then where the rest is written down.
- **The way out**, where the module declared one: a restart, a shutdown, and,
  where the module named a console to stop into, closing the interface with the
  machine left running. Opening it never stops a run; choosing a row does.

Every answer is written to the answer file the moment it is given, so an
interruption costs nothing.

## Files it writes

Beside whoever started the program (never inside a module, which may be a
read-only medium or a git checkout) and named after the module, so two of them
started from the same folder keep their own:

```
./runtime.conf     what the runtime keeps for every module: the language
./installer.conf   every answer, as KEY='value': shell, editable by hand
./installer.log    everything: the runtime's own progress and every line a script printed
```

That is the `installer` module's pair; `recovery` beside it writes
`recovery.conf` and `recovery.log`. `-conf` or `RUNTIME_CONF` moves them.

## What a script is handed

Every declared variable under its own name, answered or not, plus:

| | |
|---|---|
| `MODULE_DIR` | the module's folder, absolute |
| `MODULE_CONF` | its answer file |
| `MODULE_LOG` | its log |
| `RUNTIME_LANG` | the language showing |
| `RUNTIME_VERSION` | the runtime's version |

Scripts are **sourced** into a shell that already carries an `ERR` trap and,
where the module declares one, the shared library. They need no preamble, no
`set -e`, no imports, no error handling: if a command fails, the task fails, and
the user is told the file, the line, the command and the exit code. A script
that merely *ends* on a false test (`[ "$X" = true ] && do_it`) is not a
failure and is never reported as one — except in a `tty: true` task, which has
no wrapper around it and is its own exit status.

Scripts ask nothing and print nothing for a person to read. The single exception
is a `tty: true` task, which is a session somebody is sitting in front of rather
than a step.

## Translations

The source string is the key. A line of Go says `T("Back")` and a catalog
answers with `"Zurück"`; a catalog with nothing to say about it leaves the
English standing. So a half-finished translation is useful from its first line.

The catalogs are **gettext `.po` files**, one per language, filled in from a
`.pot` template beside them: the format every translation platform reads, and
the one where the msgid a translator is shown is the English sentence itself.
Both templates are generated and neither is edited by hand: the runtime's out of
the Go sources, a module's out of the loaded module. `make locales` writes them
and brings every catalog up to them.

Two independent catalogs are merged: the runtime's own, compiled into the binary
under `locales/`, and the module's own `locales/` beside its declaration. Adding
a language is adding a file.

```sh
cp locales/runtime.pot locales/fr.po  # a language nobody has started yet
make locales                          # every template, and every catalog brought up to it
runtime -check                        # reports coverage per language
```

A catalog names its own language in it, as the translation of `English`, that
is what the picker lists, so a language is always offered in its own words. See
[TRANSLATING.md](../TRANSLATING.md).

The language is the first page of every run, changed afterwards in the
settings, and it opens on whatever `runtime.conf` last recorded — or, on a
machine that has never said, on what `LC_ALL`, `LC_MESSAGES` or `LANG` comes
closest to.

**`language:`** ties it to one of a module's own answers as well. The value is
matched against the catalogs the way a machine's own locale is (`de_DE` is
German), so a module that asks where a machine is has also said which language
it speaks: answering it changes the words on screen, and the settings page shows
that row instead of a language row of its own.

## Building

```sh
make build                     # bin/runtime-linux-amd64, and its checksum
make run                       # straight from source, against the modules at ..
make run MODULE=recovery       # one of them outright
make check                     # gofmt, vet, staticcheck, test, build, before a commit
```

`run` reads the repository root, which is a `runtime.yaml` with the module
folders beside it exactly as a release is. `make build` at the repository root
assembles the real thing: `release/runtime`.

The binary is static and has no runtime dependencies of its own. It has to live
beside `runtime.yaml` and its modules, since that is where it looks for them.

## Layout

```
main.go              read the command line, load the runtime and its modules, open the interface
internal/spec        the runtime and its modules, read into memory, checked over and put in order
internal/store       the answers, and the file they survive a restart in
internal/exec        the only place a process is started, and the failure shape
internal/runner      what a question offers, which tasks this run consists of
internal/wlan        joining a wireless network, the way a module's hooks say to
internal/i18n        the message catalogs
internal/logging     the single sink for everything a run records
locales/             the runtime's own words, compiled in
tools/potgen/        reads every T("…") out of the sources and writes the template
tui/                 the interface: one frame, a stack of pages, no page draws its own
```
