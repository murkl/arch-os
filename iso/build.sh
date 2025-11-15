#!/bin/bash
set -e

# VERSION
GUM_VERSION="0.13.0"
GUM_ARCH="Linux_x86_64"

# SCRIPT
ARCH_OS_RELEASE="./release"
DOWNLOAD_DIR="./download"
ISO_DIR="./archiso"
ISO_CONFIG="releng" # baseline or releng

# AIROOTFS
AIRFS_BIN="${ISO_DIR}/airootfs/usr/local/bin"
AIRFS_GUM="${AIRFS_BIN}/gum"
AIRFS_ARCHOS="${AIRFS_BIN}/arch-os"
AIRFS_RECOVERY="${AIRFS_BIN}/arch-os-recovery"

# TAGS
: "${SNAPSHOT_VERSION:=$(date +'%Y.%m')}"

# TEMP DIR
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TEMP_DIR}"' EXIT

# Init
echo "### Initialize Build"
mkdir -p "$DOWNLOAD_DIR"
sudo rm -rf "${ISO_DIR}" "${ARCH_OS_RELEASE}"
mkdir -p "${ISO_DIR}"
mkdir -p "${ARCH_OS_RELEASE}"

# Install dependencies
! command -v /usr/bin/mkarchiso &>/dev/null && sudo pacman -S --noconfirm archiso

# Generate ISO (baseline/releng)
cp -r "/usr/share/archiso/configs/${ISO_CONFIG}/"* "${ISO_DIR}"

