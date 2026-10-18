# The only task runner. CI runs these targets, so what holds at a desk holds
# there.
#
#   runtime/target/release/arch-os             build: the program, with every module inside it
#   dist/arch-os-$VERSION-recovery/            image: recovery.efi, recovery.img
#   dist/arch-os-$VERSION-recovery-x86_64.tar  image: that folder as one file
#   dist/arch-os-$VERSION-x86_64.iso           image: the bootable image

# One bash per recipe, with -e, -u and pipefail. A failed file target is
# removed rather than left half written.
SHELL       := bash
.SHELLFLAGS := -eu -o pipefail -c
.DELETE_ON_ERROR:

# ////////////////////////////////////////////////////////////////////////////
# THE PROGRAM | The runtime with the product embedded
# ////////////////////////////////////////////////////////////////////////////

RUNTIME := runtime
BIN     := $(RUNTIME)/target/release/arch-os

# What a release hands in as `VERSION=`. Without it, build.rs names a
# pre-release of the patch after the last release.
VERSION ?=

# What `make run` opens, and the rest of its command line.
MODULE ?= installer
ARGS   ?=

# ////////////////////////////////////////////////////////////////////////////
# THE IMAGES | Stock Arch profiles, patched to boot into this
# ////////////////////////////////////////////////////////////////////////////

DIST_DIR := dist

# Scripts rather than targets, each taking what it works on as an argument.
ISO_DIR    := iso
ISO_BUILD  := $(ISO_DIR)/build.sh
ISO_SMOKE  := $(ISO_DIR)/smoke.sh
ISO_E2E    := $(ISO_DIR)/e2e.sh
ISO_GLYPHS := $(ISO_DIR)/glyphs.sh
ISO_FONT   := $(ISO_DIR)/font.sh

# What `make e2e` installs: core or desktop.
START ?= core

# The Recovery inside the ISO, or left for the Installer to fetch from the
# release page. build.sh decides by the version, `make iso ISO_RECOVERY=true`
# by hand.
ISO_RECOVERY ?=

# The newest images, read when used, so `make iso && make smoke` needs no
# argument.
ISO      ?= $(shell ls -t $(DIST_DIR)/*.iso 2>/dev/null | head -1)
RECOVERY ?= $(shell ls -td $(DIST_DIR)/*-recovery 2>/dev/null | head -1)

# ////////////////////////////////////////////////////////////////////////////
# THE SCRIPTS | Everything checked, by the dialect it is written in
# ////////////////////////////////////////////////////////////////////////////

# POSIX sh: get.sh runs on whatever shell the machine has.
POSIX_SCRIPTS := get.sh .github/settings.sh

# Bash: what builds and boots the images, and what they run.
ISO_SCRIPTS := $(ISO_BUILD) $(ISO_SMOKE) $(ISO_E2E) $(ISO_GLYPHS) $(ISO_FONT) $(wildcard $(ISO_DIR)/src/usr/local/bin/* $(ISO_DIR)/recovery/airootfs/usr/local/bin/*)

# Bash: the helpers in docs/, run by hand.
DOCS_SCRIPTS := $(wildcard docs/*.sh)

# The modules: every folder with a module.yaml, as the build embeds them.
MODULES := $(patsubst %/module.yaml,%,$(wildcard */module.yaml))

# Every module script with the library they share, and every yaml.
LIBRARY        := lib.sh
MODULE_SCRIPTS = $(LIBRARY) $(shell find $(MODULES) -name '*.sh')
MODULE_YAML    = product.yaml $(shell find $(MODULES) -name '*.yaml')

# Shell a module ships into somebody's home, found by the name it lands under.
# zsh is read by its own shell, since shellcheck cannot.
MODULE_SHELL = $(wildcard $(addsuffix /tasks/*/*/data/bashrc,$(MODULES)) $(addsuffix /tasks/*/*/data/aliases,$(MODULES)))
MODULE_ZSH   = $(wildcard $(addsuffix /tasks/*/*/data/zshrc,$(MODULES)))

