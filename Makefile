# Builds a release: the runtime binary next to the installer tree, with the
# recovery tree beside it — one binary, two trees, which is the only thing a
# machine needs.
#
# release/ is the installer as a machine runs it; dist/ is what a person
# downloads. `tarball` and `iso` each turn the first into one of the second.
#
# VERSION is the single source of truth for this whole project: the short commit
# SHA of HEAD, or "dev" outside a repository.
VERSION := $(shell git rev-parse --short HEAD 2>/dev/null || echo dev)

RELEASE_DIR := release
DIST_DIR    := dist
RUNTIME_BIN := runtime/bin/installer-linux-amd64

# What each tree is, and the only place either is written down. What is not
# listed — a Makefile, a README, a linter's config — is how the tree is worked
# on, not part of what runs.
#
# The recovery is a tree of its own and goes into a folder of its own, which the
# binary runs with `-dir recovery`.
TREE          := installer.yaml lib.sh data locales hooks tasks
RECOVERY      := recovery
RECOVERY_TREE := recovery.yaml lib.sh locales hooks tasks

# Both artefacts of a build carry the same name and differ only by extension, so
# a release page reads as one build rather than two. Only x86_64 is built.
STEM    := archos-$(VERSION)
TARBALL := $(STEM)-x86_64.tar.gz

.PHONY: all build tarball iso lint fmt check clean

# Every target here writes release/, and build empties it first.
.NOTPARALLEL:

all: build

# The runtime binary, plus a clean copy of both trees. The folder is emptied
# first, so what is in it afterwards is this build and nothing else.
build:
	$(MAKE) -C runtime release
	rm -rf $(RELEASE_DIR)
	mkdir -p $(RELEASE_DIR)
	install -m 755 $(RUNTIME_BIN) $(RELEASE_DIR)/installer
	cp -r $(addprefix installer/,$(TREE)) $(RELEASE_DIR)/
	mkdir -p $(RELEASE_DIR)/$(RECOVERY)
	cp -r $(addprefix $(RECOVERY)/,$(RECOVERY_TREE)) $(RELEASE_DIR)/$(RECOVERY)/

# The release as one file, for a stock Arch ISO: unpack it, run ./installer.
# get.sh picks both files out of a release by extension, so renaming either one
# is a change here and nowhere else.
tarball: build
	mkdir -p $(DIST_DIR)
	tar -czf $(DIST_DIR)/$(TARBALL) --owner=0 --group=0 --sort=name \
		--transform 's,^,$(STEM)/,' \
		-C $(RELEASE_DIR) installer $(TREE) $(RECOVERY)
	cd $(DIST_DIR) && sha256sum $(TARBALL) > $(TARBALL).sha256

iso: build
	$(MAKE) -C iso build RELEASE_DIR=../$(RELEASE_DIR) DIST_DIR=../$(DIST_DIR) VERSION=$(VERSION)

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
