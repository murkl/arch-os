# Builds a release: the runtime binary with its modules beside it, a folder
# each — which is the only thing a machine needs.
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
# product it drives, and one folder per module. runtime.yaml is the only place
# the module list is written down — this reads it back rather than keeping a
# second copy that could disagree with it.
APP     := runtime
RUNTIME := runtime.yaml

# Which modules there are is read back out of the declaration the machine reads,
# so adding one is a line there and a folder — and nothing here has to be kept
# in step with it.
MODULES := $(shell sed -n '/^modules:/,/^[^ -]/ s/^ *- *//p' $(RUNTIME))

# What of a module goes into a release: its own declaration, named after it, and
# the parts the runtime finds by name. What is not here — a Makefile, a README,
# a linter's config — is how a module is worked on rather than part of what
# runs, and a part a module does not have is simply not copied.
MODULE_PARTS := lib.sh data locales hooks tasks

# Both artefacts of a build carry the same name and differ only by extension, so
# a release page reads as one build rather than two. Only x86_64 is built.
STEM    := arch-os-$(VERSION)
TARBALL := $(STEM)-x86_64.tar.gz

.PHONY: all build tarball iso locales lint fmt check clean

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
	cp $(RUNTIME) $(RELEASE_DIR)/
	set -e; for m in $(MODULES); do \
		mkdir -p $(RELEASE_DIR)/$$m; \
		cp $$m/$$m.yaml $(RELEASE_DIR)/$$m/; \
		for part in $(MODULE_PARTS); do \
			[ -e $$m/$$part ] && cp -r $$m/$$part $(RELEASE_DIR)/$$m/ || true; \
		done; \
	done
	find $(RELEASE_DIR) -name '*.pot' -delete

# The release as one file, for a stock Arch ISO: unpack it, run ./runtime.
# get.sh picks both files out of a release by extension, so renaming either one
# is a change here and nowhere else.
tarball: build
	mkdir -p $(DIST_DIR)
	tar -czf $(DIST_DIR)/$(TARBALL) --owner=0 --group=0 --sort=name \
		--transform 's,^,$(STEM)/,' \
		-C $(RELEASE_DIR) $(APP) $(RUNTIME) $(MODULES)
	cd $(DIST_DIR) && sha256sum $(TARBALL) > $(TARBALL).sha256

iso: build
	$(MAKE) -C iso build RELEASE_DIR=../$(RELEASE_DIR) DIST_DIR=../$(DIST_DIR) VERSION=$(VERSION)

# Every template and every catalog, brought up to what the code and the modules
# now say. The modules are asked through the runtime, so it is built first.
locales:
	$(MAKE) -C runtime locales
	$(MAKE) -C runtime build
	$(MAKE) -C installer locales
	$(MAKE) -C recovery locales

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
	$(MAKE) -C installer check
	$(MAKE) -C recovery check
	$(MAKE) -C iso check

clean:
	$(MAKE) -C runtime clean
	$(MAKE) -C iso clean
	rm -rf $(RELEASE_DIR) $(DIST_DIR)