# A program a module ships, named outright: it has no extension to find it by.
MODULE_PROGRAMS := installer/tasks/desktop/recovery-app/data/arch-os-recovery

# Everything that can reach a screen: the product, the catalogs, the library
# and every module file. The READMEs and fastfetch's config, drawn for a
# graphical terminal, never reach a console.
MODULE_TEXT = product.yaml $(wildcard locales/*.po) $(LIBRARY) $(shell find $(MODULES) -type f ! -name '*.md' ! -name fastfetch.jsonc)

# Each module's own check of what it ships in data/: the Installer's lookup
# tables, the Recovery's boot entries. And a task's check of a program it
# ships: the cache trim that keeps the snapshots' kernels.
DATA_CHECKS = $(wildcard $(addsuffix /data/check.sh,$(MODULES)) $(addsuffix /tasks/*/*/check.sh,$(MODULES)))

# lib.sh's own check: its functions against answers written out beside them.
LIBRARY_CHECK := lib.check.sh

# A task's check of the zshrc it ships: keys typed into the shell reading it.
ZSH_CHECKS = $(wildcard $(addsuffix /tasks/*/*/check.zsh,$(MODULES)))

# ////////////////////////////////////////////////////////////////////////////
# HOUSEKEEPING
# ////////////////////////////////////////////////////////////////////////////

# Everything a build leaves outside cargo's target folder.
BUILD_OUTPUT := $(DIST_DIR) $(ISO_DIR)/archiso $(ISO_DIR)/download

# Empty when there is nothing to elevate, which is the case in CI.
SUDO := $(shell [ "$$(id -u)" -eq 0 ] || echo sudo)

.PHONY: all build run image iso smoke e2e check fmt fmt-check lint test \
	secrets-check actions-check library-check data-check zsh-check glyphs-check github clean

all: build

# The program: the runtime with the product, the library, the catalogs and
# every module inside it.
build:
	cd $(RUNTIME) && $(if $(VERSION),ARCH_OS_VERSION=$(VERSION)) cargo build --release --locked

# Arch OS out of the sources, in a folder of its own, where it keeps its
# answers and its log. `make run MODULE=recovery ARGS=--dry-run`.
run:
	mkdir -p $(RUNTIME)/target/run
	cd $(RUNTIME)/target/run && cargo run --manifest-path ../../Cargo.toml -- $(MODULE) $(ARGS)

# The images, out of the program: the Recovery as a folder and as one file for
# the release page, then the ISO that carries it.
image:
	$(if $(ISO_RECOVERY),ISO_RECOVERY=$(ISO_RECOVERY)) $(ISO_BUILD) $(BIN) $(DIST_DIR)

# The whole way there.
iso: build image

# Boots both images and waits for the interface. The frames land in dist/.
smoke:
	$(ISO_SMOKE) $(ISO)
	$(ISO_SMOKE) $(RECOVERY)

# Installs the newest ISO and walks it as a person does: iso/README.md. The logs
# land in dist/e2e/.
e2e:
	$(ISO_E2E) $(ISO) $(START)

# ////////////////////////////////////////////////////////////////////////////
# CHECKS | What has to pass before anything is committed
# ////////////////////////////////////////////////////////////////////////////

# The whole gate, cheapest and loudest first. CI runs exactly this.
check: secrets-check fmt-check lint test actions-check library-check data-check zsh-check glyphs-check

# This is installed by piping a script into a shell.
secrets-check:
	gitleaks dir . --redact --no-banner

fmt:
	cd $(RUNTIME) && cargo fmt
	shfmt -w -ln posix -i 4 $(POSIX_SCRIPTS)
	shfmt -w -i 4 $(ISO_SCRIPTS) $(DOCS_SCRIPTS) $(MODULE_PROGRAMS) $(MODULE_SCRIPTS) $(MODULE_SHELL) $(LIBRARY_CHECK)

