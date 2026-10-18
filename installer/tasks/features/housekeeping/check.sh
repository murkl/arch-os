#!/usr/bin/env bash
# data/paccache.sh against snapshots, a cache, and a paccache that lists its
# candidates as the real one does: what goes, and which kernels stay.
#
#   check.sh
set -euo pipefail

# Byte order, the same here as in the lists compared.
export LC_ALL=C

cd "$(dirname "$0")"

status=0
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "${work}/bin"

# paccache records how it was called; a dry run names the candidates of the case.
cat >"${work}/bin/paccache" <<'EOF'
#!/usr/bin/env bash
echo "paccache $*" >>"${WORK}/calls"
if [ "$1" = -d ]; then
    echo '==> Candidate packages:'
    cat "${WORK}/candidates"
    echo
    echo '==> finished dry run'
fi
EOF
cat >"${work}/bin/pacman-conf" <<'EOF'
#!/usr/bin/env bash
echo "${WORK}/cache/"
EOF
chmod 755 "${work}/bin/paccache" "${work}/bin/pacman-conf"

# A snapshot with a package installed: a kernel when its files hold a vmlinuz.
installed() {
    local dir="${work}/snapshots/$1/snapshot/var/lib/pacman/local/$2-$3"
    mkdir -p "$dir"
    printf '%%NAME%%\n%s\n\n%%VERSION%%\n%s\n' "$2" "$3" >"${dir}/desc"
    printf '%%FILES%%\nusr/\n%s\n' "$4" >"${dir}/files"
}

# Kernel package files by version, a signature, and a list as compared.
pkg() { for v in "$@"; do echo "linux-zen-${v}-x86_64.pkg.tar.zst"; done; }
sig() { echo "linux-zen-${1}-x86_64.pkg.tar.zst.sig"; }
listed() { sort | paste -sd' '; }

# The cache holding the files given, paccache offering the candidates given;
# the answer and the files left are compared with what is wanted.
case_of() {
    local what="$1" files="$2" candidates="$3" want_status="$4" want="$5" got_status=0 got file
    rm -rf "${work}/cache" "${work}/calls"
    mkdir -p "${work}/cache"
    while read -r file; do
        if [ -n "$file" ]; then : >"${work}/cache/${file}"; fi
    done <<<"$files"
    printf '%s\n' "$candidates" >"${work}/candidates"
    WORK="$work" PATH="${work}/bin:${PATH}" bash data/paccache.sh "${work}/snapshots" >/dev/null 2>&1 || got_status=$?
    got="$(find "${work}/cache" -type f -printf '%f\n' | listed)"
    if [ "$got_status" != "$want_status" ] || [ "$got" != "$want" ]; then
        printf '%s\n  got:  %s %s\n  want: %s %s\n' "$what" "$got_status" "$got" "$want_status" "$want" >&2
        status=1
    fi
}

# What paccache was called with, against what is wanted.
called() {
    if ! grep -qxF "$2" "${work}/calls"; then
        printf '%s\n  paccache was not called as: %s\n' "$1" "$2" >&2
        status=1
    fi
}

case_of "no snapshots" "$(pkg 6.1-1)" "" 0 "$(pkg 6.1-1 | listed)"
called "no snapshots" "paccache -r"

installed 1 linux-zen 6.1-1 usr/lib/modules/6.1.0-zen1-1-zen/vmlinuz
installed 1 linux-firmware 20261001-1 usr/lib/firmware/a.bin
installed 2 linux-zen 6.3-1 usr/lib/modules/6.3.0-zen1-1-zen/vmlinuz

case_of "an old kernel a snapshot has" "$(pkg 6.1-1 6.2-1 6.3-1 6.4-1 6.5-1 && sig 6.1-1 && sig 6.2-1)" \
    "$(pkg 6.1-1 && sig 6.1-1 && pkg 6.2-1 && sig 6.2-1)" \
    0 "$({ pkg 6.1-1 6.3-1 6.4-1 6.5-1 && sig 6.1-1; } | listed)"
called "an old kernel a snapshot has" "paccache -r --ignore linux-zen"

# 6.1-1 is in a snapshot, 6.1-10 only starts the same.
case_of "a release that only shares the start" "$(pkg 6.1-1 6.1-10 6.3-1)" "$(pkg 6.1-10)" 0 "$(pkg 6.1-1 6.3-1 | listed)"

# A kernel's file list that cannot be read could be any version: nothing goes.
mkdir -p "${work}/snapshots/3/snapshot/var/lib/pacman/local/linux-zen-6.0-1/files"
case_of "a snapshot that cannot be read" "$(pkg 6.0-1 6.2-1)" "$(pkg 6.0-1 6.2-1)" 1 "$(pkg 6.0-1 6.2-1 | listed)"

[ "$status" -eq 0 ] && echo "the package cache keeps the snapshots' kernels as written down here"
exit "$status"
