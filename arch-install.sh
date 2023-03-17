#!/usr/bin/env bash
# shellcheck disable=SC1090

# /////////////////////////////////////////////////////
# ARG VARIABLES
# /////////////////////////////////////////////////////

ARCH_FORCE_INSTALL=""
ARCH_CONFIG_FILE=""
ARCH_USER_SCRIPTS=()

# /////////////////////////////////////////////////////
# CACHE DIR
# /////////////////////////////////////////////////////

INSTALL_CACHE_DIR=$(mktemp -d "/tmp/arch-install-cache.XXXXXXXXXX")

# /////////////////////////////////////////////////////
# PROGRESS INFO (WHIPTAIL)
# /////////////////////////////////////////////////////

PROGRESS_COUNT=0
PROGRESS_TOTAL=28

# /////////////////////////////////////////////////////
# PRINT FUNCTIONS
# /////////////////////////////////////////////////////

print_red() { echo -e "\e[31m${1}\e[0m"; }
print_green() { echo -e "\e[32m${1}\e[0m"; }
print_yellow() { echo -e "\e[33m${1}\e[0m"; }
print_purple() { echo -e "\e[35m${1}\e[0m"; }

print_title() {
    if [ "$ARCH_FORCE_INSTALL" = "true" ]; then
        # Print whiptail info
        echo ">>> $1" >&2 # Print title to stderr in case of failure
        ((PROGRESS_COUNT += 1)) && echo -e "XXX\n$((PROGRESS_COUNT * 100 / PROGRESS_TOTAL))\n${1}...\nXXX"
    else
        # Print default info
        for ((i = ${#1}; i < 67; i++)); do local spaces="${spaces} "; done
        print_purple "┌──────────────────────────────────────────────────────────────────────┐"
        print_purple "│ ${1} ${spaces} │"
        print_purple "└──────────────────────────────────────────────────────────────────────┘"
    fi
}

print_help() {
    print_purple "Description:"
    print_yellow "\t This scipt installs Arch Linux depending on your config."
    print_yellow "\t Your passed scripts will be invoked as last installation step."
    print_yellow "\t More information: https://github.com/murkl/arch-distro"
    echo -e ""
    print_purple "Usage:"
    print_yellow "\t $0 -c <config> [-f] [-s <script>...]"
    echo -e ""
}

# ///////////////////////////////////////////////////////////////////
# UNMOUNT FUNCTION
# ///////////////////////////////////////////////////////////////////

unmount() {
    swapoff -a &>/dev/null
    umount -A -R /mnt &>/dev/null
    cryptsetup close cryptroot &>/dev/null
}

# /////////////////////////////////////////////////////
# PRINT HEADER
# /////////////////////////////////////////////////////

clear && print_green "
\t             █████╗ ██████╗  ██████╗██╗  ██╗          
\t            ██╔══██╗██╔══██╗██╔════╝██║  ██║          
\t            ███████║██████╔╝██║     ███████║          
\t            ██╔══██║██╔══██╗██║     ██╔══██║          
\t            ██║  ██║██║  ██║╚██████╗██║  ██║          
\t            ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝          
\t ██╗███╗   ██╗███████╗████████╗ █████╗ ██╗     ██╗     
\t ██║████╗  ██║██╔════╝╚══██╔══╝██╔══██╗██║     ██║     
\t ██║██╔██╗ ██║███████╗   ██║   ███████║██║     ██║     
\t ██║██║╚██╗██║╚════██║   ██║   ██╔══██║██║     ██║     
\t ██║██║ ╚████║███████║   ██║   ██║  ██║███████╗███████╗
\t ╚═╝╚═╝  ╚═══╝╚══════╝   ╚═╝   ╚═╝  ╚═╝╚══════╝╚══════╝
"

# /////////////////////////////////////////////////////
# CHECK UEFI
# /////////////////////////////////////////////////////

[ ! -d /sys/firmware/efi ] && print_red "ERROR: BIOS not supported" && exit 1

# /////////////////////////////////////////////////////
# CHECK ARGS
# /////////////////////////////////////////////////////

while getopts ':c:s:f' flag; do
    case "${flag}" in
    c) ARCH_CONFIG_FILE="$OPTARG" ;;
    s) ARCH_USER_SCRIPTS+=("${OPTARG}") ;;
    f) ARCH_FORCE_INSTALL="true" ;;
    :) print_red "ERROR: Option -${OPTARG} requires an argument" && exit 1 ;;
    ?) print_red "ERROR: Invalid option -${OPTARG}" && exit 1 ;;
    esac