fmt-check:
	cd $(RUNTIME) && cargo fmt --check
	shfmt -d -ln posix -i 4 $(POSIX_SCRIPTS)
	shfmt -d -i 4 $(ISO_SCRIPTS) $(DOCS_SCRIPTS) $(MODULE_PROGRAMS) $(MODULE_SCRIPTS) $(MODULE_SHELL) $(LIBRARY_CHECK)

# Module scripts are checked as the runtime runs them: bash, with lib.sh in
# scope. A script that sources it is read with it, found from the script's own
# folder. Each grep refuses a pattern its message explains.
lint:
	cd $(RUNTIME) && cargo clippy --all-targets --locked -- -D warnings
	shellcheck -s sh -S style $(POSIX_SCRIPTS)
	shellcheck -x -P SCRIPTDIR -S style $(ISO_SCRIPTS) $(DOCS_SCRIPTS) $(MODULE_PROGRAMS)
	shellcheck -x -S style $(MODULE_SCRIPTS) $(LIBRARY_CHECK)
	shellcheck -s bash -S style -e SC1091 $(MODULE_SHELL)
	for file in $(MODULE_ZSH) $(ZSH_CHECKS); do zsh -n "$$file"; done
	yamllint -s .
	actionlint
	zizmor --offline --persona auditor .github
	msgfmt --check-format -o /dev/null $(wildcard locales/*.po)
	@! grep -nE 'arch-chroot [^|&;]*[[:space:]](command|type|hash|source|alias)[[:space:]]' \
		$(MODULE_SCRIPTS) $(MODULE_YAML) \
		|| { echo "a shell builtin cannot run through arch-chroot, see has_command" >&2; exit 1; }
	@! grep -nE '^[[:space:]]*\}[[:space:]]*>>?[[:space:]]*"\$$\{MNT\}' $(MODULE_SCRIPTS) \
		|| { echo "a file written into the new system is a template beside its task, put in place with render, see lib.sh" >&2; exit 1; }
	@! grep -nE '^[[:space:]]*![[:space:]]' $(MODULE_SCRIPTS) \
		|| { echo "a command inverted with ! fails nothing under the ERR trap a script runs in: write it as an if that exits" >&2; exit 1; }

# The runtime's tests load the product as a run does and hold every catalog to
# every text.
test:
	cd $(RUNTIME) && cargo test --locked

# A console font holds one table of glyphs, and a character outside it is a box
# on screen. Asked of the program, which knows what it draws itself. A debug
# build answers the same, without the release's link-time optimisation.
glyphs-check:
	cd $(RUNTIME) && cargo build --locked
	@$(ISO_GLYPHS) $(RUNTIME)/target/debug/arch-os $(MODULE_TEXT)

# Every name a module hands to another program, against that program's own
# list: a wrong keymap, font or time zone reads fine and is silently ignored,
# and a package Arch dropped fails somebody's installation.
data-check:
	@for check in $(DATA_CHECKS); do $$check || exit 1; done

library-check:
	@./$(LIBRARY_CHECK)

zsh-check:
	@for check in $(ZSH_CHECKS); do zsh "$$check" "$$(dirname "$$check")/data/zshrc" || exit 1; done

# An action two modules share is a folder in each, the same file for file.
actions-check:
	@for name in $$(basename -a */actions/*/ | sort | uniq -d); do \
		set -- */actions/$$name; first=$$1; shift; \
		for dir in "$$@"; do \
			diff -r $$first $$dir || { echo "$$dir differs from $$first" >&2; exit 1; }; \
		done; \
	done

# The repository's settings on GitHub, out of .github/settings/. Run by hand as
# an admin: a workflow may not change the rules it is held to.
github:
	.github/settings.sh

# mkarchiso writes as root. The plain removal comes first, so an ordinary clean
# asks for no password.
clean:
	cd $(RUNTIME) && cargo clean
	rm -rf $(BUILD_OUTPUT) || $(SUDO) rm -rf $(BUILD_OUTPUT)
