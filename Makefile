# Builds a release: the Oak binary with oak.yaml and a modules folder beside it
# — which is the only thing a machine needs.
#
# release/ is Arch OS as a machine runs it; dist/ is what a person downloads.
# `tarball` and `iso` each turn the first into one of the second.
#
# VERSION is the single source of truth for this whole project: the tag this
# commit carries, or the nearest one with the distance and the short SHA after
# it, and "dev" outside a repository. A release is a tag, so a build made on one
# is named after it and every build between two says how far past the last it is.
# It is Arch OS's own — Oak carries a version of its own and is a dependency of
# this, like any other.
VERSION := $(shell git describe --tags --always --dirty 2>/dev/null || echo dev)

RELEASE_DIR := release
DIST_DIR    := dist

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
# this repository is the same build tomorrow.
OAK_REPO    := murkl/oak
OAK_VERSION ?= v1.0.0
OAK_ASSET   := oak-linux-amd64
OAK_DIR     := .oak
OAK_BIN     := $(OAK_DIR)/oak
OAK_URL     := https://github.com/$(OAK_REPO)/releases/download/$(OAK_VERSION)/$(OAK_ASSET)

# What a release is called and what it holds: one binary, the declaration of the
# product it drives, and a folder per module under one modules folder. In the
# source tree each module keeps its own declaration in its own folder; a release
# is that laid out flat around the binary, which is where it looks.
APP         := oak
PRODUCT     := oak.yaml
MODULES_DIR := modules

# Which modules there are is whatever folders are in modules/, so adding one is
# a folder and nothing here has to be kept in step with it.
MODULES := $(notdir $(wildcard $(MODULES_DIR)/*))

# What of a module goes into a release: its own declaration, named after it, and
# the parts Oak finds by name. What is not here — a Makefile, a README, a
# linter's config — is how a module is worked on rather than part of what runs,
# and a part a module does not have is simply not copied.
MODULE_PARTS := lib.sh data locales hooks tasks

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

# Both artefacts of a build carry the same name and differ only by extension, so
# a release page reads as one build rather than two. Only x86_64 is built.
STEM    := arch-os-$(VERSION)
TARBALL := $(STEM)-x86_64.tar.gz

.PHONY: all oak build dev run tarball iso locales lint fmt check clean

# Every target here writes release/, and build empties it first.
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

# The runtime, the product's declaration with this build's version written into
# it, and a clean copy of every module. The folder is emptied first, so what is
# in it afterwards is this build and nothing else.
#
# The translation templates go out again with it: a .pot is the list a catalog
# is filled in from, which is how a module is translated rather than part of
# what it runs — the same reason a Makefile and a README are not copied either.
build: $(OAK_BIN)
	rm -rf $(RELEASE_DIR)
	mkdir -p $(RELEASE_DIR)
	install -m 755 $(OAK_BIN) $(RELEASE_DIR)/$(APP)
	sed 's|^version:.*|version: $(VERSION)|' $(PRODUCT) > $(RELEASE_DIR)/$(PRODUCT)
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
	mkdir -p $(DIST_DIR)
	tar -czf $(DIST_DIR)/$(TARBALL) --owner=0 --group=0 --sort=name \
		--transform 's,^,$(STEM)/,' \
		-C $(RELEASE_DIR) $(APP) $(PRODUCT) $(MODULES_DIR)
	cd $(DIST_DIR) && sha256sum $(TARBALL) > $(TARBALL).sha256

iso: build
	$(MAKE) -C iso build RELEASE_DIR=../$(RELEASE_DIR) DIST_DIR=../$(DIST_DIR) VERSION=$(VERSION)

# Every template and every catalog, brought up to what the modules now say.
locales:
	set -e; for m in $(MODULES); do $(MAKE) -C $(MODULES_DIR)/$$m locales; done

# get.sh is POSIX sh, so it is checked as such rather than as bash. The yaml is
# checked here rather than per component: one rule set over one kind of file.
# actionlint reads the workflows again for what a yaml linter cannot see.
lint:
	shellcheck -s sh -S style get.sh
	shfmt -d -ln posix -i 4 get.sh
	yamllint .
	actionlint

fmt:
	shfmt -w -ln posix -i 4 get.sh

# What has to pass before anything is committed.
check: lint
	set -e; for m in $(MODULES); do $(MAKE) -C $(MODULES_DIR)/$$m check; done
	$(MAKE) -C iso check

# The downloaded runtime stays: it is a dependency rather than build output.
# `make oak` replaces it.
clean:
	$(MAKE) -C iso clean
	rm -rf $(RELEASE_DIR) $(DIST_DIR) $(DEV_DIR)
