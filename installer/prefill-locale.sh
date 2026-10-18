# The language the interface is read in, as the locale of its own country: de
# reads de_DE. Otherwise not Afar, the first row, but the one locale generated
# either way.
lang="$MODULE_LANGUAGE"
if [[ $lang =~ ^[a-z]{2,3}$ ]] && grep -q "^${lang}_${lang^^}\(\.UTF-8\)\{0,1\} UTF-8$" /usr/share/i18n/SUPPORTED; then
    printf '%s_%s' "$lang" "${lang^^}"
    return 0
fi
printf 'en_US'