done

shift $((OPTIND - 1)) && [ -z "$ARCH_CONFIG_FILE" ] && print_help && exit 1
[ -z "$ARCH_FORCE_INSTALL" ] && ARCH_FORCE_INSTALL="false"

# /////////////////////////////////////////////////////
# DOWNLOAD & CHECK CONFIG FILE
# /////////////////////////////////////////////////////

# Check if passed config file starts with http or https
if [[ "$ARCH_CONFIG_FILE" == http://* ]] || [[ "$ARCH_CONFIG_FILE" == https://* ]]; then

    # When starts with http or https -> download config file to cache dir
    curl -Lfs "$ARCH_CONFIG_FILE" -o "${INSTALL_CACHE_DIR}/install.conf" || { print_red "ERROR: Downloading Config" && exit 1; }

else

    # When local config file passed -> check if local config file exists
    [ ! -f "$ARCH_CONFIG_FILE" ] && print_red "ERROR: Config '$ARCH_CONFIG_FILE' not found" && exit 1

    # Copy local script file to cache dir
    cp -f "$ARCH_CONFIG_FILE" "${INSTALL_CACHE_DIR}/install.conf" || exit 1
fi

# Set config file to cache location
ARCH_CONFIG_FILE="${INSTALL_CACHE_DIR}/install.conf"

# Check if config file exists
[ ! -f "$ARCH_CONFIG_FILE" ] && print_red "ERROR: Config '$ARCH_CONFIG_FILE' not found" && exit 1

# /////////////////////////////////////////////////////
# DOWNLOAD & CHECK SCRIPT FILES
# /////////////////////////////////////////////////////

if [ -n "${ARCH_USER_SCRIPTS[*]}" ]; then

    mkdir -p "${INSTALL_CACHE_DIR}/scripts"
    arch_script_file_array_new=()

    # Iterate all passed script arguments
    for ((i = 0; i < ${#ARCH_USER_SCRIPTS[@]}; ++i)); do

        # Check if passed script starts with http or https
        if [[ "${ARCH_USER_SCRIPTS[$i]}" == http://* ]] || [[ "${ARCH_USER_SCRIPTS[$i]}" == https://* ]]; then

            # When starts with http or https -> download script file to cache dir
            curl -Lfs "${ARCH_USER_SCRIPTS[$i]}" -o "${INSTALL_CACHE_DIR}/scripts/${i}_script.sh" || { print_red "ERROR: Downloading Script" && exit 1; }

            # Check if downloaded script file exists
            [ ! -f "${INSTALL_CACHE_DIR}/scripts/${i}_script.sh" ] && print_red "ERROR: Script '${INSTALL_CACHE_DIR}/scripts/${i}_script.sh' not found" && exit 1

        else

            # When local script file passed -> check if local script file exists
            [ ! -f "${ARCH_USER_SCRIPTS[$i]}" ] && print_red "ERROR: Script '${ARCH_USER_SCRIPTS[$i]}' not found" && exit 1

            # Copy local script file to cache dir
            cp -f "${ARCH_USER_SCRIPTS[$i]}" "${INSTALL_CACHE_DIR}/scripts/${i}_script.sh" || exit 1
        fi

        # Add new script file location (cache dir) to new array
        arch_script_file_array_new+=("${INSTALL_CACHE_DIR}/scripts/${i}_script.sh")
    done

    # Set new script file location (cache dir)
    ARCH_USER_SCRIPTS=("${arch_script_file_array_new[@]}")
fi

# /////////////////////////////////////////////////////
# CHECK CONFIG
# /////////////////////////////////////////////////////

set -a # Enable auto export
source "$ARCH_CONFIG_FILE" || exit 1
set +a # Disable auto export

[ -z "${ARCH_USERNAME}" ] && print_red "ERROR: ARCH_USERNAME is missing" && exit 1
[ -z "${ARCH_HOSTNAME}" ] && print_red "ERROR: ARCH_HOSTNAME is missing" && exit 1
[ -z "${ARCH_PASSWORD}" ] && print_red "ERROR: ARCH_PASSWORD is missing" && exit 1
[ -z "${ARCH_DISK}" ] && print_red "ERROR: ARCH_DISK is missing" && exit 1
[ -z "${ARCH_BOOT_PARTITION}" ] && print_red "ERROR: ARCH_BOOT_PARTITION is missing" && exit 1
[ -z "${ARCH_ROOT_PARTITION}" ] && print_red "ERROR: ARCH_ROOT_PARTITION is missing" && exit 1
[ -z "${ARCH_ENCRYPTION_ENABLED}" ] && print_red "ERROR: ARCH_ENCRYPTION_ENABLED is missing" && exit 1
[ -z "${ARCH_FSTRIM_ENABLED}" ] && print_red "ERROR: ARCH_FSTRIM_ENABLED is missing" && exit 1
[ -z "${ARCH_SWAP_SIZE}" ] && print_red "ERROR: ARCH_SWAP_SIZE is missing" && exit 1
[ -z "${ARCH_TIMEZONE}" ] && print_red "ERROR: ARCH_TIMEZONE is missing" && exit 1
[ -z "${ARCH_LOCALE_LANG}" ] && print_red "ERROR: ARCH_LOCALE_LANG is missing" && exit 1
[ -z "${ARCH_LOCALE_GEN_LIST[*]}" ] && print_red "ERROR: ARCH_LOCALE_GEN_LIST is missing" && exit 1
[ -z "${ARCH_VCONSOLE_KEYMAP}" ] && print_red "ERROR: ARCH_VCONSOLE_KEYMAP is missing" && exit 1
[ -z "${ARCH_VCONSOLE_FONT}" ] && print_red "ERROR: ARCH_VCONSOLE_FONT is missing" && exit 1
[ -z "${ARCH_MULTILIB_ENABLED}" ] && print_red "ERROR: ARCH_MULTILIB_ENABLED is missing" && exit 1
[ -z "${ARCH_AUR_ENABLED}" ] && print_red "ERROR: ARCH_AUR_ENABLED is missing" && exit 1
[ -z "${ARCH_PKGFILE_ENABLED}" ] && print_red "ERROR: ARCH_PKGFILE_ENABLED is missing" && exit 1
[ -z "${ARCH_SHUTDOWN_TIMEOUT_SEC}" ] && print_red "ERROR: ARCH_SHUTDOWN_TIMEOUT_SEC is missing" && exit 1

# /////////////////////////////////////////////////////
# START INSTALLATION?
# /////////////////////////////////////////////////////

print_green "Check Config: OK"
print_green "Check Script: ${#ARCH_USER_SCRIPTS[@]}\n"

if [ "$ARCH_FORCE_INSTALL" = "false" ]; then
    read -r -p "> Start Installation? [y/N]: " user_input </dev/tty
    [ "$user_input" != "y" ] && exit 1
fi

# /////////////////////////////////////////////////////
# SET TRAP
# /////////////////////////////////////////////////////

trap unmount EXIT

# /////////////////////////////////////////////////////
# WAITING FOR REFLECTOR
# /////////////////////////////////////////////////////

print_title "Waiting for Reflector from Arch ISO"
while timeout 180 tail --pid=$(pgrep reflector) -f /dev/null &>/dev/null; do sleep 1; done
pgrep reflector &>/dev/null && print_red "ERROR: Reflector timeout after 180 seconds" && exit 1
print_green "> Done\n"

# /////////////////////////////////////////////////////
# PREPARE INSTALLATION
# /////////////////////////////////////////////////////

print_title "Prepare Installation"

# Make sure everything is unmounted before start install
unmount

# Temporarily disable ECN (prevent traffic problems with some old routers)
#sysctl net.ipv4.tcp_ecn=0 1>/dev/null

# Update keyring
pacman -Sy --noconfirm archlinux-keyring 1>/dev/null

# Detect microcode
unset ARCH_MICROCODE
grep -E "GenuineIntel" <<<"$(lscpu)" 1>/dev/null && ARCH_MICROCODE="intel-ucode"
grep -E "AuthenticAMD" <<<"$(lscpu)" 1>/dev/null && ARCH_MICROCODE="amd-ucode"

print_green "> Done\n"

# /////////////////////////////////////////////////////  START ARCH LINUX INSTALLATION /////////////////////////////////////////////////////

print_title "Wipe Partitions"

# Wipe all partitions
wipefs -af "$ARCH_DISK" 1>/dev/null || exit 1

# Create new GPT partition table
sgdisk -Z -o "$ARCH_DISK" 1>/dev/null || exit 1

# Reload partition table
partprobe "$ARCH_DISK" 1>/dev/null || exit 1

print_green "> Done\n"

# /////////////////////////////////////////////////////

print_title "Create Partitions"

# Create partition /boot efi partition: 1 GiB
sgdisk -n 1:0:+1G -t 1:ef00 -c 1:boot "$ARCH_DISK" 1>/dev/null || exit 1

# Create partition / partition: Rest of space
sgdisk -n 2:0:0 -t 2:8300 -c 2:root "$ARCH_DISK" 1>/dev/null || exit 1

# Reload partition table
partprobe "$ARCH_DISK" 1>/dev/null || exit 1

print_green "> Done\n"

# /////////////////////////////////////////////////////

if [ "$ARCH_ENCRYPTION_ENABLED" = "true" ]; then
    print_title "Enable Disk Encryption"
    echo -n "$ARCH_PASSWORD" | cryptsetup luksFormat "$ARCH_ROOT_PARTITION" 1>/dev/null || exit 1
    echo -n "$ARCH_PASSWORD" | cryptsetup open "$ARCH_ROOT_PARTITION" cryptroot 1>/dev/null || exit 1
    print_green "> Done\n"
fi

# /////////////////////////////////////////////////////

print_title "Format Disk"
yes | LC_ALL=en_US.UTF-8 mkfs.fat -F 32 -n BOOT "$ARCH_BOOT_PARTITION" 1>/dev/null || exit 1
[ "$ARCH_ENCRYPTION_ENABLED" = "true" ] && { yes | LC_ALL=en_US.UTF-8 mkfs.ext4 -L ROOT /dev/mapper/cryptroot 1>/dev/null || exit 1; }
[ "$ARCH_ENCRYPTION_ENABLED" = "false" ] && { yes | LC_ALL=en_US.UTF-8 mkfs.ext4 -L ROOT "$ARCH_ROOT_PARTITION" 1>/dev/null || exit 1; }
print_green "> Done\n"

# /////////////////////////////////////////////////////

print_title "Mount Disk"
[ "$ARCH_ENCRYPTION_ENABLED" = "true" ] && { mount -v /dev/mapper/cryptroot /mnt 1>/dev/null || exit 1; }
[ "$ARCH_ENCRYPTION_ENABLED" = "false" ] && { mount -v "$ARCH_ROOT_PARTITION" /mnt 1>/dev/null || exit 1; }
mkdir -p /mnt/boot 1>/dev/null || exit 1
mount -v "$ARCH_BOOT_PARTITION" /mnt/boot 1>/dev/null || exit 1
print_green "> Done\n"

# /////////////////////////////////////////////////////

print_title "Installing Packages"
packages=()
packages+=("base")
packages+=("base-devel")
packages+=("linux")
packages+=("linux-firmware")
packages+=("networkmanager")
packages+=("pacman-contrib")
packages+=("reflector")
packages+=("git")
packages+=("nano")
packages+=("bash-completion")
[ "$ARCH_PKGFILE_ENABLED" = 'true' ] && packages+=("pkgfile")
[ -n "$ARCH_MICROCODE" ] && packages+=("$ARCH_MICROCODE")
pacstrap /mnt "${packages[@]}" "${ARCH_OPT_PACKAGE_LIST[@]}" 1>/dev/null || exit 1
print_green "> Done\n"

# /////////////////////////////////////////////////////

print_title "Configure Pacman"
sed -i 's/^#ParallelDownloads/ParallelDownloads/' /mnt/etc/pacman.conf 1>/dev/null || exit 1
sed -i 's/^#Color/Color/' /mnt/etc/pacman.conf 1>/dev/null || exit 1
[ "$ARCH_MULTILIB_ENABLED" = 'true' ] && { sed -i "/\[multilib\]/,/Include/"'s/^#//' /mnt/etc/pacman.conf 1>/dev/null || exit 1; }
arch-chroot /mnt pacman -Syy --noconfirm 1>/dev/null || exit 1
print_green "> Done\n"

# /////////////////////////////////////////////////////

print_title "Configure Reflector"
{
    echo "# Reflector config for the systemd service"
    echo "--save /etc/pacman.d/mirrorlist"
    echo "--protocol https"
    echo "--latest 10"
    echo "--sort rate"
} >/mnt/etc/xdg/reflector/reflector.conf || exit 1
print_green "> Done\n"

# /////////////////////////////////////////////////////

print_title "Generate /etc/fstab"
genfstab -U /mnt >>/mnt/etc/fstab || exit 1
print_green "> Done\n"

# /////////////////////////////////////////////////////

if [ "$ARCH_SWAP_SIZE" != "0" ] && [ -n "$ARCH_SWAP_SIZE" ]; then
    print_title "Create Swap"
    dd if=/dev/zero of=/mnt/swapfile bs=1G count="$ARCH_SWAP_SIZE" status=progress 1>/dev/null || exit 1
    chmod 600 /mnt/swapfile 1>/dev/null || exit 1
    mkswap /mnt/swapfile 1>/dev/null || exit 1
    swapon /mnt/swapfile 1>/dev/null || exit 1
    echo "# Swapfile" >>/mnt/etc/fstab || exit 1
    echo "/swapfile none swap defaults 0 0" >>/mnt/etc/fstab || exit 1
    print_green "> Done\n"
fi

# /////////////////////////////////////////////////////

print_title "Timezone & System Clock"
arch-chroot /mnt ln -sf "/usr/share/zoneinfo/$ARCH_TIMEZONE" /etc/localtime 1>/dev/null || exit 1
arch-chroot /mnt hwclock --systohc 1>/dev/null || exit 1 # Set hardware clock from system clock
print_green "> Done\n"

# /////////////////////////////////////////////////////

print_title "Set Console Keymap"
echo "KEYMAP=$ARCH_VCONSOLE_KEYMAP" >/mnt/etc/vconsole.conf || exit 1
echo "FONT=$ARCH_VCONSOLE_FONT" >>/mnt/etc/vconsole.conf || exit 1
print_green "> Done\n"

# /////////////////////////////////////////////////////

print_title "Generate Locale"
echo "LANG=$ARCH_LOCALE_LANG" >/mnt/etc/locale.conf || exit 1
for ((i = 0; i < ${#ARCH_LOCALE_GEN_LIST[@]}; i++)); do sed -i "s/^#${ARCH_LOCALE_GEN_LIST[$i]}/${ARCH_LOCALE_GEN_LIST[$i]}/g" "/mnt/etc/locale.gen" 1>/dev/null || exit 1; done
arch-chroot /mnt locale-gen 1>/dev/null || exit 1
print_green "> Done\n"

# /////////////////////////////////////////////////////

print_title "Set Hostname"
echo "$ARCH_HOSTNAME" >/mnt/etc/hostname || exit 1
print_green "> Done\n"

# /////////////////////////////////////////////////////

print_title "Set /etc/hosts"
{
    echo '127.0.0.1    localhost'
    echo '::1          localhost'
} >/mnt/etc/hosts || exit 1
print_green "> Done\n"

# /////////////////////////////////////////////////////

print_title "Set /etc/environment"
{
    echo 'EDITOR=nano'
    echo 'VISUAL=nano'
} >/mnt/etc/environment || exit 1
print_green "> Done\n"

# /////////////////////////////////////////////////////

print_title "Create Initial Ramdisk"
[ "$ARCH_ENCRYPTION_ENABLED" = "true" ] && { sed -i "s/^HOOKS=(.*)$/HOOKS=(base systemd autodetect modconf keyboard sd-vconsole block sd-encrypt filesystems resume fsck)/" /mnt/etc/mkinitcpio.conf 1>/dev/null || exit 1; }
[ "$ARCH_ENCRYPTION_ENABLED" = "false" ] && { sed -i "s/^HOOKS=(.*)$/HOOKS=(base systemd autodetect modconf keyboard sd-vconsole block filesystems resume fsck)/" /mnt/etc/mkinitcpio.conf 1>/dev/null || exit 1; }
arch-chroot /mnt mkinitcpio -P 1>/dev/null || exit 1
print_green "> Done\n"

# /////////////////////////////////////////////////////

print_title "Install Bootloader"

# Install systemdboot to /boot
arch-chroot /mnt bootctl --esp-path=/boot install 1>/dev/null || exit 1

# Kernel args
swap_device_uuid="$(findmnt -no UUID -T /mnt/swapfile)"
swap_file_offset="$(filefrag -v /mnt/swapfile | awk '$1=="0:" {print substr($4, 1, length($4)-2)}')"
if [ "$ARCH_ENCRYPTION_ENABLED" = "true" ]; then
    kernel_args="rd.luks.name=$(blkid -s UUID -o value "${ARCH_ROOT_PARTITION}")=cryptroot root=/dev/mapper/cryptroot rw init=/usr/lib/systemd/systemd quiet splash vt.global_cursor_default=0 resume=/dev/mapper/cryptroot resume_offset=${swap_file_offset}"
else
    kernel_args="root=PARTUUID=$(lsblk -dno PARTUUID "${ARCH_ROOT_PARTITION}") rw init=/usr/lib/systemd/systemd quiet splash vt.global_cursor_default=0 resume=UUID=${swap_device_uuid} resume_offset=${swap_file_offset}"
fi

# Create Bootloader config
{
    echo 'default arch.conf'
    echo 'console-mode max'
    echo 'timeout 0'
    echo 'editor yes'
} >/mnt/boot/loader/loader.conf || exit 1

# Create arch default entry
{
    echo 'title   Arch Linux'
    echo 'linux   /vmlinuz-linux'
    [ -n "$ARCH_MICROCODE" ] && echo "initrd  /${ARCH_MICROCODE}.img"
    echo 'initrd  /initramfs-linux.img'
    echo "options ${kernel_args}"
} >/mnt/boot/loader/entries/arch.conf || exit 1

# Create arch fallback entry
{
    echo 'title   Arch Linux (Fallback)'
    echo 'linux   /vmlinuz-linux'
    [ -n "$ARCH_MICROCODE" ] && echo "initrd  /${ARCH_MICROCODE}.img"
    echo 'initrd  /initramfs-linux-fallback.img'
    echo "options ${kernel_args}"
} >/mnt/boot/loader/entries/arch-fallback.conf || exit 1

print_green "> Done\n"

# /////////////////////////////////////////////////////

print_title "Create User"

# Create new user
arch-chroot /mnt useradd -m -G wheel -s /bin/bash "$ARCH_USERNAME" 1>/dev/null || exit 1

# Allow users in group wheel to use sudo
sed -i 's^# %wheel ALL=(ALL:ALL) ALL^%wheel ALL=(ALL:ALL) ALL^g' /mnt/etc/sudoers 1>/dev/null || exit 1
echo -e "\n## Enable sudo password feedback\nDefaults pwfeedback" >>/mnt/etc/sudoers || exit 1

# Change passwords
printf "%s\n%s" "${ARCH_PASSWORD}" "${ARCH_PASSWORD}" | arch-chroot /mnt passwd 1>/dev/null || exit 1
printf "%s\n%s" "${ARCH_PASSWORD}" "${ARCH_PASSWORD}" | arch-chroot /mnt passwd "$ARCH_USERNAME" 1>/dev/null || exit 1

print_green "> Done\n"

# /////////////////////////////////////////////////////

print_title "Enable Services"
arch-chroot /mnt systemctl enable NetworkManager 1>/dev/null || exit 1                                                    # Network Manager
arch-chroot /mnt systemctl enable systemd-timesyncd.service 1>/dev/null || exit 1                                         # Sync time from internet after boot
arch-chroot /mnt systemctl enable reflector.service 1>/dev/null || exit 1                                                 # Rank mirrors after boot
arch-chroot /mnt systemctl enable paccache.timer 1>/dev/null || exit 1                                                    # Discard cached/unused packages weekly
[ "$ARCH_FSTRIM_ENABLED" = 'true' ] && { arch-chroot /mnt systemctl enable fstrim.timer 1>/dev/null || exit 1; }          # SSD support
[ "$ARCH_PKGFILE_ENABLED" = 'true' ] && { arch-chroot /mnt systemctl enable pkgfile-update.timer 1>/dev/null || exit 1; } # Pkgfile update timer
print_green "> Done\n"

# /////////////////////////////////////////////////////

print_title "Configure System"

# Reduce shutdown timeout
sed -i "s/^#DefaultTimeoutStopSec=.*/DefaultTimeoutStopSec=${ARCH_SHUTDOWN_TIMEOUT_SEC}/" /mnt/etc/systemd/system.conf 1>/dev/null || exit 1

# Set Nano colors
sed -i 's;^# include "/usr/share/nano/\*\.nanorc";include "/usr/share/nano/*.nanorc"\ninclude "/usr/share/nano/extra/*.nanorc";g' /mnt/etc/nanorc 1>/dev/null || exit 1

print_green "> Done\n"

# /////////////////////////////////////////////////////

if [ "$ARCH_AUR_ENABLED" = "true" ]; then

    print_title "Install AUR Helper"

    # Add sudo needs no password rights
    arch-chroot /mnt sed -i 's/^# %wheel ALL=(ALL:ALL) NOPASSWD: ALL/%wheel ALL=(ALL:ALL) NOPASSWD: ALL/' /etc/sudoers 1>/dev/null || exit 1

    # Install paru as user
    arch-chroot /mnt /usr/bin/runuser -u "$ARCH_USERNAME" -- bash -c "git clone https://aur.archlinux.org/paru-bin.git /tmp/paru && cd /tmp/paru && makepkg -si --noconfirm && rm -rf /tmp/paru" 1>/dev/null || exit 1

    # Remove sudo needs no password rights
    arch-chroot /mnt sed -i 's/^%wheel ALL=(ALL:ALL) NOPASSWD: ALL/# %wheel ALL=(ALL:ALL) NOPASSWD: ALL/' /etc/sudoers 1>/dev/null || exit 1

    # Paru config
    sed -i 's/^#BottomUp/BottomUp/g' /mnt/etc/paru.conf 1>/dev/null || exit 1
    sed -i 's/^#SudoLoop/SudoLoop/g' /mnt/etc/paru.conf 1>/dev/null || exit 1

    print_green "> Done\n"
fi

# /////////////////////////////////////////////////////

if [ -n "${ARCH_USER_SCRIPTS[*]}" ]; then

    print_title "Execute Scripts (Count: ${#ARCH_USER_SCRIPTS[@]})"

    # Run all user scripts iteratively
    for user_script in "${ARCH_USER_SCRIPTS[@]}"; do

        # Read script and add wait to the end of it
        script_content=$(printf '%s\n%s' "$(<"${user_script}")" 'wait')

        # Add sudo needs no password rights
        arch-chroot /mnt sed -i 's/^# %wheel ALL=(ALL:ALL) NOPASSWD: ALL/%wheel ALL=(ALL:ALL) NOPASSWD: ALL/' /etc/sudoers 1>/dev/null || exit 1

        # Run script as user (sudo needs no password)
        { arch-chroot /mnt /usr/bin/runuser -u "$ARCH_USERNAME" -- bash -c "$script_content" && wait; } 1>/dev/null || exit 1

        # Remove sudo needs no password rights
        arch-chroot /mnt sed -i 's/^%wheel ALL=(ALL:ALL) NOPASSWD: ALL/# %wheel ALL=(ALL:ALL) NOPASSWD: ALL/' /etc/sudoers 1>/dev/null || exit 1
    done

    print_green "> Done\n"
fi

# /////////////////////////////////////////////////////

print_title "Set Permissions"
arch-chroot /mnt chown -R "$ARCH_USERNAME":"$ARCH_USERNAME" "/home/${ARCH_USERNAME}" 1>/dev/null || exit 1
print_green "> Done\n"

# /////////////////////////////////////////////////////

print_title "Remove Orphans"
arch-chroot /mnt bash -c 'pacman -Qtd &>/dev/null && pacman -Qtdq | pacman -Rns --noconfirm - || echo "Skipped"' 1>/dev/null || exit 1

print_green "> Done\n"

# /////////////////////////////////////////////////////

print_title "Arch Installation finished"
print_green "\n!!! Please reboot now !!!\n"
