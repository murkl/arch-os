# The only task runner in the repository. What CI runs is these targets, so a
# rule that holds at a desk holds there.
#
#   dist/arch-os-2.0.0/                 the product: oak, oak.yaml, modules/
#   dist/arch-os-2.0.0-x86_64.tar.gz    that folder as one file
#   dist/arch-os-2.0.0-x86_64.iso       the bootable image
#
# `build` writes the first, `tarball` and `image` each turn it into one of the
# others. Nothing is ever assembled twice.

# Every recipe is one bash with -e, -u and pipefail, so a command that fails in
# the middle of a line fails the target rather than the next one. A file target
# whose recipe failed is removed rather than left half written.
SHELL       := /bin/bash
.SHELLFLAGS := -euo pipefail -c
.DELETE_ON_ERROR:

# ////////////////////////////////////////////////////////////////////////////
# THE PRODUCT | What a release is called and what it holds
# ////////////////////////////////////////////////////////////////////////////

# One binary, the declaration of the product it drives, and one folder per
# module. Oak looks for all of it beside its own binary.
APP         := oak
PRODUCT     := oak.yaml
MODULES_DIR := modules

# The single source of truth for this project's version. It becomes both
# filenames, the ISO label and the tag `v` + this - the `v` belongs to the tag
# and to nothing else, and `make tag` is what writes it.
VERSION := $(shell sed -n 's/^version:[[:space:]]*//p' $(PRODUCT))

