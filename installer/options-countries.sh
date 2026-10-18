printf 'auto\tauto (%s)\n' "$(auto_country)"
echo none
# A "-" marks a country Arch has no mirror in.
awk -F'\t' '!/^#/ && $2 != "-" { print $2 }' "$(installer_data)/countries"
