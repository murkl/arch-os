# The zone of the chosen country, and UTC rather than Africa/Abidjan for none.
locale="${ARCH_OS_LOCALE_LANG%%.*}"
territory=""
[[ $locale == *_* ]] && territory="${locale#*_}"
zone="$(country_field 3 "$territory")"
printf '%s' "${zone:-UTC}"
