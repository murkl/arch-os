# A release is the Oak binary with oak.yaml and a modules folder beside it,
# which is the only thing a machine needs. Everything a build produces lands in
# dist/:
#
#   dist/arch-os-2.0.0/                 the product: oak, oak.yaml, modules/
#   dist/arch-os-2.0.0-x86_64.tar.gz    that folder as one file  (+ .sha256)
#   dist/arch-os-2.0.0-x86_64.iso       the bootable image       (+ .sha256)
#
# `build` writes the first, `tarball` and `image` each turn it into one of the
# others. Nothing is ever assembled twice.
#
# This is the only task runner in the repository. What CI runs is these targets,
# so a rule that holds at a desk holds there.

# Every recipe is one bash with -e, -u and pipefail: a command that fails in the
# middle of a line or a pipeline fails the target rather than the next one.
SHELL       := /bin/bash
.SHELLFLAGS := -euo pipefail -c

# A file target whose recipe failed is removed rather than left half written for
# the next run to mistake for finished work.
.DELETE_ON_ERROR:

# ////////////////////////////////////////////////////////////////////////////
# THE PRODUCT | What a release is called and what it holds
# ////////////////////////////////////////////////////////////////////////////

# One binary, the declaration of the product it drives, and one folder per
# module. Oak looks for all of it beside its own binary.
APP         := oak
PRODUCT     := oak.yaml
MODULES_DIR := modules

# The single source of truth for this project's version, declared where
# everything else about the product is. It becomes both filenames, the ISO label
# and the tag `v` + this — the `v` belongs to the tag and to nothing else, and
# `make tag` is what writes it, so the two cannot drift apart.
VERSION := $(shell sed -n 's/^version:[[:space:]]*//p' $(PRODUCT))

