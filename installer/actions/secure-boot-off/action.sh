# Read whole before it is searched: grep stops at the first match, and bootctl,
# still writing, would die of that under pipefail.
grep -q "Secure Boot: disabled" <<<"$(bootctl status 2>/dev/null)"
