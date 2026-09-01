APP     := installer
PKG     := .
BIN_DIR := bin

# Single source of truth for the version: the short commit SHA of HEAD, or
# "dev" outside a repository. `make run` appends "-dev" so it is obvious a
# binary did not come from a build of an actual commit.
VERSION     := $(shell git rev-parse --short HEAD 2>/dev/null || echo dev)
VERSION_DEV := $(VERSION)-dev

GOOS   ?= linux
GOARCH ?= $(shell go env GOARCH)

# The version lives inside the binary (see main.version), not in the filename —
# a stable name keeps download links and the ISO build working across builds.
BIN := $(BIN_DIR)/$(APP)-$(GOOS)-$(GOARCH)

LDFLAGS_BUILD := -s -w -X main.version=$(VERSION)
LDFLAGS_RUN   := -X main.version=$(VERSION_DEV)
GOFLAGS       := CGO_ENABLED=0 GOOS=$(GOOS) GOARCH=$(GOARCH)

# The tree this runtime is developed against — what `make run` runs, and nothing
# else. A build leaves its binary in bin/; putting a copy of it in the tree is
# the release's business, not this one's.
TREE ?= ../setup

.PHONY: all build run tidy tidy-check test test-race vet staticcheck vuln fmt fmt-check clean check release

all: build

# Runs against the tree next to this one. -dir because `go run` builds into a
# temporary folder, where nothing of the tree is beside the binary.
run:
	go run -ldflags="$(LDFLAGS_RUN)" $(PKG) -dir $(TREE)

build: $(BIN_DIR)
	$(GOFLAGS) go build -trimpath -ldflags="$(LDFLAGS_BUILD)" -o $(BIN) $(PKG)
	cd $(BIN_DIR) && sha256sum $(notdir $(BIN)) > $(notdir $(BIN)).sha256

release:
	$(MAKE) build GOOS=linux GOARCH=amd64

tidy:
	go mod tidy

# What `tidy` would change, said as an error instead of made as a change. A
# go.mod that has drifted from what the code imports builds here and nowhere
# else.
tidy-check:
	go mod tidy -diff

test:
	go test ./...

# The same tests under the race detector. Not part of `check`: it doubles a run
# that already takes over a minute, and it is the deeper question rather than
# the everyday one. CI runs it on every push.
#
# The detector is built on cgo, and Go turns cgo off by itself wherever it finds
# no C compiler — asking for it explicitly turns a silently skipped check into a
# missing gcc.
test-race:
	CGO_ENABLED=1 go test -race ./...

vet:
	go vet ./...

# Dead code, values that go nowhere, the mistakes vet does not look for.
staticcheck:
	staticcheck ./...

# Known vulnerabilities in what this imports. It asks a server, so it stays out
# of `check` — a check that needs the network is a check that fails on a train.
# CI runs it on every push.
vuln:
	govulncheck ./...

fmt:
	gofmt -s -w .

# gofmt asked as a question rather than made as an edit, so a branch that was
# never formatted fails here instead of arriving later as a diff nobody wrote.
fmt-check:
	@unformatted="$$(gofmt -s -l .)"; \
	[ -z "$$unformatted" ] || { echo "not gofmt'd:" >&2; echo "$$unformatted" >&2; exit 1; }

# The one command that has to pass before anything is committed.
check: fmt-check tidy-check vet staticcheck test build

# There is deliberately no install target. The binary looks for its
# installer.yaml beside itself, so a copy on $PATH with nothing next to it is a
# program that can only say it found no installer. What ships is the tree with
# the binary in it.

clean:
	rm -rf $(BIN_DIR)

$(BIN_DIR):
	mkdir -p $@
