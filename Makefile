# The only task runner. CI runs the same targets.
#
#   runtime/target/release/arch-os             build: the runtime with every module embedded
#   dist/arch-os-$VERSION-recovery/            image: recovery.efi, recovery.img
#   dist/arch-os-$VERSION-recovery-x86_64.tar  image: the Recovery folder as one file
#   dist/arch-os-$VERSION-x86_64.iso           image: the ISO

SHELL       := bash
.SHELLFLAGS := -eu -o pipefail -c
.DELETE_ON_ERROR:

# ////////////////////////////////////////////////////////////////////////////
# THE PROGRAM | Runtime with embedded product
# ////////////////////////////////////////////////////////////////////////////

RUNTIME := runtime
BIN     := $(RUNTIME)/target/release/arch-os

# Set by a release. Without it, build.rs names a pre-release of the next patch.
VERSION ?=

# Module and arguments for `make run`.
MODULE ?= installer
ARGS   ?=

# ////////////////////////////////////////////////////////////////////////////
# THE IMAGES | Patched stock archiso profiles
# ////////////////////////////////////////////////////////////////////////////

DIST_DIR := dist

# Scripts, not targets, each taking its input as an argument.
ISO_DIR    := iso
ISO_BUILD  := $(ISO_DIR)/build.sh
ISO_SMOKE  := $(ISO_DIR)/smoke.sh
ISO_E2E    := $(ISO_DIR)/e2e.sh
ISO_GLYPHS := $(ISO_DIR)/glyphs.sh
ISO_FONT   := $(ISO_DIR)/font.sh

# `make e2e` installs core or desktop.
START ?= core

# The newest images, expanded on use, so `make iso && make smoke` needs no
# argument.
ISO      ?= $(shell ls -t $(DIST_DIR)/*.iso 2>/dev/null | head -1)
RECOVERY ?= $(shell ls -td $(DIST_DIR)/*-recovery 2>/dev/null | head -1)

# ////////////////////////////////////////////////////////////////////////////
# THE SCRIPTS | Grouped by dialect
# ////////////////////////////////////////////////////////////////////////////

# Bash: image build, boot tests and the images' own scripts.
ISO_SCRIPTS := $(ISO_BUILD) $(ISO_SMOKE) $(ISO_E2E) $(ISO_GLYPHS) $(ISO_FONT) $(wildcard $(ISO_DIR)/airootfs/usr/local/bin/* $(ISO_DIR)/recovery/airootfs/usr/local/bin/*)

# Every folder with a module.yaml, as the build embeds them.
MODULES := $(patsubst %/module.yaml,%,$(wildcard */module.yaml))

LIBRARY        := lib.sh
MODULE_SCRIPTS = $(LIBRARY) $(shell find $(MODULES) -name '*.sh')
MODULE_YAML    = product.yaml $(shell find $(MODULES) -name '*.yaml')

# Shell files a module ships into a home, found by file name. zsh gets zsh -n,
# since shellcheck has no zsh.
MODULE_SHELL = $(wildcard $(addsuffix /tasks/*/data/bashrc,$(MODULES)) $(addsuffix /tasks/*/data/aliases,$(MODULES)))
MODULE_ZSH   = $(wildcard $(addsuffix /tasks/*/data/zshrc,$(MODULES)))

# Listed by name, since it has no extension.
MODULE_PROGRAMS := installer/tasks/recovery-app/data/arch-os-recovery installer/tasks/housekeeping/data/smartd-notify

# Everything that can reach the console. READMEs and fastfetch's config target a
# graphical terminal.
MODULE_TEXT = product.yaml $(wildcard locales/*.po) $(LIBRARY) $(shell find $(MODULES) -type f ! -name '*.md' ! -name fastfetch.jsonc)

# Each module's check of its data/, and a task's check of a program it ships.
DATA_CHECKS = $(wildcard $(addsuffix /data/check.sh,$(MODULES)) $(addsuffix /tasks/*/check.sh,$(MODULES)))

LIBRARY_CHECK := lib.check.sh