# Whatever folders are in modules/, so adding one is a folder and nothing here
# has to be kept in step with it.
MODULES := $(notdir $(wildcard $(MODULES_DIR)/*))

# What of a module goes into a release: its declaration and the parts Oak finds
# by name. A README and a linter's config are how it is worked on, not part of
# what runs.
MODULE_DECL  := module.yaml
MODULE_PARTS := module.sh data locales tasks hooks

# ////////////////////////////////////////////////////////////////////////////
# OAK | The runtime this is built on
# ////////////////////////////////////////////////////////////////////////////

# A project of its own - https://github.com/murkl/oak - downloaded rather than
# built, so nothing here needs a Go toolchain. The version is named outright
# rather than followed, so a build of a given commit is the same build tomorrow.
# Written without the `v` its tag carries.
OAK_REPO    := murkl/oak
OAK_VERSION ?= 0.3.2
OAK_ASSET   := oak-linux-amd64
OAK_DIR     := .oak
OAK_BIN     := $(OAK_DIR)/oak
OAK_URL     := https://github.com/$(OAK_REPO)/releases/download/v$(OAK_VERSION)/$(OAK_ASSET)
OAK_API     := https://api.github.com/repos/$(OAK_REPO)/releases/tags/v$(OAK_VERSION)

# https even after a redirect, the same flags get.sh fetches with: -L on its own
# would follow a 302 into plain http, where the answer is whoever is on the wire
# — and the answer here is the program that goes on to write a disk.
CURL := curl --proto '=https' --proto-redir '=https' -Lf --progress-bar

# ////////////////////////////////////////////////////////////////////////////
# BUILD OUTPUT | One folder, everything a build leaves
# ////////////////////////////////////////////////////////////////////////////

DIST_DIR := dist

# The product under the name it unpacks to, so a download and the folder it came
# out of are the same thing under the same name. Only x86_64 is built.
STEM        := arch-os-$(VERSION)
RELEASE_DIR := $(DIST_DIR)/$(STEM)
TARBALL     := $(STEM)-x86_64.tar.gz

# A release's shape made of symlinks into the tree, so every check reads the file
# being edited rather than a copy the last build made of it.
DEV_DIR := .dev

# What `make run` opens. MODULE names one outright, the way
# `oak --module=installer` does on a machine; ARGS is whatever else it takes.
MODULE ?=
ARGS   ?=

# ////////////////////////////////////////////////////////////////////////////
# THE IMAGE | Stock Arch releng, patched to boot into this
# ////////////////////////////////////////////////////////////////////////////

# Scripts rather than targets: assembling an archiso profile is a script's work,
# and so is booting a machine to read its console or reading a font's glyph
# table. Each takes what it works on as an argument.
ISO_DIR    := iso
ISO_BUILD  := $(ISO_DIR)/build.sh
ISO_SMOKE  := $(ISO_DIR)/smoke.sh
ISO_GLYPHS := $(ISO_DIR)/glyphs.sh

# The newest image there is, so `make iso && make smoke` needs no argument. Read
# when it is used rather than when make starts, which is what lets the two run
# in one line.
ISO ?= $(shell ls -t $(DIST_DIR)/*.iso 2>/dev/null | head -1)

# ////////////////////////////////////////////////////////////////////////////
# THE SCRIPTS | Everything checked, by the dialect it is written in
# ////////////////////////////////////////////////////////////////////////////

# POSIX sh, because both run on whatever shell the machine has.
POSIX_SCRIPTS := get.sh .github/summary.sh

# Bash: what builds and boots the image, and what the image itself runs.
ISO_SCRIPTS := $(ISO_BUILD) $(ISO_SMOKE) $(ISO_GLYPHS) $(wildcard $(ISO_DIR)/src/usr/local/bin/*)

# Every script of every module, and every yaml for the check that reads both.
# Looked up when they are used, so only the targets that read them pay for it.
MODULE_SCRIPTS = $(shell find $(MODULES_DIR) -name '*.sh')
MODULE_YAML    = $(shell find $(MODULES_DIR) -name '*.yaml')

# The shell a module ships as a file of somebody's home rather than as a task.
# Found by the name it lands under, since a .bashrc carries no extension. The
# other three in that folder are out: zsh and fish are not dialects shellcheck
# reads, and the handover fragment is placeholders rather than shell.
MODULE_SHELL = $(wildcard $(MODULES_DIR)/*/tasks/@*/*/bashrc $(MODULES_DIR)/*/tasks/@*/*/aliases)

# Everything a module can put on a screen: the declarations, the scripts, the
# tables and every catalog. The READMEs are the one thing here nobody reads on
# a console.
MODULE_TEXT = $(shell find $(MODULES_DIR) -type f ! -name '*.md')

# ////////////////////////////////////////////////////////////////////////////
# HOUSEKEEPING
# ////////////////////////////////////////////////////////////////////////////

# Everything a build leaves. The runtime in .oak/ is not in here: it is a
# dependency rather than build output.
BUILD_OUTPUT := $(DIST_DIR) $(DEV_DIR) $(ISO_DIR)/archiso $(ISO_DIR)/download

# Empty when there is nothing to elevate, which is the case in CI.
SUDO := $(shell [ "$$(id -u)" -eq 0 ] || echo sudo)

# The pictures in docs/, both generated so neither can drift from what a run
# shows: the screenshots by driving the modules on a pty, the banner by
# collaging two of them under the wordmark read from oak.yaml.
#
# Which pages are taken is docs/screenshots.yaml, and every run is started with
# --debug: no disk is partitioned, nothing is mounted, nothing restarts.
#
# They need chromium, imagemagick, python-pyte and python-yaml, which a build
# does not, so they stay out of `check` and are run by hand.
BANNER_CARDS   := docs/screenshots/installer.png docs/screenshots/installing.png
BANNER_TAGLINE := A minimal, robust and reproducible Arch Linux base. Installer and Recovery on one image.
BANNER_CELL    := 9

.PHONY: all oak build dev run inspect tarball image iso smoke locales \
	locales-check glyphs-check lint fmt check version version-check \
	secrets-check tag screenshots banner docs clean

# build empties the release it writes, and everything that packages it reads
# what it left. Running them at once would package a half-written folder.
.NOTPARALLEL:

all: build

# Downloaded once and kept, checked against the checksum GitHub publishes for
# that asset - the release carries no checksum file of its own, and the digest
# below is what the release page prints under the download. `make oak` fetches
# it again after OAK_VERSION was raised.
$(OAK_BIN):
	@mkdir -p $(OAK_DIR)
	$(CURL) $(OAK_URL) -o $(OAK_DIR)/$(OAK_ASSET)
	digest="$$($(CURL) -s $(OAK_API) | awk -v asset='"name": "$(OAK_ASSET)"' \
		'index($$0, asset) { want = 1 } \
		 want && !seen && /"digest": *"sha256:/ { seen = 1; sub(/.*sha256:/, ""); sub(/".*/, ""); print }')"; \
	[ -n "$$digest" ] \
		|| { echo "$(OAK_REPO) publishes no checksum for $(OAK_ASSET) at v$(OAK_VERSION)" >&2; exit 1; }; \
	echo "$$digest  $(OAK_DIR)/$(OAK_ASSET)" | sha256sum -c -
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

# Arch OS out of the sources, against the modules being edited.
run: dev
	cd $(DEV_DIR) && ./$(APP) $(if $(MODULE),--module=$(MODULE)) $(ARGS)

# Every module loaded exactly as a run loads it: every task ordered, every
# condition resolved, every question checked against the tasks that read it -
# and the order it all adds up to, which is the one thing nobody writes down.
inspect: dev
	@cd $(DEV_DIR) && ./$(APP) --inspect

# The release as one file, for a stock Arch ISO: unpack it, run ./oak.
tarball: build
	tar -czf $(DIST_DIR)/$(TARBALL) --owner=0 --group=0 --sort=name \
		--transform 's,^,$(STEM)/,' \
		-C $(RELEASE_DIR) $(APP) $(PRODUCT) $(MODULES_DIR)

