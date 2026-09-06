# A release is the Oak binary with oak.yaml and a modules folder beside it,
# which is the only thing a machine needs. Everything a build produces lands in
# dist/:
#
#   dist/arch-os-2.0.0/                 the product: oak, oak.yaml, modules/
#   dist/arch-os-2.0.0-x86_64.tar.gz    that folder as one file  (+ .sha256)
#   dist/arch-os-2.0.0-x86_64.iso       the bootable image       (+ .sha256)
#
# `build` writes the first, `tarball` and `iso` each turn it into one of the
# others. Nothing is ever assembled twice.

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
# and the tag `v` + this — the `v` belongs to the tag and to nothing else.
VERSION := $(shell sed -n 's/^version:[[:space:]]*//p' $(PRODUCT))

# Which modules there are is whatever folders are in modules/, so adding one is
# a folder and nothing here has to be kept in step with it.
MODULES := $(notdir $(wildcard $(MODULES_DIR)/*))

# What of a module goes into a release: its declaration and the parts Oak finds
# by name. What is not here — a README, a linter's config — is how the module is
# worked on rather than part of what runs.
MODULE_PARTS := lib.sh data locales hooks tasks

# ////////////////////////////////////////////////////////////////////////////
# OAK | The runtime this is built on
# ////////////////////////////////////////////////////////////////////////////

# The runtime is a project of its own — https://github.com/murkl/oak — and is
# downloaded rather than built, so nothing here needs a Go toolchain.
# OAK_VERSION is named outright rather than followed, so a build of a given
# commit is the same build tomorrow. Written without the `v` its tag carries.
OAK_REPO    := murkl/oak
OAK_VERSION ?= 1.0.0
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

# The shell that is not part of a module: the one command that installs this,
# and the one that writes a workflow run's summary. POSIX sh, both of them.
SCRIPTS := get.sh .github/summary.sh

# Every script of every module. Oak sources them rather than executing them, so
# none carries a shebang and the dialect comes from each module's .shellcheckrc.
MODULE_SCRIPTS := $(shell find $(MODULES_DIR) -name '*.sh')

.PHONY: all oak build dev run inspect tarball iso locales locales-check lint fmt check version version-check clean

# build empties the release it writes, and the two targets that package it read
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
	set -e; for m in $(MODULES); do \
		dest=$(RELEASE_DIR)/$(MODULES_DIR)/$$m; \
		mkdir -p $$dest; \
		cp $(MODULES_DIR)/$$m/$$m.yaml $$dest/; \
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

# The release as one file, for a stock Arch ISO: unpack it, run ./oak. get.sh
# picks both downloads out of a release by extension, so renaming either one is
# a change here and nowhere else.
tarball: build
	tar -czf $(DIST_DIR)/$(TARBALL) --owner=0 --group=0 --sort=name \
		--transform 's,^,$(STEM)/,' \
		-C $(RELEASE_DIR) $(APP) $(PRODUCT) $(MODULES_DIR)
	cd $(DIST_DIR) && sha256sum $(TARBALL) > $(TARBALL).sha256

# The image is built out of the release beside it and named after the version
# that release declares, so there is nothing to hand down here.
iso: build
	$(MAKE) -C iso build RELEASE_DIR=../$(RELEASE_DIR) DIST_DIR=../$(DIST_DIR)

# Both modules loaded exactly as a run loads them: every task ordered, every
# condition resolved, every question checked against the tasks that read it —
# and the order it all adds up to, which is the one thing nobody writes down.
inspect: dev
	@cd $(DEV_DIR) && ./$(APP) --inspect

# Every template rewritten out of the module it belongs to, and every catalog
# brought up to it. msgmerge keeps every translation whose source text is
# unchanged and marks the rest fuzzy rather than dropping it.
locales: dev
	set -e; for m in $(MODULES); do \
		pot=$(MODULES_DIR)/$$m/locales/$$m.pot; \
		(cd $(DEV_DIR) && ./$(APP) --strings --module=$$m) >$$pot; \
		for po in $(MODULES_DIR)/$$m/locales/*.po; do \
			msgmerge --quiet --update --backup=none --no-wrap "$$po" $$pot; \
		done; \
	done

# A question added or reworded without `make locales` being run is a question no
# translator will ever be shown. And a translation that drops a placeholder is a
# message that breaks where it is printed rather than where it was written.
locales-check: dev
	@set -e; for m in $(MODULES); do \
		pot=$(MODULES_DIR)/$$m/locales/$$m.pot; \
		(cd $(DEV_DIR) && ./$(APP) --strings --module=$$m) | diff -u $$pot - \
			|| { echo "$$pot is out of date — run 'make locales'" >&2; exit 1; }; \
		for po in $(MODULES_DIR)/$$m/locales/*.po; do \
			printf '%s: ' "$$po"; msgfmt --check-format --statistics -o /dev/null "$$po" || exit 1; \
		done; \
	done

# The version this build carries, for anything outside make that needs it.
version:
	@echo $(VERSION)

# A tag is matched against it, so anything but X.Y.Z would only be found at the
# point where it costs a release.
version-check:
	@echo "$(VERSION)" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$$' \
		|| { echo "$(PRODUCT) declares '$(VERSION)', which is not a version" >&2; exit 1; }

# The two above are checked as POSIX sh, since get.sh runs on whatever shell the
# machine has. A module's scripts are checked the way Oak runs them: as bash,
# with lib.sh already in scope. actionlint reads the workflows again for what a
# yaml linter cannot see.
lint:
	shellcheck -s sh -S style $(SCRIPTS)
	shfmt -d -ln posix -i 4 $(SCRIPTS)
	shellcheck -x $(MODULE_SCRIPTS)
	shfmt -d -i 4 $(MODULE_SCRIPTS)
	yamllint .
	actionlint

fmt:
	shfmt -w -ln posix -i 4 $(SCRIPTS)
	shfmt -w -i 4 $(MODULE_SCRIPTS)

# What has to pass before anything is committed.
check: version-check lint inspect locales-check
	$(MAKE) -C iso check

# The downloaded runtime stays: it is a dependency rather than build output.
# `make oak` replaces it.
clean:
	$(MAKE) -C iso clean
	rm -rf $(DIST_DIR) $(DEV_DIR)