# A task's check of its zshrc, run in zsh.
ZSH_CHECKS = $(wildcard $(addsuffix /tasks/*/check.zsh,$(MODULES)))

# ////////////////////////////////////////////////////////////////////////////
# HOUSEKEEPING
# ////////////////////////////////////////////////////////////////////////////

# Build output outside cargo's target folder.
BUILD_OUTPUT := $(DIST_DIR) $(ISO_DIR)/archiso $(ISO_DIR)/download

# Empty as root, as in CI.
SUDO := $(shell [ "$$(id -u)" -eq 0 ] || echo sudo)

.PHONY: all build run image iso smoke e2e screenshots banner check fmt fmt-check lint test \
	secrets-check library-check data-check zsh-check glyphs-check github clean

all: build

build:
	cd $(RUNTIME) && $(if $(VERSION),ARCH_OS_VERSION=$(VERSION)) cargo build --release --locked

# Runs from source in runtime/target/run, which holds answers and log:
# `make run MODULE=recovery ARGS=--dry-run`
run:
	mkdir -p $(RUNTIME)/target/run
	cd $(RUNTIME)/target/run && cargo run --manifest-path ../../Cargo.toml -- $(MODULE) $(ARGS)

image:
	$(ISO_BUILD) $(BIN) $(DIST_DIR)

# .WAIT, since the images embed the program.
iso: build .WAIT image

# Boots both images until the interface shows. Frames land in dist/.
smoke:
	$(ISO_SMOKE) $(ISO)
	$(ISO_SMOKE) $(RECOVERY)

# Installs the newest ISO through its interface: iso/README.md. Logs land in
# dist/e2e/.
e2e:
	$(ISO_E2E) $(ISO) $(START)

# By hand after a visible change: docs/CONTRIBUTING.md. The pages show VERSION,
# so `make screenshots VERSION=2.1.0` shows a release before it exists.
screenshots: build
	python3 docs/screenshots.py --product $(BIN)

# From two screenshots and the README's tagline, the paragraph under the banner
# without bold, so banner and README stay in sync. murkl/workflows, checked out
# next to this project, renders it.
banner:
	@tagline="$$(awk '/src="banner\.png"/ { found = 1; next } found && NF { print; exit }' docs/README.md | \
		sed -n 's:^<p>\(.*\)</p>$$:\1:p' | sed 's:</\{0,1\}b>::g')"; \
	[ -n "$$tagline" ] || { echo "docs/README.md: no <p> tagline under the banner" >&2; exit 1; }; \
	python3 ../workflows/banner/banner.py --product product.yaml --logo docs/logo.svg --cell 9 --tagline "$$tagline" \
		--card docs/screenshots/installer.png --card docs/screenshots/installing.png

# ////////////////////////////////////////////////////////////////////////////
# CHECKS | Required before commit
# ////////////////////////////////////////////////////////////////////////////

# Cheapest and loudest first. CI runs exactly this.
check: secrets-check fmt-check lint test library-check data-check zsh-check glyphs-check

secrets-check:
	gitleaks dir . --redact --no-banner

fmt:
	cd $(RUNTIME) && cargo fmt
	shfmt -w -i 4 $(ISO_SCRIPTS) $(MODULE_PROGRAMS) $(MODULE_SCRIPTS) $(MODULE_SHELL) $(LIBRARY_CHECK)

fmt-check:
	cd $(RUNTIME) && cargo fmt --check
	shfmt -d -i 4 $(ISO_SCRIPTS) $(MODULE_PROGRAMS) $(MODULE_SCRIPTS) $(MODULE_SHELL) $(LIBRARY_CHECK)

# Module scripts as the runtime runs them: bash, with lib.sh in scope.
lint:
	cd $(RUNTIME) && cargo clippy --all-targets --locked -- -D warnings
	shellcheck -x -P SCRIPTDIR -S style $(ISO_SCRIPTS) $(MODULE_PROGRAMS)
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
		|| { echo "a file written into the new system is a template beside its task, placed with render" >&2; exit 1; }
	@! grep -nE '^[[:space:]]*![[:space:]]' $(MODULE_SCRIPTS) \
		|| { echo "a command inverted with ! never triggers the ERR trap, use an if that exits" >&2; exit 1; }

# Loads the product as a run does and checks every catalog against every text.
test:
	cd $(RUNTIME) && cargo test --locked

# A character outside the console font shows as a box. A debug build of the
# program lists the same glyphs, without the release's LTO.
glyphs-check:
	cd $(RUNTIME) && cargo build --locked
	@$(ISO_GLYPHS) $(RUNTIME)/target/debug/arch-os $(MODULE_TEXT)

# Each name a module passes to another program, against that program's list. A
# wrong keymap, font or time zone is ignored silently, a dropped package fails.
data-check:
	@for check in $(DATA_CHECKS); do $$check || exit 1; done

library-check:
	@./$(LIBRARY_CHECK)

zsh-check:
	@for check in $(ZSH_CHECKS); do zsh "$$check" "$$(dirname "$$check")/data/zshrc" || exit 1; done

# Applies .github/settings/ with murkl/workflows checked out next to this project.
# Run by hand as admin, since a workflow must not change its own rules.
github:
	../workflows/settings/settings.sh

# mkarchiso writes as root. Plain rm first, so a normal clean needs no password.
clean:
	cd $(RUNTIME) && cargo clean
	rm -rf $(BUILD_OUTPUT) || $(SUDO) rm -rf $(BUILD_OUTPUT)