# The image, out of the release already in dist/ rather than out of a second
# build of the same sources. What it is called is read out of that release.
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

# This project is installed by piping a script into a shell, so a credential
# that reached the repository would be handed to everybody who did that.
secrets-check:
	gitleaks dir . --redact --no-banner

# A question reworded without `make locales` being run is a question no
# translator will ever be shown, and a translation that drops a placeholder is a
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

# The two POSIX scripts are checked as sh; a module's are checked the way Oak
# runs them, as bash with module.sh already in scope. actionlint reads the
# workflows again for what a yaml linter cannot see.
#
# The first grep is for the one mistake no linter here can see, because it is
# valid shell that only fails on a machine being installed: arch-chroot execs
# what it is given, so a shell builtin handed to it exists nowhere. It cost two
# silent test failures in a live run before it was found.
#
# The second keeps the first honest. Everything above reads *.sh and nothing
# reads shell written into a yaml, so a block scalar is the one place a script
# can go unchecked - and a failure in one names the command instead of a file
# and a line. A single line calling a function by name is still fine: that
# function is in module.sh, where it is checked. `requires:` is deliberately not
# on that list - it is what the module says about the machine it belongs on, and
# it belongs in the declaration where somebody looking for it looks.
lint:
	shellcheck -s sh -S style $(POSIX_SCRIPTS)
	shellcheck -S style $(ISO_SCRIPTS)
	shellcheck -x -S style $(MODULE_SCRIPTS)
	shellcheck -s bash -S style -e SC1091 $(MODULE_SHELL)
	shfmt -d -ln posix -i 4 $(POSIX_SCRIPTS)
	shfmt -d -i 4 $(ISO_SCRIPTS) $(MODULE_SCRIPTS) $(MODULE_SHELL)
	yamllint .
	actionlint
	@! grep -nE 'arch-chroot [^|&;]*[[:space:]](command|type|hash|source|alias)[[:space:]]' \
		$(MODULE_SCRIPTS) $(MODULE_YAML) \
		|| { echo "a shell builtin cannot be run through arch-chroot - see has_command" >&2; exit 1; }
	@! grep -nE '^[[:space:]]*(script|test|command|prefill|apply|answer):[[:space:]]*[|>]' $(MODULE_YAML) \
		|| { echo "a task's or hook's shell is linted by nothing inside a yaml and gives a failure no line to point at - put it in the .sh file beside it" >&2; exit 1; }

fmt:
	shfmt -w -ln posix -i 4 $(POSIX_SCRIPTS)
	shfmt -w -i 4 $(ISO_SCRIPTS) $(MODULE_SCRIPTS) $(MODULE_SHELL)

# A virtual console holds one font and that font holds one table of glyphs, so a
# character outside it is a box on the screen - in whichever language it happens
# to be in, which is not the one whoever wrote it reads. After locales-check,
# which is what makes the catalogs it reads the current ones.
glyphs-check:
	@$(ISO_GLYPHS) $(MODULE_TEXT)

# The whole gate, cheapest and loudest first. CI runs this and nothing it adds
# to it, so there is no second definition of green.
check: version-check secrets-check lint inspect locales-check glyphs-check

# ////////////////////////////////////////////////////////////////////////////
# RELEASING
# ////////////////////////////////////////////////////////////////////////////

# The tag that publishes a release, made out of the declared version rather than
# typed - so a tag naming a version this commit does not declare cannot be
# written in the first place. It is created and not pushed: pushing it is what
# publishes, and that is a second decision.
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

# ////////////////////////////////////////////////////////////////////////////
# DOCUMENTATION | The pictures the README is made of
# ////////////////////////////////////////////////////////////////////////////

screenshots: dev
	python3 docs/screenshots.py --product $(DEV_DIR)

banner:
	python3 docs/banner.py \
		--product $(PRODUCT) \
		--logo docs/logo.svg \
		$(foreach c,$(BANNER_CARDS),--card $(c)) \
		--tagline "$(BANNER_TAGLINE)" \
		--cell $(BANNER_CELL)

# The banner collages the screenshots, so it comes after them - which is what
# .NOTPARALLEL above holds, whatever -j says.
docs: screenshots banner

# The downloaded runtime stays: it is a dependency rather than build output.
#
# mkarchiso writes as root, and a build killed before its own cleanup ran leaves
# root-owned files behind. The plain removal is tried first, so an ordinary
# clean never asks for a password.
clean:
	rm -rf $(BUILD_OUTPUT) || $(SUDO) rm -rf $(BUILD_OUTPUT)
