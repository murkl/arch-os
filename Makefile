# Builds a release: the runtime binary with runtime.yaml and a modules folder
# beside it — which is the only thing a machine needs.
#
# release/ is Arch OS as a machine runs it; dist/ is what a person downloads.
# `tarball` and `iso` each turn the first into one of the second.
#
# VERSION is the single source of truth for this whole project: the short commit
# SHA of HEAD, or "dev" outside a repository.
VERSION := $(shell git rev-parse --short HEAD 2>/dev/null || echo dev)

RELEASE_DIR := release
DIST_DIR    := dist
RUNTIME_BIN := runtime/bin/runtime-linux-amd64

# What a release is called and what it holds: one binary, the declaration of the
# product it drives, and a folder per module under one modules folder. In the
# source tree each component keeps its own declaration in its own folder; a
# release is that laid out flat around the binary, which is where it looks.
APP          := runtime
RUNTIME      := runtime.yaml
RUNTIME_SRC  := runtime/$(RUNTIME)
MODULES_DIR  := modules

# Which modules there are is whatever folders are in modules/, so adding one is
# a folder and nothing here has to be kept in step with it.
MODULES := $(notdir $(wildcard $(MODULES_DIR)/*))

# What of a module goes into a release: its own declaration, named after it, and
# the parts the runtime finds by name. What is not here — a Makefile, a README,
# a linter's config — is how a module is worked on rather than part of what
# runs, and a part a module does not have is simply not copied.
MODULE_PARTS := lib.sh data locales hooks tasks

# The shape a release has, made out of the sources with nothing copied: a
# runtime.yaml with a modules folder beside it, both symlinks into the tree. It
# is what the runtime is pointed at while it is worked on, so a check reads the
# file being edited rather than a copy of it made by the last build.
DEV_DIR := .dev

# Both artefacts of a build carry the same name and differ only by extension, so
# a release page reads as one build rather than two. Only x86_64 is built.
STEM    := arch-os-$(VERSION)
TARBALL := $(STEM)-x86_64.tar.gz

.PHONY: all build dev tarball iso locales lint fmt check clean

# Every target here writes release/, and build empties it first.
.NOTPARALLEL:

all: build

# The runtime binary, plus a clean copy of every module. The folder is emptied
# first, so what is in it afterwards is this build and nothing else.
#
# The translation templates go out again with it: a .pot is the list a catalog
# is filled in from, which is how a module is translated rather than part of
# what it runs — the same reason a Makefile and a README are not copied either.
build:
	$(MAKE) -C runtime release
	rm -rf $(RELEASE_DIR)
	mkdir -p $(RELEASE_DIR)
	install -m 755 $(RUNTIME_BIN) $(RELEASE_DIR)/$(APP)
	cp $(RUNTIME_SRC) $(RELEASE_DIR)/
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
# that runs the runtime points at this.
dev:
	@mkdir -p $(DEV_DIR)
	@ln -sfn ../$(RUNTIME_SRC) $(DEV_DIR)/$(RUNTIME)
	@ln -sfn ../$(MODULES_DIR) $(DEV_DIR)/$(MODULES_DIR)

# The release as one file, for a stock Arch ISO: unpack it, run ./runtime.
# get.sh picks both files out of a release by extension, so renaming either one
# is a change here and nowhere else.
tarball: build
	mkdir -p $(DIST_DIR)
	tar -czf $(DIST_DIR)/$(TARBALL) --owner=0 --group=0 --sort=name \
		--transform 's,^,$(STEM)/,' \
		-C $(RELEASE_DIR) $(APP) $(RUNTIME) $(MODULES_DIR)
	cd $(DIST_DIR) && sha256sum $(TARBALL) > $(TARBALL).sha256

iso: build
	$(MAKE) -C iso build RELEASE_DIR=../$(RELEASE_DIR) DIST_DIR=../$(DIST_DIR) VERSION=$(VERSION)

# Every template and every catalog, brought up to what the code and the modules
# now say. The modules are asked through the runtime, so it is built first.
locales:
	$(MAKE) -C runtime locales
	$(MAKE) -C runtime build
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
	$(MAKE) -C runtime check
	set -e; for m in $(MODULES); do $(MAKE) -C $(MODULES_DIR)/$$m check; done
	$(MAKE) -C iso check

clean:
	$(MAKE) -C runtime clean
	$(MAKE) -C iso clean
	rm -rf $(RELEASE_DIR) $(DIST_DIR) $(DEV_DIR)
