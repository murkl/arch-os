# Arch OS Runtime

A single Go binary. It draws the interface, asks the questions, stores the answers and runs the shell scripts in order, reporting exactly where things went wrong if they do.

It installs nothing itself and knows nothing about Arch Linux, disks, packages or desktops. None of those words appear in the source.

- What the product is called and how it looks comes from `runtime.yaml`
- What it asks, what the answers mean and what shell it runs comes from one folder per module under `modules/`

```
runtime                      # asks the language, then which module to open
runtime installer            # opens that module directly, skipping the second question
runtime installer --debug    # the same run against nothing, changing no disk
runtime --version
```

**Note:** _Started without a `runtime.yaml` and a `modules/` folder beside it, the binary says so and stops._

## What sits beside the Binary

The binary looks next to itself, and nowhere else:

```
runtime                 the binary
runtime.yaml            what the product is called and what it looks like
modules/installer/      one module: installer.yaml and the folders beside it
modules/recovery/       another: recovery.yaml and its own
```

```
name: Arch OS            # shown on the pages drawn before a module is opened
accent: "#1793d1"        # the one colour the interface is built from
logo: |                  # everything above the blank line is a dim eyebrow
  Arch Linux

  ██████ …               # the wordmark, drawn in the accent colour
```

Three keys, holding only what no module can know about its neighbours. Which modules exist is not written down anywhere: they are the folders under `modules/`, in name order. Adding one is a folder, removing one is deleting it.

**Note:** _Nothing here is compiled in. A different name, a different colour and a different set of modules is a different product from the same binary._

## The Command Line

```
runtime [<module>] [--debug] [--version]
```

| Flag | Description |
| --- | --- |
| `--debug` | Pass `DEBUG=true` to every script |
| `--version` | Print the version and exit |

Those two words are the runtime's own. Everything else on the line names the module to open and whether a word names one depends on what is in `modules/` at that moment, which is what keeps the list of modules out of the binary.

- A module may be written as a bare word or with dashes: `runtime installer` and `runtime --installer` are the same request
- It may appear anywhere on the line
- A folder named after one of the two flags is refused at startup, since nothing could ever open it

`--debug` belongs to the runtime rather than to a module because it is the same switch in every one of them. Every script gets it as `DEBUG`, `true` or `false`, so a script guarding itself with `[ "$DEBUG" = true ]` is never testing an empty string.

**Note:** _Nothing else on the command line is treated as an answer. Questions are answered in the interface and stored in the answer file beside it._

## A Module

Only the declaration has to be there. Everything else is found by its own name, so a module turns a part of the program off by leaving it out.

```
<name>.yaml              the whole declaration: what it is, what it asks, what order it runs in
tasks/<id>/task.yaml     where that step belongs
tasks/<id>/task.sh       what it does
hooks/<name>.sh          everything around the work itself, one script per hook
lib.sh                   sourced before every script in this module
locales/<code>.po        one catalog per language, beside the template it is filled in from
```

The declaration is the one `.yaml` file at the top level of the folder, whatever it is called. Two `.yaml` files in one folder is refused rather than resolved.

The folder name is the module's identity: it is what the module picker keys on, what the command line names and what its answer file and log are called. The `installer` module writes `installer.conf` and `installer.log`.

### Order of the Pages

```
language → which module → its `first:` questions → network → preflight → presets → hub
```

The language is the runtime's own answer, not any module's. It is settled before there is a module to settle anything else, so even the question of which module to open is asked in it. It is stored in `runtime.conf` beside the modules' own answer files and passed into whichever module is opened, so every script knows what language is on screen.

**Note:** _Naming a module on the command line answers only the second question. The language page is always drawn._

### The Declaration

