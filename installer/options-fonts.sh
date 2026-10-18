printf 'auto\tauto (%s)\n' "$(auto_font)"
echo none
find /usr/share/kbd/consolefonts -name '*.psf*' -printf '%f\n' 2>/dev/null |
    sed 's/\.psfu\?\(\.gz\)\?$//' | sort -u