# Which modules there are is whatever folders are in modules/, so adding one is
# a folder and nothing here has to be kept in step with it.
MODULES := $(notdir $(wildcard $(MODULES_DIR)/*))

# What of a module goes into a release: its declaration and the parts Oak finds
# by name. What is not here — a README, a linter's config — is how the module is
# worked on rather than part of what runs.
MODULE_DECL  := module.yaml
MODULE_PARTS := module.sh data locales tasks hooks

# ////////////////////////////////////////////////////////////////////////////
# OAK | The runtime this is built on
# ////////////////////////////////////////////////////////////////////////////

# The runtime is a project of its own — https://github.com/murkl/oak — and is
# downloaded rather than built, so nothing here needs a Go toolchain.
# OAK_VERSION is named outright rather than followed, so a build of a given
# commit is the same build tomorrow. Written without the `v` its tag carries.
OAK_REPO    := murkl/oak
OAK_VERSION ?= 0.1.0
OAK_ASSET   := oak-linux-amd64
OAK_DIR     := .oak
OAK_BIN     := $(OAK_DIR)/oak
OAK_URL     := https://github.com/$(OAK_REPO)/releases/download/v$(OAK_VERSION)/$(OAK_ASSET)

# ////////////////////////////////////////////////////////////////////////////
# BUILD OUTPUT | One folder, everything a build leaves
# ////////////////////////////////////////////////////////////////////////////

DIST_DIR := dist

# The product under the name it unpacks to, so a download and the folder it came
# out of are the same thing under the same name.
STEM        := arch-os-$(VERSION)
RELEASE_DIR := $(DIST_DIR)/$(STEM)

# Both downloads differ only by extension, so a release page reads as one build
# rather than two. Only x86_64 is built.
TARBALL := $(STEM)-x86_64.tar.gz

# A release's shape made of symlinks into the tree, so every check reads the file
# being edited rather than a copy the last build made of it.
DEV_DIR := .dev

# What `make run` opens. MODULE names one module outright, the way
# `oak --module=installer` does on a machine; without it the interface asks
# which. ARGS is whatever else that run takes — `make run ARGS=--debug` for one
# that touches nothing.
MODULE ?=
ARGS   ?=

# ////////////////////////////////////////////////////////////////////////////
# THE IMAGE | Stock Arch releng, patched to boot into this
# ////////////////////////////////////////////////////////////////////////////

# Two scripts rather than two targets: assembling an archiso profile is a
# script's work, and so is booting a machine to read its console. Each takes
# what it works on as an argument, so neither has to know where a build put it.
ISO_DIR   := iso
ISO_BUILD := $(ISO_DIR)/build.sh
ISO_SMOKE := $(ISO_DIR)/smoke.sh

# What `make smoke` boots: the newest image there is, so `make iso && make
# smoke` needs no argument. Read when it is used rather than when make starts,
# which is what lets the two run in one line.
ISO ?= $(shell ls -t $(DIST_DIR)/*.iso 2>/dev/null | head -1)

# ////////////////////////////////////////////////////////////////////////////
# THE SCRIPTS | Everything checked, by the dialect it is written in
# ////////////////////////////////////////////////////////////////////////////

# POSIX sh, because both run on whatever shell the machine has: the one command
# that installs this, and the one that writes a workflow run's summary.
POSIX_SCRIPTS := get.sh .github/summary.sh

# Bash: what builds and boots the image, and what the image itself runs.
ISO_SCRIPTS := $(ISO_BUILD) $(ISO_SMOKE) $(wildcard $(ISO_DIR)/src/usr/local/bin/*)

# Every script of every module. Oak sources them rather than executing them, so
# none carries a shebang and the dialect comes from each module's .shellcheckrc.
# Looked up when it is used rather than when make starts, so only the two
# targets that read it pay for the search.
MODULE_SCRIPTS = $(shell find $(MODULES_DIR) -name '*.sh')

# Every module's yaml as well, for the check that reads both: a task may write
# its script into the declaration instead of beside it.
MODULE_YAML = $(shell find $(MODULES_DIR) -name '*.yaml')

# ////////////////////////////////////////////////////////////////////////////
# HOUSEKEEPING
# ////////////////////////////////////////////////////////////////////////////

# Everything a build leaves, wherever it leaves it. The runtime in .oak/ is not
# in here: it is a dependency rather than build output.
BUILD_OUTPUT := $(DIST_DIR) $(DEV_DIR) $(ISO_DIR)/archiso $(ISO_DIR)/download

# Empty when there is nothing to elevate, which is the case in CI. Only `clean`
# reaches for it, and only when a plain removal was refused.
SUDO := $(shell [ "$$(id -u)" -eq 0 ] || echo sudo)

.PHONY: all oak build dev run inspect tarball image iso smoke locales \
	locales-check lint fmt check version version-check secrets-check tag clean

# build empties the release it writes, and everything that packages it reads
# what it left. Running them at once would package a half-written folder.
.NOTPARALLEL:

all: build

# Fetches the runtime and checks it against the checksum published beside it.
# Downloaded once and kept: `make oak` fetches it again after OAK_VERSION was
# raised, and `make clean` leaves it alone.
$(OAK_BIN):
	@mkdir -p $(OAK_DIR)
	curl -Lf --progress-bar $(OAK_URL) -o $(OAK_DIR)/$(OAK_ASSET)
	curl -Lf --progress-bar $(OAK_URL).sha256 -o $(OAK_DIR)/$(OAK_ASSET).sha256
	cd $(OAK_DIR) && sha256sum -c $(OAK_ASSET).sha256
	install -m 755 $(OAK_DIR)/$(OAK_ASSET) $@
	@echo "oak $$($@ --version)"

oak:
	rm -rf $(OAK_DIR)
	$(MAKE) $(OAK_BIN)

# The runtime, the product's declaration and a clean copy of every module. The
# folder is emptied first, so what is in it afterwards is this build and nothing
# else. The templates go out again: a .pot is how a module is translated rather
# than part of what it runs.
build: $(OAK_BIN)
	rm -rf $(RELEASE_DIR)
	mkdir -p $(RELEASE_DIR)
	install -m 755 $(OAK_BIN) $(RELEASE_DIR)/$(APP)
	install -m 644 $(PRODUCT) $(RELEASE_DIR)/$(PRODUCT)
	for m in $(MODULES); do \
		dest=$(RELEASE_DIR)/$(MODULES_DIR)/$$m; \
		mkdir -p $$dest; \
		cp $(MODULES_DIR)/$$m/$(MODULE_DECL) $$dest/; \
		for part in $(MODULE_PARTS); do \
			[ -e $(MODULES_DIR)/$$m/$$part ] && cp -r $(MODULES_DIR)/$$m/$$part $$dest/ || true; \
		done; \
	done
	find $(RELEASE_DIR) -name '*.pot' -delete

# The same shape without the build, for working on the sources. The binary is
# copied rather than linked: Oak resolves its own path before looking beside
# itself, so a symlink would send it looking in .oak/ instead.
dev: $(OAK_BIN)
	@mkdir -p $(DEV_DIR)
	@ln -sfn ../$(PRODUCT) $(DEV_DIR)/$(PRODUCT)
	@ln -sfn ../$(MODULES_DIR) $(DEV_DIR)/$(MODULES_DIR)
	@install -m 755 $(OAK_BIN) $(DEV_DIR)/$(APP)

# Arch OS out of the sources, against the modules being edited rather than a
# copy of them made by the last build.
run: dev
	cd $(DEV_DIR) && ./$(APP) $(if $(MODULE),--module=$(MODULE)) $(ARGS)

# Both modules loaded exactly as a run loads them: every task ordered, every
# condition resolved, every question checked against the tasks that read it —
# and the order it all adds up to, which is the one thing nobody writes down.
inspect: dev
	@cd $(DEV_DIR) && ./$(APP) --inspect

# The release as one file, for a stock Arch ISO: unpack it, run ./oak. get.sh
# picks both downloads out of a release by extension, so renaming either one is
# a change here and nowhere else.
tarball: build
	tar -czf $(DIST_DIR)/$(TARBALL) --owner=0 --group=0 --sort=name \
		--transform 's,^,$(STEM)/,' \
		-C $(RELEASE_DIR) $(APP) $(PRODUCT) $(MODULES_DIR)
	cd $(DIST_DIR) && sha256sum $(TARBALL) > $(TARBALL).sha256

# The image, out of the release already in dist/ rather than out of a second
# build of the same sources — which is what CI does with the tarball it
# downloaded. What the image is called is read out of that release, so there is
# nothing to hand down here.
image:
	$(ISO_BUILD) $(CURDIR)/$(RELEASE_DIR)

# The whole way there, for a machine that has nothing yet.
iso: build image

# Boots a built image and waits for the interface to come up in it. The frames
# land beside the image, in dist/.
smoke:
	$(ISO_SMOKE) $(ISO)

# Every template rewritten out of the module it belongs to, and every catalog
# brought up to it. msgmerge keeps every translation whose source text is
# unchanged and marks the rest fuzzy rather than dropping it.
locales: dev
	for m in $(MODULES); do \
		pot=$(MODULES_DIR)/$$m/locales/$$m.pot; \
		(cd $(DEV_DIR) && ./$(APP) --strings --module=$$m) >$$pot; \
		for po in $(MODULES_DIR)/$$m/locales/*.po; do \
			[ -e "$$po" ] || continue; \
			msgmerge --quiet --update --backup=none --no-wrap "$$po" $$pot; \
		done; \
	done

# ////////////////////////////////////////////////////////////////////////////
# CHECKS | What has to pass before anything is committed
# ////////////////////////////////////////////////////////////////////////////

# The version this build carries, for anything outside make that needs it.
version:
	@echo $(VERSION)

# A tag is matched against it, so anything but X.Y.Z would only be found at the
# point where it costs a release.
version-check:
	@echo "$(VERSION)" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$$' \
		|| { echo "$(PRODUCT) declares '$(VERSION)', which is not a version" >&2; exit 1; }

# This project is installed by piping a script into a shell. A credential that
# reached the repository would be handed to everybody who did that. What git
# ignores is skipped, so a build in dist/ is not scanned.
secrets-check:
	gitleaks dir . --redact --no-banner

# A question added or reworded without `make locales` being run is a question no
# translator will ever be shown. And a translation that drops a placeholder is a
# message that breaks where it is printed rather than where it was written.
locales-check: dev
	@for m in $(MODULES); do \
		pot=$(MODULES_DIR)/$$m/locales/$$m.pot; \
		(cd $(DEV_DIR) && ./$(APP) --strings --module=$$m) | diff -u $$pot - \
			|| { echo "$$pot is out of date — run 'make locales'" >&2; exit 1; }; \
		for po in $(MODULES_DIR)/$$m/locales/*.po; do \
			[ -e "$$po" ] || continue; \
			printf '%s: ' "$$po"; msgfmt --check-format --statistics -o /dev/null "$$po" || exit 1; \
		done; \
	done

# The two POSIX scripts are checked as sh, since they run on whatever shell the
# machine has. A module's scripts are checked the way Oak runs them: as bash,
# with module.sh already in scope. actionlint reads the workflows again for what
# a yaml linter cannot see.
#
# The grep at the end is for the one mistake no linter here can see, because it
# is valid shell that only fails on a machine being installed: arch-chroot execs
# what it is given, so a shell builtin handed to it exists nowhere. `command -v`
# is the one that gets written, and it cost two silent test failures in a live
# run before it was found.
lint:
	shellcheck -s sh -S style $(POSIX_SCRIPTS)
	shellcheck -S style $(ISO_SCRIPTS)
	shellcheck -x -S style $(MODULE_SCRIPTS)
	shfmt -d -ln posix -i 4 $(POSIX_SCRIPTS)
	shfmt -d -i 4 $(ISO_SCRIPTS) $(MODULE_SCRIPTS)
	yamllint .
	actionlint
	@! grep -nE 'arch-chroot [^|&;]*[[:space:]](command|type|hash|source|alias)[[:space:]]' \
		$(MODULE_SCRIPTS) $(MODULE_YAML) \
		|| { echo "a shell builtin cannot be run through arch-chroot - see has_command" >&2; exit 1; }

fmt:
	shfmt -w -ln posix -i 4 $(POSIX_SCRIPTS)
	shfmt -w -i 4 $(ISO_SCRIPTS) $(MODULE_SCRIPTS)

# The whole gate, cheapest and loudest first. CI runs this and nothing it adds
# to it, so there is no second definition of green.
check: version-check secrets-check lint inspect locales-check

# ////////////////////////////////////////////////////////////////////////////
# RELEASING
# ////////////////////////////////////////////////////////////////////////////

# The tag that publishes a release, made out of the declared version rather than
# typed — so a tag naming a version this commit does not declare cannot be
# written in the first place. The release workflow refuses one anyway, for a tag
# made on the web page, but by then it exists and has to be deleted again.
#
# It is created and not pushed: pushing it is what publishes, and that is a
# second decision.
tag: version-check
	@[ -z "$$(git status --porcelain)" ] \
		|| { echo "the tree has uncommitted changes — a tag names a commit, not a desk" >&2; exit 1; }
	@git merge-base --is-ancestor HEAD origin/main 2>/dev/null \
		|| { echo "HEAD is not on main — run 'git switch main && git pull' first" >&2; exit 1; }
	@if git rev-parse -q --verify "refs/tags/v$(VERSION)" >/dev/null; then \
		echo "v$(VERSION) exists already — raise version: in $(PRODUCT)" >&2; exit 1; \
	fi
	git tag "v$(VERSION)"
	@echo "push it with:  git push origin v$(VERSION)"

# The downloaded runtime stays: it is a dependency rather than build output.
# `make oak` replaces it.
#
# mkarchiso writes as root, and a build killed before its own cleanup ran leaves
# root-owned files behind. The plain removal is tried first, so an ordinary
# clean never asks for a password; what survives it needs the escalation the
# build itself used — see iso/build.sh.
clean:
	rm -rf $(BUILD_OUTPUT) || $(SUDO) rm -rf $(BUILD_OUTPUT)
