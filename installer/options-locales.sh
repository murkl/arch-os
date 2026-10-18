# Every UTF-8 locale glibc supports, without @-variants. SUPPORTED rather than
# locale.gen, which cloud-init and hand edits rewrite.
sed -n 's/^\([a-z]\{2,3\}\(_[A-Z]\{2\}\)\{0,1\}\)\(\.UTF-8\)\{0,1\} UTF-8$/\1/p' /usr/share/i18n/SUPPORTED | sort -u