```
title: Arch OS Installer
description: Put Arch Linux on this machine.   # shown on the page that asks which module to open
run: Installation        # what one run of this module is called

language: ARCH_OS_LOCALE_LANG  # optional: ties the interface language to one of this module's answers

stages: [prepare, disk, base, finish]   # the order the work happens in

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

`confirm:` is filled in from the answers, so it names the actual disk rather than describing things in the abstract.

`description:` and `run:` are two different things and a module needs both once a runtime offers more than one:

- `description` is what the module **is**, shown on the page that asks which to open
- `run` is what one **run** of it is called, read out wherever the interface reports what is happening

**Note:** _A module that leaves `run` out defaults to "Installation", which is right for one kind of module and wrong for the rest._

### task.yaml

```
name: Install the graphics driver    # the line shown while the user waits
stage: desktop                       # one of the stages, which decides where this task runs
needs: [desktop-gnome]               # ordered after these, within the same stage
conditions:                          # every one must hold, or the task is skipped entirely
  - ARCH_OS_DESKTOP != none
  - ARCH_OS_DESKTOP_GRAPHICS_DRIVER != none
```

Seven more keys change what a task **is** rather than what it does:

| Key | Description |
| --- | --- |
| `asks: VAR` | The run pauses to ask for that value before this task runs |
| `confirm:` | Asked as a yes/no before it runs, declining skips it |
| `default: no` | That yes/no defaults to no instead of yes |
| `report:` | The run pauses on a page of its own once this task has finished |
| `shows: VAR` | Shows that answer on the page as a scannable code |
| `quits: true` | The program does not return after this task, a reboot |
| `tty: true` | The interface steps aside and hands the script the whole terminal |

**`asks:`** is for a value that cannot be known before the work has started, for example which snapshot to roll back to once the disk holding them is open. The question appears where the task list was, right before `confirm:`. The variable it names must have a fixed set of possible answers and must not be a secret.

**`report:`** marks a milestone a plain list of task names cannot express on its own: the work is done and everything after it is optional. The first paragraph is the headline and `{{VAR}}` is filled in from the answers.

**`shows:`** puts one answer on that page twice, large as a scannable code and printed underneath as plain text, for a value meant to be used on a different machine than the one displaying it. If the frame is not wide enough for a full code, it draws neither rather than one that will not scan.

The value is read back from the answer file once the task has run, which is also how the task stores it there in the first place:

```
printf "MY_LINK='%s'\n" "$url" >>"$MODULE_CONF"
```

**Note:** _Nothing lists the tasks anywhere. The folder is the list and their order comes from the stages and the `needs:` fields. A cycle, an unknown stage or a `needs:` pointing at nothing produces an error at startup._

### The Shape of a Question

Decided by the declaration, not by a separate switch:

| Declaration | What is drawn |
| --- | --- |
| nothing further | A text box |
| `values: [btrfs, ext4]` | A list |
| `command: timedatectl list-timezones` | A list, built from what the command printed |
| `type: bool` | Yes / No, in the interface's language |
| `type: secret` | A password field, asked twice, never written to disk |

The other fields:

| Field | Description |
| --- | --- |
| `default` | Any scalar: `true`, `8`, `pc105` |
| `prefill` | Shell that prints a suggested answer into the box |
| `apply` | Shell run when the answer takes effect |
| `first` | Asked before everything else |
| `blind` | Opens with the filter box already up, for a question asked before any keyboard layout is settled. Only meaningful together with `first` |
| `free` | Label of a text box under a list, for a value the list only suggests |
| `conditions` | See below |

**Note:** _`true` and `false` are shown as Yes and No wherever they appear, so `values: [auto, true, false]` is a boolean with a third option added._

A **secret** is the one required value that does not hold up the rest of the program while it is missing. It is never written to the answer file, so it is asked for right before the run that needs it, used and then forgotten.

**`apply`** is for an answer that changes the machine the Installer is running on, rather than the one being installed:

```
apply: loadkeys "$ARCH_OS_VCONSOLE_KEYMAP"
```

It runs the moment the answer is given and again at startup for an answer this run already had, so a restart picks up where the last one left off. A failure here is logged as a warning, the answer still stands.

**`first: true`** puts a question before everything else: before the network screen, before the preflight, before the presets. It is what lets a password be typed on a keyboard layout that has already been settled rather than guessed.

**Note:** _Use `first` sparingly. Every question marked `first` is asked before the check that decides whether this machine can be installed onto at all._

A command that provides options can return a value and its display text on one line, separated by a **tab**. Everything before the tab is stored, everything after it is shown:

```
lsblk -dn -o PATH,SIZE,MODEL | awk '{printf "%s\t%s  %s %s\n", $1, $1, $2, $3}'
# /dev/nvme0n1<TAB>/dev/nvme0n1  1.8T WD Black
```

**Note:** _An empty value before the tab is still a real answer ("no variant", "the default"), not a blank line to be ignored._

### Conditions

One condition, or a list where every one must hold:

```
VAR == value
VAR != value
```

This is deliberately not a full expression language. These three tokens cover every guard an Installer needs and they are checked against the declared variables when the module loads, so a renamed variable produces an error at startup rather than a task that silently never runs.

**Note:** _There is no `or`. A row that applies under two unrelated conditions is written as two rows._

### Shell Fields

`command:`, `prefill:` and `apply:` each accept either inline shell or a file. A single line starting with `./` or `../` names a file, anything else is the shell itself.

### Hooks

Bash scripts called by name. Nothing declares them: a script under one of these names **is** the declaration and any other file name under `hooks/` is rejected when the module loads.

| Hook | Description |
| --- | --- |
| `preflight.sh` | Can this machine be installed onto at all. A hard stop, run before everything except the `first` questions |
| `online.sh` | Is there internet. Without it the network screen never appears |
| `wlan-device.sh` | Which wireless device to use |
| `wlan-networks.sh` | The networks in range, one SSID per line |
| `wlan-connect.sh` | Join one, with `WLAN_DEVICE`, `WLAN_SSID` and `WLAN_PASSPHRASE` in the environment |
| `restart.sh` | Shut this machine down and start it again |
| `shutdown.sh` | Switch it off |

Whatever the preflight writes to stderr is what the user reads.

`restart.sh` and `shutdown.sh` turn leaving the interface into a choice rather than a plain exit. A module that defines them is saying the machine booted specifically to run it, so every way out lands on a page offering restart or shutdown. That page is drawn over whatever was happening: the run keeps going behind it, esc puts the page away again, and only choosing one of its rows actually stops anything.

**Note:** _A module with neither hook exits like any ordinary program, which is right for something started from a shell the user is still sitting in._

`console:` is the third way out and the only one that runs nothing: the program stops and the machine keeps running. Its value is the message printed once the interface is gone.

## What the Interface does

In this order, and each page appears only if it has something to show:

- **Language**, if more than one is available. The runtime's own question, before everything else. Afterwards it is a row in the settings
- **What to do**, if the runtime offers more than one module and none was named on the command line
- **The `first` questions**, unnumbered. The few that cannot wait, because everything typed afterwards depends on them
- **Network**, if the module defines an `online.sh` hook
- **The check**, if the module defines a `preflight.sh` hook. A failure here is a hard stop
- **Presets**, one page per preset the module declares. A preset is a set of answers, not a mode the program stays in. It is offered once, on a machine that has answered nothing yet
- **The questions** that are required, meaningful and still unanswered. One per page, numbered, in declaration order
- **Install** or **Settings**, once nothing is left to answer
- **Settings**: every answer on one page with its current value. `/` filters by name or heading
- **Installing**: a list of tasks filling in from the top and nothing else. Not a single line of what any script printed, all of that goes to the log
- **A failure**: what the tool reported, then which script, which line, which command, which exit code and where the rest is logged
- **The way out**, wherever the module defines one: restart, shutdown, or closing the interface with the machine left running

Four keys, each with one meaning, on every page of every module:

| Key | Meaning |
| --- | --- |
| `enter` | Confirm |
| `esc`, `backspace` | Back |
| `q`, `ctrl+c` | Ask to leave |

Backspace deletes a character while there is one to delete and a filter box closes before the page holding it does. Backing off the very first page is the same as asking to leave, and so is pressing esc during a run.

**Note:** _Arrow keys only move a cursor, since an arrow key is also what a mouse wheel sends. Every answer is written to the answer file the moment it is given, so an interruption never loses anything._

## Files it writes

Beside wherever the program was started, never inside a module, and named after the module, so two modules started from the same folder do not collide:

```
./runtime.conf     what the runtime keeps across every module: the language
./installer.conf   every answer, as KEY='value': plain shell, editable by hand
./installer.log    everything: the runtime's own progress plus every line a script printed
```

**Note:** _That is the `installer` module's pair. `recovery` writes its own `recovery.conf` and `recovery.log` alongside it._

## What a Script receives

Every declared variable under its own name, answered or not, plus:

| Variable | Description |
| --- | --- |
| `MODULE_DIR` | The module's folder, as an absolute path |
| `MODULE_CONF` | Its answer file |
| `MODULE_LOG` | Its log |
| `RUNTIME_LANG` | The language currently shown |
| `RUNTIME_VERSION` | The runtime's version |
| `DEBUG` | Whether this run is only simulating, see `--debug` |

Scripts are **sourced** into a shell that already has an `ERR` trap and, if the module declares one, the shared library. They need no preamble: no `set -e`, no imports, no error handling. If a command fails, the task fails and the user is shown the file, the line, the command and the exit code.

**Note:** _A script that simply ends because of a false test (`[ "$X" = true ] && do_it`) is not treated as a failure, except in a `tty: true` task, which has no wrapper around it and reports its own exit status directly._

Scripts never ask questions and never print anything meant for a person to read. The one exception is a `tty: true` task, which is an interactive session the user sits in front of rather than a step in a list.

## Translations

The source string is the key. A line of Go says `T("Back")` and a catalog answers with `"Zurück"`. A catalog with nothing to say about that string leaves the English as it is, which is what makes a half-finished translation useful from its first line.

Two catalogs are merged: the runtime's own, compiled into the binary under `locales/`, and the module's own beside its declaration. Adding a language means adding a file.

```
cp locales/runtime.pot locales/fr.po            # a language nobody has started yet
make locales                                    # regenerate every template, update every catalog
go run ./tools/inspect -dir ../.dev installer   # translation coverage per language
```

A catalog names its own language as the translation of `English` and that is what the language picker lists, so a language is always shown in its own words.

The language is chosen on the first page of every run and can be changed afterwards in the settings. It opens on whatever `runtime.conf` last recorded, or on whatever `LC_ALL`, `LC_MESSAGES` or `LANG` comes closest to.

**`language:`** ties the interface language to one of a module's own answers. The value is matched against the catalogs the same way a machine's own locale would be (`de_DE` is German), so a module that asks where a machine is has effectively also asked which language it speaks.

**[➜ See Translating](../TRANSLATING.md)**

## Building

```
make build                     # bin/runtime-linux-amd64, plus its checksum
make run                       # straight from source, against the modules in ../modules
make run MODULE=recovery       # opens one module directly
make run MODULE=installer ARGS=--debug   # plus any extra flags that run needs
make check                     # gofmt, vet, staticcheck, test, build
```

`run` builds into `../.dev`, which `make dev` at the repository root lays out the way a release is laid out (a `runtime.yaml` with a modules folder beside it) but from symlinks into the tree instead of copies. Answers and logs land there too.

**Note:** _The binary is static and has no runtime dependencies of its own. It does need to sit beside `runtime.yaml` and its modules folder, since that is where it looks for them._

## What is where

```
main.go              reads the command line, loads the runtime and its modules, opens the interface
internal/spec        the runtime and its modules, loaded into memory, validated and ordered
internal/store       the answers, and the file they are stored in across restarts
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
