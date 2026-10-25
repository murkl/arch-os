# Arch OS Runtime

The program behind Installer and Recovery: draws the pages, asks the questions, stores the answers, runs the scripts. Pages and work are declared in YAML with bash scripts beside it, all compiled into one binary. Another Arch distribution swaps YAML and scripts and keeps the runtime.

```
arch-os <module> [--dry-run] [--kiosk] [--unattended] [--trace <file>]
arch-os glyphs
arch-os --version
```

| Argument | Meaning |
| --- | --- |
| `<module>` | A folder beside `runtime/` with a `module.yaml`: `installer` or `recovery` |
| `--dry-run` | Shows the run without doing it. **[➜ Dry Run](#dry-run)** |
| `--kiosk` | The machine's only program: leaving restarts it with every answer kept |
| `--unattended` | Runs the work without interface. **[➜ Unattended](#unattended)** |
| `--trace <file>` | Names each page and row on screen by id, for tests. **[➜ Trace](#trace)** |
| `glyphs` | Every character the interface draws on a console, for **[iso/font/glyphs.sh](../iso/font/glyphs.sh)** |

```
cargo build --release   # program with every module embedded
cargo test              # load every module as a run does, hold every catalog to every text
```

## Product

```
product.yaml        name, color, wordmark, actions shared by all modules
lib.sh              the one library of every script, with every function the YAML names
locales/<code>.po   one catalog per language
<module>/           one folder per module
runtime/            this program
```

The build embeds everything except `runtime/`, so the binary is the whole program. At start it writes the scripts to `$XDG_RUNTIME_DIR/arch-os-<pid>/` and runs them there. The folder is removed on exit, a stale one at the next start.

### `product.yaml`

```yaml
title: Arch OS
logo: |
  Arch Linux

   █████  ██████   ██████ ██   ██      ██████  ███████
accent: "#1793d1"
console-accent: bright-blue
surface: "#3b4252"
console-surface: blue
status:
  check: check_online()
  pass: Online
  fail: Offline
actions:
  restart:
    title: Restart
    run: restart_machine()
```

| Key | Description |
| --- | --- |
| `title` | Product name, first in the breadcrumb |
| `logo` | Wordmark on the way in. Above the first blank line, a dim eyebrow |
| `accent` | `#rrggbb`, the one color the interface derives from |
| `console-accent` | Its slot on a 16-color console. **[➜ Console](#console)** |
| `surface` | `#rrggbb` behind the row under the cursor. Default dark gray |
| `console-surface` | Its slot on a console: `red`, `green`, `yellow`, `blue`, `magenta`, `cyan` or `white`, since a console has only eight background colors. Default blue. The row on it reads in white or black, whichever contrasts more |
| `status` | One line about the machine in the header. `check` is a `lib.sh` function: exit 0 shows `pass`, anything else `fail`. Checked every `every` seconds, default 10, and right after an action |
| `actions` | Actions any module may name. **[➜ Actions](#actions)** |

### `lib.sh`

The one place for script code outside the tasks. Loaded before every task, test and action and before everything the YAML calls. Defines functions and exports constants, computes nothing while loading.

### Functions

A key that runs shell code names a `lib.sh` function as `name()`. A missing function is refused at startup, and so is shell code inside the YAML: every line stays where a linter reads it and a failure can point to it.

These keys are `check` of the status, `run` of an action, and `options-from`, `value-from`, `prefill`, `apply` and `check` of a setting. A setting's function is named after its key, such as `options_disks()` or `prefill_timezone()`, an action's after its work, such as `join_wifi()`.

## Module

| Path | Description |
| --- | --- |
| `module.yaml` | Settings, actions and tasks |
| `tasks/<task>/task.sh` | A task's work |
| `tasks/<task>/test.sh` | Optional, checks the result |

The folder name is the module's identity: `arch-os recovery` opens it, and it writes `recovery.conf` and `recovery.log`.

**Note:** _Each key table below lists the keys in file order, which is run order._

### `module.yaml`

```yaml
title: Installer
start: Install now
requires: [live-image, root, internet]
presets: …
settings: …
dashboard: [start, settings, reset, wifi]
language: Region
confirm: |
  Install Arch OS on {{ARCH_OS_DISK}}?

  Everything on the disk is erased.
stages: …
report: |
  Arch OS installed

  {{ARCH_OS_HOSTNAME}} on {{ARCH_OS_DISK}}.
errors:
  3: |
    Internet connection lost

    Reconnect this machine.
on:
  leave: [restart, shutdown]
  failure: [share-log]
  success: [chroot]
actions: …
```

| Key | Description |
| --- | --- |
| `title` | **Required.** Module name in the breadcrumb |
| `start` | First dashboard row, starts the work. Default `Start` |
| `requires` | Actions checked in order before anything is asked. The first no blocks everything with its page and is checked again every few seconds. Skipped on a dry run |
| `presets` | Profiles. **[➜ Presets](#presets)** |
| `settings` | Questions under their headings. **[➜ Settings](#settings)** |
| `dashboard` | **Required.** Dashboard rows in order. **[➜ Dashboard](#dashboard)** |
| `language` | Heading of the interface language row. Refused where no setting is under it |
| `confirm` | Question after every password and before the work, opening on No. First paragraph is the headline |
| `stages` | **Required.** Phases of the work in order, each with its tasks. **[➜ Tasks](#tasks)** |
| `report` | Text of a finished run. First paragraph is the headline |
| `errors` | Text for each status its scripts stop with. **[➜ Stopping on Purpose](#stopping-on-purpose)** |
| `on` | Where its other actions appear. **[➜ Actions](#actions)** |
| `actions` | Its own actions. **[➜ Actions](#actions)** |

### Start Sequence

1. Wordmark, then language, unless the answer file holds one
2. Every setting marked `first`
3. Actions under `requires`
4. Profiles, while there are no answers yet
5. Every required setting without answer, one page each, counted in the header
6. Dashboard

### Dashboard

The module's home: rows in `dashboard` order, each name once. `f` filters.

| Name | Row |
| --- | --- |
| `start` | **Required.** The `start` row, starts the work |
| `settings` | **Required.** Every answer under its group heading, each row opens its question. The interface language heads the group `language` names |
| `reset` | **Reset all answers**: deletes the answer file after a question that opens on No |
| An action | Its row where its `requires` say yes, under its `group` heading. Directly after answers ending with that group, a blank row replaces the heading. An action may not use a name above |

A blank row follows `start`, the answers and each action group. After `start`, the answer headings take its place.

`start` asks what is missing, then every password, then `confirm`, then runs the tasks: one row each, checked off when done, counted in the header. `tab` switches to their output, during and after the run. `systemd-inhibit` blocks shutdown and sleep while tasks run, so closing the lid never suspends a run. A task with `asks` or `confirm` pauses the run on its page. The header names the outcome, **Done** or **Failed**. A finished run shows `report`, its duration, the actions under `on: success` and **Continue**. A failed run shows what failed and where, the actions under `on: failure` and **Back to the dashboard** with a confirmation.

`q` or `esc` on the dashboard leaves. With `on: leave`, or in a kiosk, a page comes first: the actions under `on: leave`, then **Exit**, or **Start over** in a kiosk. During a run the same page warns that every choice stops it. The run continues behind it, and its questions wait until the page closes. A choice stops the run first: its script and everything it started get `SIGTERM`, after 10 seconds `SIGKILL`. The choice runs once none of it is left.

## Settings

One entry under `settings:` is one question and one environment variable. The key above a list is the dashboard heading of its rows. Lists are asked in file order.

```yaml
settings:
  Storage:
    - name: ARCH_OS_DISK
      type: list
      title: Disk
      description: Everything on it is erased.
      required: true
      options-from: options_disks()
      pattern: '^/dev/'
      error: Choose a disk that exists.
```

The type sets the widget and the allowed keys:

| `type` | Widget | Keys |
| --- | --- | --- |
| `text` | Text box | `default`, `prefill`, `value-from`, `pattern` |
| `bool` | Yes or No | `default`, `value-from` |
| `list` | List | `options` or `options-from`, `filter`, `default`, `prefill`, `pattern` |
| `open-list` | List plus a custom entry row | `options` or `options-from`, `filter`, `default`, `prefill`, `pattern` |
| `password` | Existing password, typed once | `check` |
| `new-password` | New password, typed twice | |

| Key | Description |
| --- | --- |
| `name` | **Required.** Variable a script reads. `MODULE_` and `DRY_RUN` are reserved |
| `type` | **Required.** One of the types above |
| `title` | **Required.** The question and its dashboard row |
| `description` | Purpose of the value |
| `when` | When it is asked. **[➜ Conditions](#conditions)** |
| `first` | Asked before everything else, `requires` included, with the filter open |
| `required` | Asked while unanswered |
| `options` | Answers, inline |
| `options-from` | Prints the answers, one per line. `value<TAB>label` stores the value and shows the label |
| `filter` | Filter box: `collapsed` behind `f`, or `open` |
| `default` | Initial answer, such as `true`, `auto` or `pc105` |
| `prefill` | Prints a suggestion. Still asked |
| `value-from` | Prints the value instead of asking. Never asked, never on the dashboard, never stored |
| `pattern` | Regular expression the answer must match |
| `error` | Message for a wrong answer |
| `check` | Tests a `password` before accepting it |
| `apply` | Applies the answer to this machine, such as a keymap |

- `true` and `false` show as Yes and No
- A password is asked right before the run, used and forgotten
- `value-from` runs when the module opens and on every answer change
- An `options-from` answer is checked against its list again at the start of the work, before any password. One no longer listed is asked again
- An answer from the file passes `pattern` and the list like a typed one. One that fails is asked again

**Note:** _Refused at startup: a key the type does not take, `value-from` with `prefill` or `first`, a password with `first`._

### Conditions

```yaml
when:
  - ARCH_OS_DESKTOP != none
  - ARCH_OS_FLATPAK_ENABLED == true
```

`VAR == value` and `VAR != value`, one or several, all must hold. No `or`: two unrelated conditions are two rows. An undeclared name is refused at startup.

### Placeholders

`{{VAR}}` is filled from the answers in every `confirm`, `report`, `error` and `errors`. An undeclared name is refused at startup, and a translation that drops or adds one fails the tests.

## Presets

A profile on screen, offered once while there are no answers. A preset is a set of answers, not a mode.

```yaml
presets:
  - title: Desktop
    description: Core with GNOME, drivers, codecs and everyday apps.
    values:
      ARCH_OS_DESKTOP: gnome

  - title: Shared configuration
    description: Answers shared by another installation.
    action: import-config
```

A preset lists its answers under `values` or names the action that fetches them, never both. The action's script appends them to `MODULE_CONF`.

## Tasks

An entry under its stage in `stages:` and a folder `tasks/<task>/` with `task.sh`. The stage is a **when**, the task a **what**.

```yaml
stages:
  desktop:
    gnome:
      title: Install GNOME
    graphics:
      title: Install the graphics drivers
      needs: [gnome]
      when: ARCH_OS_DESKTOP != none
```

| Key | Description |
| --- | --- |
| `title` | **Required.** Its row in the run |
| `needs` | Tasks of its stage it runs after |
| `when` | Every condition must hold, or it is left out |
| `asks` | A question the run pauses for: `name`, `title`, `description`, `options` or `options-from` and `filter`, read when the run reaches it. An empty list skips the task. Never stored |
| `confirm` | Yes or no before it runs, opening on No. No skips it |
| `yes-after` | Earlier tasks: if one of them ran, `confirm` opens on Yes |
| `progress` | `true`: its last printed line shows under it while it runs |
| `simulates` | `true`: runs on a dry run too, reading `DRY_RUN` itself |
| `allow-failure` | `true`: its failure does not stop the run |
| `report` | A page the run pauses on afterwards. First paragraph is the headline |
| `errors` | Text for each status its `task.sh` stops with. **[➜ Stopping on Purpose](#stopping-on-purpose)** |
| `texts` | `NAME: text` pairs its scripts get as variables, translated into the interface language. For text it writes into the system. A setting's name is refused |

- A task runs after every task of earlier stages, within its stage after its `needs`, otherwise in file order
- Refused: a `needs` into another stage, an unknown name, a cycle
- Refused: a task without folder, a folder under `tasks/` without task, a stage without tasks, two tasks with one name

### Tests

A `test.sh` beside `task.sh` runs right after the task, on the target machine. It reads without changing anything, its exit status is the result.

- A failed test does not stop the run
- The last page counts them: `38 of 40 tests passed`
- After a failed test or `allow-failure` task, that page offers **Test results**: each row opens file, line, command and output

## Actions

Work outside the run: an entry under `actions:` in `module.yaml`, or in `product.yaml` for all modules. The entry declares the behavior, the `run` function only works: exit 0 is yes, any other status no.

```yaml
actions:
  wifi:
    title: Connect to Wi-Fi
    description: Connects to a Wi-Fi network.
    requires: [wifi-card, no-cable]
    inputs:
      - name: ARCH_OS_WIFI_SSID
        type: list
        title: Network
        required: true
        options-from: options_wifi_networks()
    run: join_wifi()
    on:
      failure: [wifi-passphrase]
```

| Key | Description |
| --- | --- |
| `title` | **Required.** Its row and page heading |
| `description` | Sentence under its row. Choosing the row is the consent, so it names what leaves the machine |
| `group` | Dashboard heading of its row. Refused where `dashboard` does not list the action |
| `requires` | Actions that must say yes before this one appears |
| `inputs` | Questions before it runs, one page each: settings without `first` or `value-from`. For this run only, never stored |
| `confirm` | Yes or no after the inputs, before the work, opening on No. For a second consent: the row agrees to a lookup, this to its result |
| `run` | **Required.** The `lib.sh` function doing the work |
| `tty` | The terminal itself is its only page |
| `simulates` | `true`: runs on a dry run too |
| `error` | Meaning of a no. **Required** under a module's `requires` |
| `errors` | Text for each status its function stops with. **[➜ Stopping on Purpose](#stopping-on-purpose)** |
| `report` | Its page after running. First paragraph is the headline |
| `qr` | A variable shown on that page as QR code, such as an address. No setting declares it, the function appends it to `MODULE_CONF` |
| `on: failure` | On a no, the first of these available on this machine opens |

| Under | Shown |
| --- | --- |
| `requires` | Nowhere: runs by itself before anything is asked, a check without page. Its `error` blocks everything until it says yes |
| `dashboard` | A dashboard row, at its place in the list |
| `on: leave` | A row on the way out, above **Exit** |
| `on: failure` | A row under a failed run. None under a run [stopped on purpose](#stopping-on-purpose) |
| `on: success` | A row under a finished run |

- A row opens the inputs, `confirm`, the work and `report` in turn. A longer flow is several actions chained by `on: failure`
- `on: leave` declares that the machine booted for the module, so leaving becomes a choice
- Refused at startup: an unknown name, an action nothing names, a `product.yaml` action no module names, an action declared again in `module.yaml`, a cycle, an action naming itself under `on: failure`, a page beside `tty`, a page or `confirm` on a check-only action, `errors` beside `tty`, a check without `error`, an input or `confirm` under `on: leave`

## Script Environment

Every declared variable under its own name, plus:

| Variable | Description |
| --- | --- |
| `MODULE_CONF` | Answer file. A script stores an answer by appending `KEY='value'` |
| `MODULE_LOG` | Log |
| `MODULE_LANGUAGE` | Interface language, such as `de` |
| `MODULE_VERSION` | Program version |
| `DRY_RUN` | `true` on a dry run, unset otherwise |

Scripts and the functions the YAML names run with `lib.sh` loaded and an `ERR` trap: no shebang, no `set -e`, no error handling. Each runs in its own session without terminal, unless the action has `tty: true`.

- **Any non-zero status is a failure**, from a command or the script. `[ "$X" = y ] && do_it` as last line fails where the test is false. A harmless status is allowed by name: `grep x file || allow 1`
- Inside `$(…)` or `( … )` a failure ends only the subshell, and the enclosing command decides: `x=$(cmd)` fails the script at that line, `echo "$(cmd)"` continues
- **No prompts.** Every question lives in the YAML, unless the action has `tty: true`. A program prompting anyway fails at once, without terminal
- **No output for people.** stdout and stderr go to the log
- A `test.sh` changes nothing

A failure shows module, task or action, script and line, the `lib.sh` function holding that line, command, exit code and output. Inside a `lib.sh` function called by a task, the line is the task's.

### Stopping on Purpose

A script stops on an expected problem itself, with its own status, worded in the YAML:

```yaml
errors:
  3: |
    Internet connection lost

    Reconnect this machine.
```

`exit 3` stops the run with this text, first paragraph as headline, without technical details or `on: failure` rows. Every other failure is reported where the script broke.

- Tasks and actions declare them for their own work, the module for all its scripts. The unit's own text wins
- Status 1 to 125: bash reserves 126 and up for commands it cannot run or find, and for signals
- Only `exit` counts, in the script or a function it calls. A failed command, a `return` status, the last line's status and an `exit` inside `$(…)` or `( … )` count as a broken script, whatever the status
- A status without text is a failure like any other
- An action stopped this way opens nothing under `on: failure`

### Dry Run

`--dry-run` shows a run without doing it. No task, test or action starts unless it declares `simulates: true`, and `requires` are skipped. Setting functions still run, with `DRY_RUN=true`.

### Unattended

`--unattended` runs the work without interface: answers from `<module>.conf` beside the program, each password from the environment under its name, such as `ARCH_OS_PASSWORD`, every confirmation a yes. A task with `asks` takes its answer from the environment too and is skipped where it is unset. The log prints as written, then the report or the failure and the test tally.

Exit status 0 where the work finished, 1 where it failed or could not start: a requirement said no, an answer is missing or invalid, a password is unset. Nothing restarts or shuts down afterwards.

## Trace

`--trace <file>` appends a line whenever the screen changes, for tests that must not read text: smoke and e2e on a virtio port, the screenshots in a file.

| Line | When |
| --- | --- |
| `page <id>` | Another page is on screen |
| `focus <id>` | The cursor is on another row |
| `task <id>` | A task of the run starts |
| `language <code>` | The interface language is set |

| Page | Id |
| --- | --- |
| Splash, language, profiles, dashboard, leave, test results | `splash`, `language`, `presets`, `dashboard`, `leave`, `results` |
| Requirement | `gate <action>` |
| Question | `question <setting>` |
| Password | `password <setting>`, then `password <setting> repeat` |
| Confirmation | `confirm` before the run, `confirm <task or action>`, `confirm reset`, `confirm home` |
| Action at work | `action <action>` |
| Report | `report <task or action>`, `stopped <action>` after a stop on purpose |
| Failure | `failure <action>`, `result <n>` for a failed test |
| Run | `run`, then `run done`, `run failed` or `run stopped` |

A row is named by what choosing it picks: on the dashboard `start`, `reset`, `language`, a setting's name or an action's id, in a list its value, on a confirmation `yes` or `no`, on the leave page an action's id or `exit`, a profile by its position.

**Note:** _The images pass `--trace` only with the systemd credential `arch-os.trace` set, its value the file, such as `/dev/virtio-ports/arch-os.trace`. **[➜ Boot Tests](../iso/README.md#boot-tests)**_

## Files

In the start directory:

| File | Description |
| --- | --- |
| `<module>.conf` | Every answer as `KEY='value'`, under its group with its title as comment, interface language first. Editable by hand. No password, no derived answer, no task or action answer |
| `<module>.log` | Run progress and all script output, timestamped in the machine's time zone. The previous log stays as `<module>.log.old` |

## Keys

| Key | Meaning |
| --- | --- |
| `⏎` `→` `l` | Open, confirm |
| `esc` `←` `h` `backspace` | Back |
| `↑` `↓` `k` `j` | Move |
| `⇞` `⇟` `g` `G` | Page up, page down, top, bottom |
| `f` `/` | Filter a list, where the footer shows it |
| `q` `ctrl+c` | Leave |
| `tab` | Switch a run between list and output |

**Note:** _An empty text box shows its question's title as placeholder, or **Repeat** for the second password. In a text box every letter types and backspace deletes one. Pasted text goes into a text box and is ignored elsewhere. A held key repeats only for moving and typing._

## Translations

The English text is the key, a missing translation shows English. **[➜ Translating](../docs/CONTRIBUTING.md#translating)**

- `msgid "English"` becomes the language's own name on the language page: `Deutsch`
- The language is chosen on the first page and stored on the first line of the answer file as `MODULE_LANGUAGE`. A file holding one skips the page
- The first page is never translated: it appears before a language is chosen

## Console

A 16-color terminal, such as the Linux console (`TERM=linux`), shows every color in the slot of its hue, and the accent in the `console-accent` slot: `red`, `green`, `yellow`, `blue`, `magenta`, `cyan`, `white`, or any of them with `bright-`. Lines and marks switch to what a console font holds. `arch-os glyphs` prints every character the interface draws there, for the ISO's font check. **[➜ Console Glyphs](../iso/README.md#console-glyphs)**
