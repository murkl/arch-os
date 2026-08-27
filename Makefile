# Builds a release: the runtime binary next to its installer.yaml and
# tasks/ — the only thing the runtime looks for, and the only thing an
# installation needs (see runtime/README.md). `iso` turns that release into a
# bootable image; nothing here builds one on its own.
#
# VERSION is the single source of truth this whole project uses: the short
# commit SHA of HEAD, or "dev" outside a repository.
VERSION := $(shell git rev-parse --short HEAD 2>/dev/null || echo dev)

RELEASE_DIR := release
RUNTIME_BIN := runtime/bin/installer-linux-amd64

.PHONY: all build iso check clean

all: build

# The runtime binary, plus a clean copy of the setup tree — no Makefile, no
# README, nothing meant for a developer rather than a machine being installed
# onto.
build:
	$(MAKE) -C runtime release
	mkdir -p $(RELEASE_DIR)
	install -m 755 $(RUNTIME_BIN) $(RELEASE_DIR)/installer
	cp setup/installer.yaml $(RELEASE_DIR)/installer.yaml
	rm -rf $(RELEASE_DIR)/tasks
	cp -r setup/tasks $(RELEASE_DIR)/tasks

# build, then the ISO on top of it, into release/iso. What CI runs on a merge
# into main.
iso: build
	$(MAKE) -C iso build RELEASE_DIR=../$(RELEASE_DIR) VERSION=$(VERSION)

# The one command that has to pass before anything is committed.
check:
	$(MAKE) -C runtime check
	$(MAKE) -C setup check
	$(MAKE) -C iso check

clean:
	$(MAKE) -C runtime clean
	rm -rf $(RELEASE_DIR)
