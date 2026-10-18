# Arch OS Runtime

The program behind the Installer and the Recovery. It draws the pages, asks the questions, keeps the answers and runs the scripts. Everything it shows and does is declared in YAML and written in bash beside it, and all of it is compiled into one binary. Another Arch distribution swaps the YAML and the scripts and keeps the runtime.

```
arch-os <module> [--dry-run] [--kiosk]
arch-os glyphs
arch-os --version
```

| Argument | Meaning |
| --- | --- |
| `<module>` | The module to open: a folder beside `runtime/` with a `module.yaml`, so `installer` or `recovery` |
| `--dry-run` | Shows the run without doing it, see [Dry Run](#dry-run) |
| `--kiosk` | The machine is only this: leaving starts it again, with every answer kept |
| `glyphs` | Every character the interface draws on a console, for **[iso/glyphs.sh](../iso/glyphs.sh)** |

```
cargo build --release   # the program, with every module inside it
cargo test              # every module loaded as a run loads it, every catalog held to every text
```

## The Product

```
product.yaml        the product: its name, colour and wordmark
lib.sh              the one library every script gets
locales/<code>.po   one catalog per language
<module>/           one folder per module
runtime/            this program
```

The build embeds everything but `runtime/` into the binary, so the binary is the whole program. At start it writes the scripts to `$XDG_RUNTIME_DIR/arch-os-<pid>/` and runs them there.

### `product.yaml`

```yaml
title: Arch OS
accent: "#1793d1"
console-accent: bright-blue
surface: "#3b4252"
console-surface: blue
status:
  check: check_online()
  pass: Online
  fail: Offline
logo: |
  Arch Linux

   █████  ██████   ██████ ██   ██      ██████  ███████
```

| Key | Description |
| --- | --- |
| `title` | The product's name, first in the trail over every page |
| `accent` | `#rrggbb`, the one colour the interface is built from |
| `console-accent` | The slot that colour takes on a console of sixteen colours, see [The Console](#the-console) |
| `surface` | `#rrggbb`, behind the row under the cursor. Dark grey without it |
| `console-surface` | Its slot on a console: one of the first eight colours, which are all a console draws text on. Blue without it |
| `status` | One line about the machine in the header. `check` is a function of `lib.sh`: exit 0 shows `pass`, anything else `fail`. Read every `every` seconds, default 10, and right after an action ran |
| `logo` | The wordmark, drawn on the way in. Above the first blank line a dim eyebrow |

### `lib.sh`

The one place scripts share code. Loaded in front of every task, test and action, and of every function the YAML calls. It defines functions and exports constants, and works nothing out while it loads.

### Shell in the YAML

A key that runs shell names it, in one of two forms:

| Form | Runs |
| --- | --- |
| `name()` | That function of `lib.sh`. Refused at startup where `lib.sh` has none by that name |
| `./file.sh` | That file, relative to the folder of the YAML |

Shell written into the YAML itself is refused: every line lives where a linter reads it and a failure can point at it. The keys are `check` of the status, and `options-from`, `value-from`, `prefill`, `apply` and `check` of a setting. A function is named after the key that calls it: `options_disks()`, `prefill_timezone()`, `apply_timezone()`, `value_virtual_machine()`, `check_online()`.

## A Module

| Path | Description |
| --- | --- |
| `module.yaml` | What it is, asks and does |
| `tasks/<stage>/<task>/task.yaml` | A task |
| `tasks/<stage>/<task>/task.sh` | Its work |
| `tasks/<stage>/<task>/test.sh` | Optional: how to tell it took |
| `actions/<action>/action.yaml` | An action |
| `actions/<action>/action.sh` | Its work |

The folder name is the module's identity: `arch-os recovery` opens it, and it writes `recovery.conf` and `recovery.log`.

### `module.yaml`

```yaml
title: Installer
start: Install now
confirm: |
  Install Arch OS on {{ARCH_OS_DISK}}?

  Everything on the disk is erased.
requires: [live-image, root, internet]
on:
  dashboard: [wifi]
  leave: [restart, shutdown]
  failure: [share-log]
  success: [chroot]
errors:
  3: |
    No internet connection

    Connect this machine and choose Install now again.
stages: [prepare, system, finish]
presets: …
settings: …
```

| Key | Description |
| --- | --- |
| `title` | **Required.** The module's name, in the trail over every page |
| `start` | **Required.** The first row of the dashboard, which starts the work |
| `confirm` | A question asked after every password and before the work, opening on No. The first paragraph is the headline |
| `requires` | Actions checked before anything is asked, in this order. The first no stands a page in front of everything and is asked again every few seconds. Skipped on a dry run |
| `on` | Where its other actions are offered, see [Actions](#actions) |
| `errors` | What a status means that any of its scripts stops itself with, see [Stopping on Purpose](#stopping-on-purpose) |
| `stages` | **Required.** The phases of the work, in order. Each is a folder `tasks/<stage>/` |
| `presets` | Starting points, see [Presets](#presets) |
| `settings` | The questions, see [Settings](#settings) |

### The Way In

1. The wordmark, then the language, unless the answer file keeps one
2. Every setting marked `first`
3. The actions under `requires`
4. The presets, on a machine that has answered nothing yet
5. Every required setting without an answer, one page each, counted in the header
6. The dashboard

### The Dashboard

The module's home. `start` on top, then every answer under its group heading, each a row that opens its question. Under them the interface language, the actions under `on: dashboard` and **Reset all answers**, which deletes the answer file after a question that opens on No. `f` narrows the rows.

`start` asks what is still missing, then every password, then `confirm`, then runs the tasks: each a row, checked off as it ends, counted in the header. A task that `asks` or has a `confirm` stops the run on its page. The run ends on a page that says how it went. Under a run that finished, the actions under `on: success` and **Continue**. Under a run that failed, what failed and where, the actions under `on: failure`, and **Back to the dashboard**, asked first.

`q` or `esc` on the dashboard leaves. A module with `on: leave`, or a kiosk, gets a page first: the actions under `on: leave`, then **Exit**, or in a kiosk **Start over**. During a run the same page says that every choice stops it.

## Settings

One entry under `settings:` is one question and one environment variable.

```yaml
settings:
  - name: ARCH_OS_DISK
    type: list
    title: Disk
    description: Everything on it is erased.
    group: Storage
    required: true
    options-from: options_disks()
    pattern: '^/dev/'
    error: Choose a disk that exists.
```

Every setting names its type, and the type decides how it is drawn and which keys mean anything for it:

| `type` | Drawn as | Takes |
| --- | --- | --- |
| `text` | A text box | `default`, `prefill`, `pattern`, `value-from` |
| `bool` | Yes or No | `default`, `value-from` |
| `list` | A list | `options` or `options-from`, `default`, `prefill`, `pattern`, `filter` |
| `open-list` | A list, and a row for an answer of one's own | `options` or `options-from`, `default`, `prefill`, `pattern`, `filter` |
| `password` | A password that exists already, typed once | `check` |
| `new-password` | A password being chosen, typed twice | |

| Key | Description |
| --- | --- |
| `name` | **Required.** The variable a script reads. `MODULE_` and `DRY_RUN` are the runtime's |
| `type` | **Required.** One of the types above |
| `title` | **Required.** The question, and its row on the dashboard |
| `description` | What the value is for |
| `group` | Its heading on the dashboard |
| `required` | Required and unanswered is what makes the runtime ask |
| `default` | The answer to start from: `true`, `auto`, `pc105` |
| `options` | The answers, written out |
| `options-from` | Shell that prints the answers, one a line. `value<TAB>label` stores the value and shows the label |
| `value-from` | Shell that prints the value instead of asking. Never asked, never on the dashboard, never stored |
| `prefill` | Shell that prints a suggestion. Still asked |
| `apply` | Shell run as the answer takes effect on this machine, such as a keymap |
| `check` | Shell that tries a `password` before it is taken |
| `first` | Asked before everything else, `requires` included, with the list's box open |
| `filter` | The list's narrowing box: `collapsed`, behind `f`, or `open` |
| `pattern` | A regular expression the answer must match |
| `error` | What a wrong answer is told |
| `when` | When it is asked, see [Conditions](#conditions) |

- `true` and `false` read as Yes and No
- A password is asked right before the run, used and forgotten
- `value-from` is read when the module opens and whenever an answer changes
- An answer from `options-from` is held to its list again when the work is started, before any password. One the list no longer prints is asked again
- An answer read from the file goes through `pattern` and the list like one typed. One that fails is asked again

**Note:** _A key its type does not take is refused at startup, and so is `value-from` together with `prefill` or `first`, and a password with `first`._

### Conditions

```yaml
when:
  - ARCH_OS_DESKTOP != none
  - ARCH_OS_FLATPAK_ENABLED == true
```

`VAR == value` and `VAR != value`, one or several, and every one must hold. There is no `or`: a row for two unrelated conditions is two rows. A name no setting answers is refused at startup.

### Placeholders

`{{VAR}}` is filled in from the answers in every `confirm`, `report`, `error` and `errors`. A name the module does not declare is refused at startup, and a translation that drops or adds one fails the tests.

## Presets

Starting points, offered once on a machine that has answered nothing. A preset is a set of answers, not a mode.

```yaml
presets:
  - title: Desktop
    description: The Core with GNOME.
    values:
      ARCH_OS_DESKTOP: gnome

  - title: Online (paste.rs)
    description: Every answer of a shared configuration.
    action: import-config
```

A preset writes its answers under `values` or names the action that fetches them, never both. The action's script appends them to `MODULE_CONF`.

## Tasks

A folder under its stage: `tasks/<stage>/<task>/`. The stage is a **when**, the folder in it a **what**.

```yaml
title: Install the graphics drivers
needs: [gnome]
when: ARCH_OS_DESKTOP != none
```

| Key | Description |
| --- | --- |
| `title` | **Required.** Its row in the run |
| `needs` | Tasks of its own stage it runs after |
| `when` | Every condition must hold, or it is left out of the run |
| `asks` | A question the run stops for first: `name`, `title`, `description`, `filter` and `options` or `options-from`, read once the run reaches it. A list that comes back empty skips the task. Never stored |
| `confirm` | A yes or no before it runs, opening on No. No skips it |
| `yes-after` | Tasks before it: where one of them ran in this run, `confirm` opens on Yes |
| `report` | A page the run stops on afterwards. The first paragraph is the headline |
| `progress` | `true`: the last line it printed is shown under it while it runs |
| `simulates` | `true`: runs on a dry run too, reading `DRY_RUN` itself |
| `allow-failure` | `true`: its failure does not stop the run |
| `errors` | What a status means that its `task.sh` stops itself with, see [Stopping on Purpose](#stopping-on-purpose) |

- A task runs after every task of an earlier stage, and within its stage after its `needs`
- A `needs` into another stage, an unknown name and a cycle are refused
- A folder under `tasks/` that is no declared stage is refused

### Tests

A `test.sh` beside `task.sh` runs right after the task, on the machine it worked on. It reads and changes nothing, and its exit status is the answer.

- A failed test does not stop the run
- The page the run ends on counts them: `38 of 40 tests passed`
- Where a test or an `allow-failure` task failed, that page offers **Test results**: the list, each row opening the file, the line, the command and what it said

## Actions

A script a module runs outside its work: `actions/<action>/action.yaml` and `action.sh`. The YAML says how it behaves, the script only does it: exit 0 is yes.

```yaml
title: Configure Wi-Fi
description: Joins a wireless network.
requires: [wifi-card, no-cable]
on:
  failure: [wifi-passphrase]
inputs:
  - name: ARCH_OS_WIFI_SSID
    type: list
    title: Network
    required: true
    options-from: options_wifi_networks()
```

| Key | Description |
| --- | --- |
| `title` | **Required.** Its row, and the heading over its page |
| `description` | The sentence under its row. Choosing the row is the consent, so it says what leaves the machine |
| `error` | What a no means. **Required** under a module's `requires` |
| `requires` | Actions that have to say yes before this one is offered |
| `on: failure` | The first of these this machine offers is opened where this action says no |
| `inputs` | Its questions before it runs, a page each: settings without `first`, `group` or `value-from`. Answered for this run only, never stored |
| `confirm` | A yes or no after its inputs and before its work, opening on No. For a second consent: the row agreed to looking, this to what was found |
| `report` | Its page after it ran. The first paragraph is the headline |
| `qr` | A variable drawn on that page as a code, such as an address. No setting declares it: the script answers it into `MODULE_CONF` |
| `tty` | Its page is the terminal itself, and it has no other |
| `simulates` | `true`: runs on a dry run too |
| `errors` | What a status means that its `action.sh` stops itself with, see [Stopping on Purpose](#stopping-on-purpose) |

Where a module places an action:

| Under | Offered |
| --- | --- |
| `requires` | Nowhere: run by itself before anything is asked, a question with no page. Its `error` stands in front of everything until it says yes |
| `on: dashboard` | A row on the dashboard, after the answers |
| `on: leave` | A row on the way out, above **Exit** |
| `on: failure` | A row under a run that failed. None under a run [stopped on purpose](#stopping-on-purpose) |
| `on: success` | A row under a run that finished |

- A row opens the action's inputs, its `confirm`, its work and its `report` in turn. A flow of more is several actions, chained by `on: failure`
- A module with `on: leave` says the machine booted to run it, so leaving becomes a choice
- Refused at startup: an unknown name, an action nothing names, a ring of actions, a page beside the terminal, a page or a `confirm` on an action only run by itself, `errors` beside `tty`, a check without `error`, and an input or a `confirm` under `on: leave`

## What a Script Receives

Every declared variable under its own name, and the runtime's:

| Variable | Description |
| --- | --- |
| `MODULE_CONF` | The answer file. A script answers by appending `KEY='value'` |
| `MODULE_LOG` | The log |
| `MODULE_LANGUAGE` | The language the interface is read in, such as `de` |
| `MODULE_VERSION` | The version of the program |
| `DRY_RUN` | `true` on a dry run, absent otherwise |

Scripts run with `lib.sh` loaded and an `ERR` trap: no shebang, no `set -e`, no error handling.

- **Any non-zero status is a failure**, a failed command or what the script hands back. `[ "$X" = y ] && do_it` as the last line fails where the test is false
- **Ask nothing.** Every question is in the YAML, unless the action has `tty: true`
- **Print nothing for a person.** stdout and stderr go to the log
- A `test.sh` also changes nothing

A failure names the module, the task or action, the script and its line, the command, the exit code and what the tool said.

### Stopping on Purpose

What a script sees coming, it stops on itself, with a status of its own. The YAML says what that status means:

```yaml
errors:
  3: |
    No internet connection

    Connect this machine and choose Install now again.
```

`exit 3` stops the run on these words, the first paragraph as the headline. Nothing technical stands beside them and no `on: failure` row under them: the words say what to do. Every other failure is reported where the script broke, for whoever changes it.

- A task or an action declares them for its own script, the module for every script it has. The unit's own words come first
- A status from 1 to 125: bash spends 126 and up on a command it cannot run or find and on signals
- Only `exit` counts, in the script or in a function it calls. A failed command, a `return` or last line that hands back a status, and an `exit` inside `$(…)` or `( … )` are where it broke, whatever the status
- A status no YAML puts into words is a failure like any other
- An action stopped this way opens nothing under its `on: failure`

### Dry Run

`--dry-run` shows a run without doing it. No task, test or action starts unless it declares `simulates: true`, and nothing under `requires` is asked. What a setting calls still runs, with `DRY_RUN=true`.

## Files It Writes

Beside wherever the program was started:

| File | Description |
| --- | --- |
| `<module>.conf` | Every answer as `KEY='value'`, under its group and with its title as a comment, the interface language first. Editable by hand. No password, no derived answer, no answer of a task or an action |
| `<module>.log` | The run's progress and everything every script printed, stamped in the machine's time zone. The log before stays as `<module>.log.old` |

## Keys

| Key | Meaning |
| --- | --- |
| `⏎` `→` `l` | Open, confirm |
| `esc` `←` `h` `backspace` | Back |
| `↑` `↓` `k` `j` | Move |
| `⇞` `⇟` `g` `G` | A page up or down, the top, the bottom |
| `f` `/` | Narrow a list |
| `q` `ctrl+c` | Leave |

**Note:** _In a text box every letter is a character, and backspace deletes one._

## Translations

The English text is the key. A catalog without a text shows the English.

- `locales/<code>.po` holds every text of the runtime and of every module, and the tests hold it to that: a text missing or left over fails them, and so does a placeholder dropped or added
- `msgid "English"` translates to the language's own name: `Deutsch`. That is how the language page lists it
- The language is chosen on the first page and kept on the first line of the answer file, as `MODULE_LANGUAGE`. A file that keeps one skips the page
- The first page is never translated: it is drawn before a language is settled

## The Console

A terminal of sixteen colours, such as the Linux console (`TERM=linux`), shows every colour in the slot of its hue, and the accent in the slot `console-accent` names: `red`, `green`, `yellow`, `blue`, `magenta`, `cyan`, `white`, or any of them with `bright-`. The lines and the marks switch to what a console font holds, and `arch-os glyphs` prints every character the interface draws there, so the ISO's font can be held to it.

**Note:** _A console font holds 512 glyphs at most: Latin with its accents, Greek and Cyrillic. **[➜ What the Console Can Draw](../iso/README.md#what-the-console-can-draw)**_
