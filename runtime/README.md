# runtime: the program that runs the modules beside it

A single Go binary that draws the interface, asks questions, stores the
answers, and runs shell scripts in order — reporting exactly where things
went wrong if they do. It builds as `runtime-linux-amd64`, and a release
ships it alongside its modules as `runtime`.

It installs nothing itself and knows nothing about Arch Linux, disks,
packages or desktops — none of those words appear in the source. What the
product is called and how it looks comes from `runtime.yaml`; what it asks,
what the answers mean, and what shell it runs comes from **one folder per
module**, under `modules/`. Started without them, the binary says so and
stops.

```
runtime                       # asks the language, then which module to open
runtime --installer           # opens that module directly, skipping the question
runtime --installer --debug   # the same run against nothing, changing no disk
runtime --version
```

`--debug` and `--version` are the only flags built into the runtime itself.
Everything else on the command line names a module to open — see
[The command line](#the-command-line) below.

## The runtime

The binary looks **next to itself**, and nowhere else, for `runtime.yaml` and
the modules folder:

```
runtime                 the binary
runtime.yaml            what the product is called and what it looks like
modules/installer/      one module: installer.yaml and the folders beside it
modules/recovery/       another: recovery.yaml and its own
```

```yaml
name: Arch OS            # shown on the pages drawn before a module is opened
accent: "#1793d1"        # the one colour the interface is built from
logo: |                  # everything above the blank line is a dim eyebrow
  Arch Linux

  ██████ …               # the wordmark, drawn in the accent colour
```

That's the whole of it: three keys, holding only what no module can know
about its neighbours.

Which modules exist is not written down anywhere — it's just the folders
under `modules/`, listed in name order. Adding one is a folder; removing one
is deleting it. Nothing in the binary and nothing in `runtime.yaml` knows any
module by name. The folder name is also the word that opens it directly:
`runtime --installer` is what the `installer` and `recovery` commands on the
ISO actually run.

Nothing here is compiled in. A different name, a different colour and a
different set of modules is a different product built from the same binary.

## A module

Only the declaration file has to be there; everything else is found by its
own name, so a module can turn a part of the program off simply by leaving
it out.

```
<name>.yaml              the whole declaration: what it is, what it asks, what order it runs in
tasks/<id>/task.yaml     where that step belongs
tasks/<id>/task.sh       what it does
hooks/<name>.sh          everything around the work itself, one script per hook
lib.sh                   sourced before every script in this module
locales/<code>.po        one catalog per language, beside the template it's filled in from
```

The declaration is **the one `.yaml` file at the top level of the folder**,
whatever it's called — `installer.yaml`, `recovery.yaml`. Naming it after the
folder is the convention, and it's what makes two modules easy to tell apart
when both are open in an editor. Two `.yaml` files in one folder is refused
rather than resolved.

The **folder name is the module's identity**: it's what the module-picker
page keys on, what the command line names, and what its answer file and log
are called. The `installer` module writes its answers to `installer.conf`
and its log to `installer.log`.

### Order of the pages

The language comes first, then the module, then everything that module needs
settled:

```
language → which module → its `first:` questions → network → preflight → presets → hub
```

The language is the runtime's own answer, not any module's — it's settled
before there's a module to settle anything else. Even the question of which
module to open is asked in it, and every module afterwards is read in it too.
It's stored in `runtime.conf` beside the modules' own answer files, and
passed into whichever module is opened so every script it runs knows what
language is on screen. A module can still tie the language to one of its own
answers (`language:`, below) and change it from there.

Naming a module on the command line answers only the second question, never
the first — the language page is always drawn.

### The declaration

```yaml
title: Arch OS Installer
description: Put Arch Linux on this machine.   # shown on the page that asks which module to open
run: Installation        # what one run of this module is called

language: ARCH_OS_LOCALE_LANG # optional: ties the interface language to one of this module's answers

stages: [prepare, disk, base, finish]   # the order installation happens in

confirm: |               # the last thing shown before anything changes
  Arch Linux will be installed on {{ARCH_OS_DISK}}.

console: Type installer to start it again.   # optional: shown on the way out

presets:                 # pages of starting points, offered on a machine with no answers yet
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
        title: Online                    # a starting point that is fetched, not written out here
        description: Take the answers from a configuration somebody shared.
        asks: ARCH_OS_CONFIG_SOURCE      # the one question this row asks
        apply: ./tasks/share/import.sh   # shell that turns that answer into more answers

variables:
  - name: ARCH_OS_USERNAME     # reaches every script as an environment variable
    title: User name
    description: |             # shown on the page that asks it
      The account you will log in with.
    group: Identity            # the heading this row and the ones after it sit under
    required: true             # required and unanswered is what makes the runtime ask
    pattern: '^[a-z_][a-z0-9_-]*$'
    error: Lower case letters, digits, - and _ only.

  - name: ARCH_OS_PASSWORD
    title: Password
    type: secret               # asked right before the run starts, never written to disk
    required: true
```

`confirm` is filled in from the answers, so it names the actual disk rather
than describing things in the abstract.

`description` and `run` are two different things, and a module needs both
once a runtime offers more than one module: `description` is what the module
*is*, shown on the page that asks which to open; `run` is what one *run* of
it is called, read out wherever the interface reports what's happening — the
row that starts it, the final warning, the clock while it runs. A module
that leaves `run` out defaults to "Installation", which is right for one
kind of module and wrong for the rest.

### The command line

The runtime itself owns exactly two flags:

```
runtime [<module>] [--debug] [--version]
```

Everything else on the line names the module to open. Whether a given word
names one depends on what's in `modules/` at that moment, which is what keeps
the list of modules out of the binary: adding a module is a folder, and it
becomes openable by name right away. It can be given as a bare word or with
the dashes an option would have — `runtime installer` and `runtime
--installer` are the same request — and it can appear anywhere on the line.
A folder named after one of the runtime's own two flags is refused at
startup, since nothing could ever open it.

| | |
|---|---|
| `--debug` | pass `DEBUG=true` to every script |
| `--version` | print the version and exit |

**`--debug`** belongs to the runtime rather than to a module because it's the
same switch in every one of them. It's passed to every script as `DEBUG`,
`true` or `false`, alongside the module's own answers — so a script guarding
itself with `[ "$DEBUG" = true ]` is never testing an empty string, and a
module may not declare a variable with that name.

Nothing else on the command line is treated as an answer. Questions are
answered in the interface and stored in the answer file beside it; a variable
inherited from whatever shell started a run is as often an accident as an
instruction, so what a script receives is decided here, deliberately.

### `hooks/`

Bash scripts called by name. Nothing declares them: a script under one of
these names *is* the declaration, and any other file name under `hooks/` is
rejected when the module loads.

| | |
|---|---|
| `preflight.sh` | can this machine be installed onto at all — a hard stop, run before everything except the `first` questions |
| `online.sh` | is there internet; without it, the network screen never appears |
| `wlan-device.sh` | which wireless device to use |
| `wlan-networks.sh` | the networks in range, one SSID per line |
| `wlan-connect.sh` | join one, with `WLAN_DEVICE`, `WLAN_SSID` and `WLAN_PASSPHRASE` in the environment |
| `restart.sh` | shut this machine down and start it again |
| `shutdown.sh` | switch it off |

The preflight is a hard stop: whatever it writes to stderr is what the user
reads.

`restart.sh` and `shutdown.sh` are what turn leaving the interface into a
choice rather than a plain exit. A module that defines them is saying the
machine booted specifically to run it, so every way out — q or ctrl+c from
anywhere, esc during a run, backing off the first page, the end of an
installation — lands on a page offering restart or shutdown. That page is
drawn *over* whatever was happening: a run keeps going behind it and the
header keeps counting, esc puts the page away again and leaves what was
underneath untouched, and only choosing one of its rows actually stops
anything. A module with neither hook exits like any ordinary program, which
is right for something started from a shell the user is still sitting in.

**`console:`** is the third way out, and the only one that runs nothing: the
program stops and the machine keeps running. Declare it when there's
something behind the interface worth returning to — its value is the message
printed once the interface is gone.

### `task.yaml`

```yaml
name: Install the graphics driver    # the line shown while the user waits
stage: desktop                       # one of the stages, which decides where this task runs
needs: [desktop-gnome]               # ordered after these, within the same stage
conditions:                          # every one must hold, or the task is skipped entirely
  - ARCH_OS_DESKTOP != none
  - ARCH_OS_DESKTOP_GRAPHICS_DRIVER != none
```

Seven more keys change what a task *is* rather than what it does:

| | |
|---|---|
| `asks: VAR` | the run pauses to ask for that value before this task runs |
| `confirm:` | asked as a yes/no before it runs; declining skips it |
| `default: no` | that yes/no defaults to no instead of yes |
| `report:` | the run pauses on a page of its own once this task has finished |
| `shows: VAR` | shows that answer on the page as a scannable code |
| `quits: true` | the program doesn't return after this task — a reboot |
| `tty: true` | the interface steps aside and hands the script the whole terminal |

**`asks:`** is for a value that can't be known before the work has started —
for example, which snapshot to roll back to, once the disk holding them is
open. The question appears where the task list was, right before `confirm:`,
so a confirmation can refer to what was just chosen. The variable it names
must have a fixed set of possible answers, never a secret. Being named by a
task is the whole declaration: the value is left out of the initial questions
and off the settings page, and it's asked fresh every time.

**`report:`** marks a milestone that a plain list of task names can't
express on its own: the work is done, and everything after it is optional.
The first paragraph is the headline, and `{{VAR}}` is filled in from the
answers.

**`shows:`** puts one answer on that page twice: large, as a scannable code,
and printed underneath as plain text, for a value that's meant to be used on
a different machine than the one displaying it. If the frame isn't wide
enough for a full code, it draws neither rather than one that won't scan.

The value is read back from the answer file once the task has run — which is
also how the task stores it there in the first place:

```sh
printf "MY_LINK='%s'\n" "$url" >>"$MODULE_CONF"
```

That file is the only channel, and it's not a special one: it's plain shell,
`KEY='value'` per line. An empty value isn't treated as a failure — the page
just shows its text and no code.

Nothing lists the tasks anywhere: the folder is the list, and their order
comes from the stages and the `needs:` fields. A cycle, an unknown stage, or
a `needs:` pointing at nothing produces an error at startup rather than an
installation that stops halfway through.

### The shape of a question

Decided by the declaration, not by a separate switch:

| declaration | what's drawn |
|---|---|
| nothing further | a text box |
| `values: [btrfs, ext4]` | a list |
| `command: timedatectl list-timezones` | a list, built from what the command printed |
| `type: bool` | Yes / No, in the interface's language |
| `type: secret` | a password field, asked twice, never written to disk |

Other fields: `default` (any scalar — `true`, `8`, `pc105`), `prefill`
(shell that prints a suggested answer), `apply` (shell run when the answer
takes effect), `first` (asked before everything else), `free` (a row under a
list that opens a free-text box), `flag` (how to answer it from the command
line), and `conditions`.

`true` and `false` are shown as Yes and No wherever they appear, so
`values: [auto, true, false]` is a boolean with a third option added.

A **secret** is the one required value that doesn't hold up the rest of the
program while it's missing. It's never written to the answer file, so it
would appear unanswered on every start; instead it's asked for right before
the run that needs it, used, and then forgotten — or supplied through its
`flag:`, which is the only way an unattended run can provide one.

**`apply`** is for an answer that changes the machine the installer is
running on, rather than the one being installed:

```yaml
apply: loadkeys "$ARCH_OS_VCONSOLE_KEYMAP"
```

It runs the moment the answer is given, and once again at startup for an
answer this run already had, so a restart picks up where the last one left
off. A failure here is logged as a warning; the answer still stands.

**`first: true`** puts a question before everything else — before the
network screen, before the preflight, before the presets. It's what lets a
password be typed on a keyboard layout that's already been settled rather
than guessed, and it's meant to be used sparingly: every question marked
`first` is asked before the check that decides whether this machine can be
installed onto at all.

A command that provides options can return a value and its display text on
one line, separated by a **tab**: everything before the tab is stored,
everything after it is shown:

```sh
lsblk -dn -o PATH,SIZE,MODEL | awk '{printf "%s\t%s  %s %s\n", $1, $1, $2, $3}'
# /dev/nvme0n1<TAB>/dev/nvme0n1  1.8T WD Black
```

An empty value before the tab is still a real answer ("no variant", "the
default") — not a blank line to be ignored.

### `conditions`

One condition, or a list where every one must hold:

```
VAR == value
VAR != value
```

This is deliberately not a full expression language. These three tokens
cover every guard an installer needs, they read like a sentence, and they're
checked against the declared variables when the module loads — so a renamed
variable produces an error at startup, never a task that silently never
runs. There's no `or`: a row that applies under two unrelated conditions is
written as two rows.

### Shell fields

`command:`, `prefill:` and `apply:` each accept either inline shell or a
file: a single line starting with `./` or `../` names a file, anything else
is treated as the shell itself. That way a short option list stays right in
the YAML next to its variable, and a longer one moves into its own file.

## What the interface does

In this order, and each page appears only if it has something to show:

- **Language**, if more than one is available. This is the runtime's own
  question and comes before everything else, including the one below. It's
  a row in the settings afterwards.
- **What to do**, if the runtime offers more than one module and none was
  named on the command line. Everything after this belongs to whichever
  module was chosen.
- **The `first` questions**, unnumbered — the few that can't wait, because
  everything typed afterwards depends on them.
- **Network**, if the module defines an `online.sh` hook.
- **The check**, if the module defines a `preflight.sh` hook. A failure here
  is a hard stop.
- **Presets**, one page per preset the module declares. A preset is a set of
  answers, not a mode the program stays in — every value it fills in is an
  ordinary answer from the next page on. It's offered once, on a machine
  that hasn't answered anything yet. A preset row with **`asks:`** achieves
  the same thing a different way: one question, whose answer is turned into
  more answers by the shell in its **`apply:`**, written straight into the
  answer file. The row isn't complete until that has run successfully.
- **The questions** that are required, meaningful, and still unanswered —
  one per page, numbered, in declaration order.
- **Install** or **Settings**, once nothing is left to answer.
- **Settings**: every answer on one page, with its current value. `/`
  filters by name or by heading.
- **Installing**: a list of tasks, filling in from the top, and nothing
  else. Not a single line of what any script printed — a package manager's
  progress bars are just noise full of escape codes, and all of that goes to
  the log instead. A task with `asks:` pauses the list to ask its question; a
  declined one keeps its row, marked as skipped. A task with `report:`
  pauses the list to show its own page.
- **A failure**: what the tool reported, then which script, which line,
  which command, which exit code, and where the rest is logged.
- **The way out**, wherever the module defines one: restart, shutdown, or —
  if the module names a console to return to — closing the interface with
  the machine left running. Opening this page never stops a run by itself;
  choosing a row does.

Four keys, each with one meaning, on every page of every module: **enter**
confirms, **esc** and **backspace** go back, and **q** and **ctrl+c** ask to
leave. Backspace deletes a character while there's one to delete, and a
filter box closes before the page holding it does. Backing off the very
first page is the same as asking to leave, and so is pressing esc during a
run — the work in progress, and any questions it's paused on, have nothing
behind them to go back to. Arrow keys only move a cursor, nothing else,
since an arrow key is also what a mouse wheel sends.

Every answer is written to the answer file the moment it's given, so an
interruption never loses anything.

## Files it writes

Written beside wherever the program was started (never inside a module,
which might be read-only or a git checkout), and named after the module, so
two modules started from the same folder don't collide:

```
./runtime.conf     what the runtime keeps across every module: the language
./installer.conf   every answer, as KEY='value': plain shell, editable by hand
./installer.log    everything: the runtime's own progress plus every line a script printed
```

That's the `installer` module's pair; `recovery` writes its own
`recovery.conf` and `recovery.log` alongside it.

## What a script receives

Every declared variable, under its own name, whether answered or not, plus:

| | |
|---|---|
| `MODULE_DIR` | the module's folder, as an absolute path |
| `MODULE_CONF` | its answer file |
| `MODULE_LOG` | its log |
| `RUNTIME_LANG` | the language currently shown |
| `RUNTIME_VERSION` | the runtime's version |
| `DEBUG` | whether this run is only simulating — see `--debug` |

Scripts are **sourced** into a shell that already has an `ERR` trap and, if
the module declares one, the shared library. They need no preamble — no
`set -e`, no imports, no error handling: if a command fails, the task fails,
and the user is shown the file, the line, the command and the exit code. A
script that simply *ends* because of a false test (`[ "$X" = true ] &&
do_it`) is not treated as a failure — except in a `tty: true` task, which has
no wrapper around it and reports its own exit status directly.

Scripts never ask questions or print anything meant for a person to read.
The one exception is a `tty: true` task, which is an interactive session the
user sits in front of, not a step in a list.

## Translations

The source string is the key. A line of Go says `T("Back")`, and a catalog
answers with `"Zurück"`; a catalog with nothing to say about that string
leaves the English text as it is. That's what makes a half-finished
translation useful from its very first line.

The catalogs are **gettext `.po` files**, one per language, filled in from a
`.pot` template beside them — the format every translation platform reads,
where the msgid shown to a translator is the English sentence itself. Both
templates are generated, never hand-edited: the runtime's from the Go
sources, a module's from the loaded module. `make locales` writes them and
brings every catalog up to date against them.

Two independent catalogs are merged: the runtime's own, compiled into the
binary under `locales/`, and the module's own `locales/` beside its
declaration. Adding a language means adding a file.

```sh
cp locales/runtime.pot locales/fr.po  # a language nobody has started yet
make locales                          # regenerates every template and updates every catalog
go run ./tools/inspect -dir ../.dev installer   # reports translation coverage per language
```

A catalog names its own language as the translation of `English`, and that's
what the language picker lists — so a language is always shown in its own
words. See [TRANSLATING.md](../TRANSLATING.md).

The language is chosen on the first page of every run, and can be changed
afterwards in the settings. It opens on whatever `runtime.conf` last
recorded, or, on a machine that's never said, on whatever `LC_ALL`,
`LC_MESSAGES` or `LANG` comes closest to.

**`language:`** additionally ties the interface language to one of a
module's own answers. The value is matched against the catalogs the same way
a machine's own locale would be (`de_DE` is German), so a module that asks
where a machine is has effectively also asked which language it speaks:
answering that question changes the language on screen, and the settings
page shows that row instead of a separate language row.

## Building

```sh
make build                     # bin/runtime-linux-amd64, plus its checksum
make run                       # straight from source, against the modules in ../modules
make run MODULE=recovery       # opens one module directly
make run MODULE=installer ARGS=--debug   # plus any extra flags that run needs
make check                     # gofmt, vet, staticcheck, test, build — run this before a commit
```

`run` builds into `../.dev`, which `make dev` at the repository root lays
out the way a release is laid out — a `runtime.yaml` with a modules folder
beside it — but built from symlinks into the tree instead of copies. The
binary looks for both beside itself, so that folder is where it finds them,
reading straight from the sources rather than a copy. Answers and logs land
there too. `make build` at the repository root assembles the real thing:
`release/runtime`.

The binary is static and has no runtime dependencies of its own. It does
need to sit beside `runtime.yaml` and its modules folder, since that's where
it looks for them.

## Layout

```
main.go              reads the command line, loads the runtime and its modules, opens the interface
internal/spec        the runtime and its modules, loaded into memory, validated and ordered
internal/store       the answers, and the file they're stored in across restarts
internal/exec        the only place a process is started, and how failures are represented
internal/runner      what each question offers, and which tasks make up this run
internal/wlan        joining a wireless network, the way a module's hooks describe
internal/i18n        the message catalogs
internal/logging     the single sink for everything a run records
locales/             the runtime's own strings, compiled in
tools/potgen/        reads every T("…") out of the sources and writes the template
tools/inspect/       loads a folder of modules and reports what it holds, or writes its template
tui/                 the interface: one frame, a stack of pages, no page draws itself directly
```
