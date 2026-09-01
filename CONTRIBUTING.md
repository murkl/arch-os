# Working on Arch OS

Everything below follows from one decision: **a commit is built once**. The
image on the release page is not a rebuild of what was tested — it is the file
that was tested, moved. That only works if promoting a commit does not change
it, which is why `main` is only ever fast-forwarded.

## Branches

```mermaid
flowchart LR
    F["feature/*"] -->|"squash merge, via a pull request"| D["dev"]
    D -->|"fast-forward — only when everything passed"| M["main"]
    M --> R["tag &lt;short-sha&gt;<br/>GitHub Release"]

    style M fill:#1793d1,stroke:#1793d1,color:#fff
    style R fill:#1793d1,stroke:#1793d1,color:#fff
```

**`feature/*`** is where work happens. Every push is checked, and nothing else
follows from it.

**`dev`** is the only branch anything is merged into, by squash, so one change
is one commit. A push here produces an image, boots it, and — if all of that
passed — promotes.

**`main`** is not written to by hand. CI fast-forwards it onto the `dev` commit
that just passed, and every commit that arrives there is tagged and released.
Its history is linear, and every entry in it is a state that was checked, built
and booted.

Because the fast-forward keeps the commit, the short SHA is the same on both
branches — and that short SHA is the version everywhere: inside the binary, on
the ISO label, in both filenames, and as the tag.

A squash into `main` would make a new commit with a new SHA, and the image built
on `dev` would carry a version no branch has. Fast-forward is not a style
preference here; it is what makes the artefact promotable.

There is **no CI on `main`**: the commit that arrives there is the commit that
was checked on `dev`, down to the SHA. Branch protection therefore requires a
linear history and forbids force pushes, but does not require status checks — a
required check on `main` would block the very push that publishes the release.

## What a push runs

```mermaid
flowchart TD
    P["push"] --> C["check<br/><small>make check · race detector</small>"]
    P --> S["security<br/><small>govulncheck · gitleaks</small>"]
    P --> B["build<br/><small>binary · release tree · tarball</small>"]
    C --> I
    S --> I
    B --> I["iso<br/><small>archiso, from the build's artefact</small>"]
    I --> K["boot test<br/><small>qemu + OVMF, until the installer appears</small>"]
    K --> M["promote<br/><small>fast-forward main · tag · release</small>"]

    style I stroke-dasharray: 4 4
    style K stroke-dasharray: 4 4
    style M fill:#1793d1,stroke:#1793d1,color:#fff
```

| Job | Where it runs | What it does |
| --- | --- | --- |
| `check` | every branch | `make check`, then the tests again under the race detector |
| `security` | every branch | vulnerabilities in the runtime's imports, and a scan for secrets in the tree |
| `build` | every branch | the runtime binary, the release tree, the tarball — and unpacks the tarball to load the tree out of it |
| `iso` | `dev`, `main`, on demand | the bootable image, out of the artefact `build` produced |
| `boot test` | after `iso` | boots that image and waits for the installer's first page |
| `promote` | `dev` | fast-forwards `main`, tags, publishes, signs |

The dashed jobs are the expensive ones. An archiso build is a quarter of an
hour, and a work in progress does not need an image — so a feature branch gets
everything except those two, in about two minutes. To get an image from a
branch, run the workflow on it by hand (Actions ▸ CI ▸ Run workflow).

`build` is the only job that compiles anything. `iso` downloads what it made
rather than making it again, and `promote` downloads what both of them made.

## Doing the work

```sh
make check            # everything below, and what has to pass before a commit
make -C runtime run   # the installer on this machine; TREE=../recovery for the other tree
make tarball          # the release, as a stock Arch ISO downloads it
make iso              # the release, as a bootable image
make -C iso smoke     # boot the newest image and wait for the installer
make clean            # all of the above, taken back
```

`make check` needs `go`, `shellcheck`, `shfmt`, `staticcheck`, `yamllint` and
`actionlint`. `make iso` needs `archiso` and root; `make -C iso smoke` needs
`qemu-base`, `edk2-ovmf`, `tesseract` and `tesseract-data-eng`. All of them are
packages:

```sh
sudo pacman -S --needed go shellcheck shfmt staticcheck yamllint actionlint \
    govulncheck gitleaks archiso qemu-base edk2-ovmf tesseract tesseract-data-eng
```

CI installs the same packages and runs the same commands, in an Arch container.
There is no second definition of what "green" means.

Most changes belong in [`installer/`](installer) — the Arch Linux half, which is
where packages, tasks and questions live — or in [`recovery/`](recovery), the
same kind of tree for repairing a system that is already on a disk. The
[`runtime/`](runtime) is the frame around both and changes for bugs and
features, not for a new package.

## Commits

Write them in the imperative — "Add", "Fix", "Refactor" — and keep one logical
change to a commit. They are squashed into `dev`, so the pull request title is
what ends up in the history.

## Setting the repository up

Once, with the `gh` CLI:

```sh
# Pull requests should default to dev, not main.
gh repo edit --default-branch dev

# main moves forward, or not at all.
gh api -X PUT repos/murkl/arch-os/branches/main/protection --input - <<'EOF'
{
  "required_linear_history": true,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "enforce_admins": false,
  "required_status_checks": null,
  "required_pull_request_reviews": null,
  "restrictions": null
}
EOF
```

Nothing else has to be configured. The workflow signs its releases with the
token GitHub already gives it, and Dependabot opens its pull requests against
`dev`.
