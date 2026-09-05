# Builds a release: the Oak binary with oak.yaml and a modules folder beside it
# — which is the only thing a machine needs.
#
# Everything a build produces lands in one folder. dist/ holds the product laid
# out as a machine runs it, and beside it the files a person downloads:
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

# One binary, the declaration of the product it drives, and a folder per module
# under one modules folder. In the source tree each module keeps its own
# declaration in its own folder; a release is that laid out flat around the
# binary, which is where it looks.
APP         := oak
PRODUCT     := oak.yaml
MODULES_DIR := modules

# VERSION is the single source of truth for this whole project, and it is
# declared where everything else about the product is: `version:` in oak.yaml.
# The build carries it into both filenames and, upper-cased, onto the ISO label.
#
# A release is the tag `v` + this, pushed once the version is on main — the `v`
# belongs to the tag and to nothing else. The release workflow refuses a tag
# that says anything other than what this line does, so the two cannot drift.
#
# It is Arch OS's own version. Oak carries one of its own and is a dependency of
# this, like any other.
VERSION := $(shell sed -n 's/^version:[[:space:]]*//p' $(PRODUCT))

# Which modules there are is whatever folders are in modules/, so adding one is
# a folder and nothing here has to be kept in step with it.
MODULES := $(notdir $(wildcard $(MODULES_DIR)/*))

# What of a module goes into a release: its own declaration, named after it, and
# the parts Oak finds by name. What is not here — a Makefile, a README, a
# linter's config — is how a module is worked on rather than part of what runs,
# and a part a module does not have is simply not copied.
MODULE_PARTS := lib.sh data locales hooks tasks

# ////////////////////////////////////////////////////////////////////////////
# OAK | The runtime this is built on
# ////////////////////////////////////////////////////////////////////////////

# The interface, the questions and the order the work happens in are not built
# here. They are Oak, a project of its own, and what this repository holds is
# the Arch Linux half: one declaration, two modules and the image they ship on.
#
# https://github.com/murkl/oak
#
# The binary is downloaded rather than built, so nothing here needs a Go
# toolchain. OAK_VERSION is the release it is taken from, named outright rather
# than followed: the runtime is a dependency, and a build of a given commit of
# this repository is the same build tomorrow. Written without the `v` its tag
# carries, the way every version in this project is.
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

# The product, as a machine runs it, under the name it unpacks to: a download
# and the folder it came out of are the same thing under the same name.
STEM        := arch-os-$(VERSION)
RELEASE_DIR := $(DIST_DIR)/$(STEM)

# Both downloads of a build carry the same name and differ only by extension, so
# a release page reads as one build rather than two. Only x86_64 is built.
TARBALL := $(STEM)-x86_64.tar.gz

# The shape a release has, made out of the sources with nothing copied: an
# oak.yaml with a modules folder beside it, both symlinks into the tree. It is
# what Oak is pointed at while this is worked on, so a check reads the file
# being edited rather than a copy of it made by the last build.
DEV_DIR := .dev

# What `make run` opens. MODULE names one module outright, the way `oak
# installer` does on a machine; without it the interface asks which. ARGS is
# whatever else that run takes — `make run ARGS=--debug` for one that touches
# nothing.
MODULE ?=
ARGS   ?=

# The shell that is not part of a module: the one command that installs this,
# and the one that writes a workflow run's summary.
SCRIPTS := get.sh .github/summary.sh

.PHONY: all oak build dev run tarball iso locales lint fmt check version version-check clean

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
# else.
#
# The declaration is copied rather than rewritten: it already carries the
# version, which is where the version is decided.
#
# The translation templates go out again with it: a .pot is the list a catalog
# is filled in from, which is how a module is translated rather than part of
# what it runs — the same reason a Makefile and a README are not copied either.
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

# The same shape without the build, for working on the sources. Every Makefile
# that runs Oak points at this.
#
# The binary is copied rather than linked: Oak resolves its own path before
# looking beside itself, so a symlink would send it looking in .oak/ instead.
dev: $(OAK_BIN)
	@mkdir -p $(DEV_DIR)
	@ln -sfn ../$(PRODUCT) $(DEV_DIR)/$(PRODUCT)
	@ln -sfn ../$(MODULES_DIR) $(DEV_DIR)/$(MODULES_DIR)
	@install -m 755 $(OAK_BIN) $(DEV_DIR)/$(APP)

# Arch OS out of the sources, against the modules being edited rather than a
# copy of them made by the last build.
run: dev
	cd $(DEV_DIR) && ./$(APP) $(MODULE) $(ARGS)

# The release as one file, for a stock Arch ISO: unpack it, run ./oak.
# get.sh picks both files out of a release by extension, so renaming either one
# is a change here and nowhere else.
tarball: build
	tar -czf $(DIST_DIR)/$(TARBALL) --owner=0 --group=0 --sort=name \
		--transform 's,^,$(STEM)/,' \
		-C $(RELEASE_DIR) $(APP) $(PRODUCT) $(MODULES_DIR)
	cd $(DIST_DIR) && sha256sum $(TARBALL) > $(TARBALL).sha256

# The image is built out of the release beside it and named after the version
# that release declares, so there is nothing to hand down here.
iso: build
	$(MAKE) -C iso build RELEASE_DIR=../$(RELEASE_DIR) DIST_DIR=../$(DIST_DIR)

# Every template and every catalog, brought up to what the modules now say.
locales:
	set -e; for m in $(MODULES); do $(MAKE) -C $(MODULES_DIR)/$$m locales; done

# The version this build carries, for anything outside make that needs it.
version:
	@echo $(VERSION)

# It is a release's name, both filenames and half of an ISO label, and a tag is
# matched against it. Anything else would be found at the point where it costs
# a release, which is the one place it must not be found.
version-check:
	@echo "$(VERSION)" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$$' \
		|| { echo "$(PRODUCT) declares '$(VERSION)', which is not a version" >&2; exit 1; }

# Both are POSIX sh, so they are checked as such rather than as bash: get.sh
# runs before anything of this project has been downloaded, on whatever shell
# the machine has, and summary.sh is one table. The yaml is checked here rather
# than per component: one rule set over one kind of file. actionlint reads the
# workflows again for what a yaml linter cannot see, shellcheck included, so the
# shell inside them is held to the same rules as the shell beside them.
lint:
	shellcheck -s sh -S style $(SCRIPTS)
	shfmt -d -ln posix -i 4 $(SCRIPTS)
	yamllint .
	actionlint

fmt:
	shfmt -w -ln posix -i 4 $(SCRIPTS)

# What has to pass before anything is committed.
check: version-check lint
	set -e; for m in $(MODULES); do $(MAKE) -C $(MODULES_DIR)/$$m check; done
	$(MAKE) -C iso check

# The downloaded runtime stays: it is a dependency rather than build output.
# `make oak` replaces it.
clean:
	$(MAKE) -C iso clean
	rm -rf $(DIST_DIR) $(DEV_DIR)