# Copy sources
cp -rf src/* "${ISO_DIR}/airootfs/"

# Copy internal Gum binary to download dir
if [ -f "../bin/gum-${GUM_VERSION}-${GUM_ARCH}" ]; then
    echo "### Copy internal Gum binary"
    cp -f "../bin/gum-${GUM_VERSION}-${GUM_ARCH}" "${DOWNLOAD_DIR}/gum"
fi

# Check if gum already exists in download dir or download from internet
if [ ! -f "${DOWNLOAD_DIR}/gum" ]; then
    echo "### Gum binary "../bin/gum-${GUM_VERSION}-${GUM_ARCH}" not found. Downloading..."
    # Download gum: https://github.com/charmbracelet/gum/releases
    gum_url="https://github.com/charmbracelet/gum/releases/download/v${GUM_VERSION}/gum_${GUM_VERSION}_${GUM_ARCH}.tar.gz"
    gum_tar="${DOWNLOAD_DIR}/gum-${GUM_VERSION}.tar.gz"
    if [ ! -f "${gum_tar}" ]; then
        echo "### Downloading gum-${GUM_VERSION}.tar.gz"
        if ! curl -Lf "$gum_url" >"${gum_tar}"; then echo "Error downloading ${gum_url}" && exit 1; fi
    fi
    # Extract gum
    if [ ! -f "${DOWNLOAD_DIR}/gum" ]; then
        mkdir -p ${DOWNLOAD_DIR}/gum-${GUM_VERSION}
        if ! tar -xf "${gum_tar}" --directory "${DOWNLOAD_DIR}/gum-${GUM_VERSION}"; then echo "Error extracting ${gum_tar}" && exit 1; fi
        gum_path=$(find "${DOWNLOAD_DIR}/gum-${GUM_VERSION}" -type f -executable -name "gum" -print -quit)
        [ -z "$gum_path" ] && echo "Error: 'gum' binary not found in '${DOWNLOAD_DIR}/gum-${GUM_VERSION}'" && exit 1
        cp -f "$gum_path" "${DOWNLOAD_DIR}/gum"
        rm -rf "${DOWNLOAD_DIR}/gum-${GUM_VERSION}/"
    fi
fi

# Install gum
[ ! -f "${DOWNLOAD_DIR}/gum" ] && echo "Error: 'gum' binary not found in '${DOWNLOAD_DIR}'" && exit 1
if ! cp -f "${DOWNLOAD_DIR}/gum" "${AIRFS_GUM}"; then echo "Error copy ${DOWNLOAD_DIR}/gum to ${AIRFS_GUM}" && exit 1; fi
if ! chmod +x "${AIRFS_GUM}"; then echo "Error chmod +x ${AIRFS_GUM}" && exit 1; fi

#echo "### Copy Gum to Release"
#cp -f "${DOWNLOAD_DIR}/gum" "${ARCH_OS_RELEASE}/gum-${GUM_VERSION}-${GUM_ARCH}"

# Download Arch OS Installer script
#echo "### Downloading Arch OS Installer"
#curl -L bit.ly/arch-os >"${DOWNLOAD_DIR}/arch-os"

# Copy Arch OS Installer script
echo "### Copy Arch OS Installer"
cp -f ../installer.sh "${DOWNLOAD_DIR}/arch-os"

#echo "### Copy Installer to Release"
#cp -f "${DOWNLOAD_DIR}/arch-os" "${ARCH_OS_RELEASE}/arch-os-installer.sh"

# Install Arch OS Installer script
[ ! -f "${DOWNLOAD_DIR}/arch-os" ] && echo "Error: 'arch-os' binary not found in '${DOWNLOAD_DIR}'" && exit 1
if ! cp -f "${DOWNLOAD_DIR}/arch-os" "${AIRFS_ARCHOS}"; then echo "Error copy ${DOWNLOAD_DIR}/arch-os to ${AIRFS_ARCHOS}" && exit 1; fi
if ! chmod +x "${AIRFS_ARCHOS}"; then echo "Error chmod +x ${AIRFS_ARCHOS}" && exit 1; fi

# Download Arch OS Recovery script
echo "### Downloading Arch OS Recovery"
curl -L bit.ly/arch-os-recovery >"${DOWNLOAD_DIR}/arch-os-recovery"

# Install Arch OS Recovery script
[ ! -f "${DOWNLOAD_DIR}/arch-os-recovery" ] && echo "Error: 'arch-os-recovery' binary not found in '${DOWNLOAD_DIR}'" && exit 1
if ! cp -f "${DOWNLOAD_DIR}/arch-os-recovery" "${AIRFS_RECOVERY}"; then echo "Error copy ${DOWNLOAD_DIR}/arch-os-recovery to ${AIRFS_RECOVERY}" && exit 1; fi
if ! chmod +x "${AIRFS_RECOVERY}"; then echo "Error chmod +x ${AIRFS_RECOVERY}" && exit 1; fi

#echo "### Copy Recovery to Release"
#cp -f "${DOWNLOAD_DIR}/arch-os-recovery" "${ARCH_OS_RELEASE}/arch-os-recovery.sh"

# Set permissions
grep -q '\["/usr/local/bin/arch-os-autostart"\]' "${ISO_DIR}/profiledef.sh" || sed -i '/^file_permissions=(/a\  ["/usr/local/bin/arch-os-autostart"]="0:0:755"' "${ISO_DIR}/profiledef.sh"
grep -q '\["/usr/local/bin/gum"\]' "${ISO_DIR}/profiledef.sh" || sed -i '/^file_permissions=(/a\  ["/usr/local/bin/gum"]="0:0:755"' "${ISO_DIR}/profiledef.sh"
grep -q '\["/usr/local/bin/arch-os"\]' "${ISO_DIR}/profiledef.sh" || sed -i '/^file_permissions=(/a\  ["/usr/local/bin/arch-os"]="0:0:755"' "${ISO_DIR}/profiledef.sh"
grep -q '\["/usr/local/bin/arch-os-recovery"\]' "${ISO_DIR}/profiledef.sh" || sed -i '/^file_permissions=(/a\  ["/usr/local/bin/arch-os-recovery"]="0:0:755"' "${ISO_DIR}/profiledef.sh"

# Add Network-Manager package
grep -qxF "networkmanager" "${ISO_DIR}/packages.x86_64" || echo "networkmanager" >>"${ISO_DIR}/packages.x86_64"

# Remove network services
rm -f "${ISO_DIR}/airootfs/etc/systemd/system/sockets.target.wants/systemd-networkd.socket"
rm -f "${ISO_DIR}/airootfs/etc/systemd/system/multi-user.target.wants/systemd-networkd.service"
rm -f "${ISO_DIR}/airootfs/etc/systemd/system/multi-user.target.wants/systemd-resolved.service"
rm -f "${ISO_DIR}/airootfs/etc/systemd/system/network-online.target.wants/systemd-networkd-wait-online.service"
rm -f "${ISO_DIR}/airootfs/etc/systemd/system/dbus-org.freedesktop.network1.service"
rm -rf "${ISO_DIR}/airootfs/etc/systemd/system/systemd-networkd-wait-online.service.d"

# Set DNS resolver
ln -sf /run/NetworkManager/resolv.conf "${ISO_DIR}/airootfs/etc/resolv.conf"

# Enable NetworkManager service
ln -sf /usr/lib/systemd/system/NetworkManager.service "${ISO_DIR}/airootfs/etc/systemd/system/multi-user.target.wants/NetworkManager.service"

# Bootloader config
sed -i '/^options / s/$/ quiet loglevel=0/' "${ISO_DIR}"/efiboot/loader/entries/01-archiso-linux*.conf
sed -i 's/^timeout.*/timeout 0/' "${ISO_DIR}/efiboot/loader/loader.conf"

# Remove Arch-Banner
: >"${ISO_DIR}/airootfs/etc/issue"

# Set arch-os-autostart as kernel parameter
sed -i '/^options /{/script=\/usr\/local\/bin\/arch-os-autostart/!s/$/ script=\/usr\/local\/bin\/arch-os-autostart/}' "${ISO_DIR}"/efiboot/loader/entries/01-archiso-linux*.conf

# Set ISO config
set_key_value() { grep -q "^$2=" "$1" && sed -i "s|^$2=.*|$2=\"$3\"|" "$1" || echo "$2=$3" >>"$1"; }
set_key_value "${ISO_DIR}/profiledef.sh" iso_name "archos"
set_key_value "${ISO_DIR}/profiledef.sh" iso_version "$SNAPSHOT_VERSION"
set_key_value "${ISO_DIR}/profiledef.sh" iso_label "ARCH_OS_${SNAPSHOT_VERSION}"
set_key_value "${ISO_DIR}/profiledef.sh" iso_application "Arch OS Autostart ISO"
set_key_value "${ISO_DIR}/profiledef.sh" iso_publisher "murkl@github.com"

# Make ISO
echo "### Make Arch OS ISO"
cd "${ISO_DIR}"
sudo rm -rf work out
sudo mkarchiso -v .
cd ..

# Move ISO to release dir
echo "### Move ISO to Release"
mv -f "${ISO_DIR}/out/"*.iso "${ARCH_OS_RELEASE}/"
