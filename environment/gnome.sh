#!/usr/bin/env bash

# List available drivers (key & value)
if [ "$1" = "--list-driver" ]; then
    echo "intel-hd" && echo "Intel HD"
    echo "nvidia" && echo "NVIDIA"
    echo "nvidia-optimus" && echo "NVIDIA Optimus"
    exit 0
fi

# /////////////////////////////////////////////////////

# Assets
PLYMOUTH_LOGO_URL="https://raw.githubusercontent.com/murkl/arch-distro/main/environment/assets/plymouth.png"

# /////////////////////////////////////////////////////

# Check required variables
[ -z "$ENVIRONMENT_X11_KEYBOARD_LAYOUT" ] && echo "env ENVIRONMENT_X11_KEYBOARD_LAYOUT is missing" && exit 1
[ -z "$ENVIRONMENT_X11_KEYBOARD_VARIANT" ] && echo "env ENVIRONMENT_X11_KEYBOARD_VARIANT is missing" && exit 1

# /////////////////////////////////////////////////////

# Enable Multilib
sudo sed -i "/\[multilib\]/,/Include/"'s/^#//' /etc/pacman.conf || exit 1

# /////////////////////////////////////////////////////

# Install Packages
packages=()

# GNOME
packages+=("gnome")
packages+=("gnome-tweaks")
packages+=("gnome-themes-extra")
packages+=("gnome-software-packagekit-plugin")
packages+=("xdg-desktop-portal")
packages+=("xdg-desktop-portal-gtk")
packages+=("xdg-desktop-portal-gnome")
packages+=("libappindicator-gtk3")
packages+=("libappindicator-gtk2")
packages+=("lib32-libindicator-gtk3")
packages+=("lib32-libindicator-gtk2")
packages+=("power-profiles-daemon")
packages+=("fwupd")
packages+=("cups")

# Driver
packages+=("mesa")
packages+=("lib32-mesa")
packages+=("vulkan-tools")
packages+=("vulkan-icd-loader")
packages+=("lib32-vulkan-icd-loader")
packages+=("xf86-input-synaptics")

# System
packages+=("pacman-contrib")
packages+=("xdotool")
packages+=("wmctrl")
packages+=("sshpass")
packages+=("man-db")
packages+=("nano-syntax-highlighting")

# Networking
packages+=("samba")
packages+=("gvfs")
packages+=("gvfs-mtp")
packages+=("gvfs-smb")
packages+=("gvfs-nfs")
packages+=("gvfs-afc")
packages+=("gvfs-goa")
packages+=("gvfs-gphoto2")
packages+=("gvfs-google")
packages+=("inetutils")

# File Access & Archives
packages+=("nfs-utils")
packages+=("ntfs-3g")
packages+=("exfat-utils")
packages+=("p7zip")
packages+=("zip")
packages+=("unrar")
packages+=("tar")

# Audio
packages+=("pipewire")
packages+=("wireplumber")
packages+=("pipewire-pulse")
packages+=("pipewire-jack")

# Codecs
packages+=("gst-libav")
packages+=("gst-plugin-pipewire")
packages+=("gst-plugins-good")
packages+=("gst-plugins-bad")
packages+=("gst-plugins-ugly")
packages+=("gstreamer-vaapi")
packages+=("rygel")
packages+=("grilo-plugins")

# Libraries
packages+=("sdl_image")
packages+=("lib32-sdl_image")

# Fonts
packages+=("ttf-dejavu")
packages+=("ttf-liberation")
packages+=("noto-fonts")
packages+=("noto-fonts-emoji")
packages+=("ttf-font-awesome")
packages+=("lib32-fontconfig")

# Apps
packages+=("seahorse")
packages+=("firefox")
packages+=("geary")
packages+=("rhythmbox")

sudo pacman -Sy --noconfirm --needed "${packages[@]}" || exit 1

# /////////////////////////////////////////////////////

# Install GNOME browser connector
git clone https://aur.archlinux.org/gnome-browser-connector.git /tmp/gnome-browser-connector || exit 1
cd /tmp/gnome-browser-connector || exit 1
yes | LC_ALL=en_US.UTF-8 makepkg -sif || exit 1
cd && rm -rf /tmp/gnome-browser-connector || exit 1

# /////////////////////////////////////////////////////

# Install Plymouth
git clone https://aur.archlinux.org/plymouth.git /tmp/plymouth || exit 1
cd /tmp/plymouth || exit 1
yes | LC_ALL=en_US.UTF-8 makepkg -sif || exit 1
cd && rm -rf /tmp/plymouth || exit 1

# Install Plymouth (GDM)
git clone https://aur.archlinux.org/gdm-plymouth.git /tmp/gdm-plymouth || exit 1
cd /tmp/gdm-plymouth || exit 1
sed -i 's/^options=(debug)/options=(!debug)/' PKGBUILD || exit 1
yes | LC_ALL=en_US.UTF-8 makepkg -sif || exit 1
cd && rm -rf /tmp/gdm-plymouth || exit 1

# Download plymouth watermark
curl -Lfs "$PLYMOUTH_LOGO_URL" >"/tmp/plymouth-watermark.png" || exit 1
sudo cp -f "/tmp/plymouth-watermark.png" "/usr/share/plymouth/themes/spinner/watermark.png" || exit 1

replace_spinner_conf_value() {
    sudo sed -i "s#$1=.*#$1=$2#g" "/usr/share/plymouth/themes/spinner/spinner.plymouth" || exit 1
}

# Configure plymouth
replace_spinner_conf_value "DialogVerticalAlignment" ".680"
replace_spinner_conf_value "TitleVerticalAlignment" ".680"
replace_spinner_conf_value "BackgroundStartColor" "0x2E3440"
replace_spinner_conf_value "BackgroundEndColor" "0x2E3440"

# Configure mkinitcpio
sudo sed -i "s/base systemd autodetect/base systemd sd-plymouth autodetect/g" /etc/mkinitcpio.conf || exit 1

# Rebuild
sudo mkinitcpio -P || exit 1

# /////////////////////////////////////////////////////

# Remove packages
sudo pacman -Rns --noconfirm gnome-music || exit 1
sudo pacman -Rns --noconfirm epiphany || exit 1

# /////////////////////////////////////////////////////

# Enable GNOME Auto Login
grep -qrnw /etc/gdm/custom.conf -e "AutomaticLoginEnable" || sudo sed -i "s/^\[security\]/AutomaticLoginEnable=True\nAutomaticLogin=${USER}\n\n\[security\]/g" /etc/gdm/custom.conf || exit 1

# /////////////////////////////////////////////////////

# Reduce shutdown timeout
sudo sed -i 's/^#DefaultTimeoutStopSec=.*/DefaultTimeoutStopSec=5s/' /etc/systemd/system.conf || exit 1

# /////////////////////////////////////////////////////

# Enable Bluetooth Experimental D-Bus (fixing issues in systemd journal)
sudo sed -i 's/^#Experimental = .*/Experimental = true/' /etc/bluetooth/main.conf || exit 1

# /////////////////////////////////////////////////////

# Nano Colors
grep -qrnw /etc/nanorc -e 'include "/usr/share/nano-syntax-highlighting/\*.nanorc"' || echo -e '\ninclude "/usr/share/nano-syntax-highlighting/*.nanorc"' | sudo tee -a /etc/nanorc &>/dev/null || exit 1

# /////////////////////////////////////////////////////

# Git Credentials
mkdir -p "/home/$USER/.config/git" && touch "/home/$USER/.config/git/config" || exit 1
git config --global credential.helper /usr/lib/git-core/git-credential-libsecret || exit 1

# /////////////////////////////////////////////////////

# Create Samba config
mkdir -p "/etc/samba/"
{
    echo "[global]"
    echo "   workgroup = WORKGROUP"
    echo "   log file = /var/log/samba/%m"
} | sudo tee /etc/samba/smb.conf &>/dev/null || exit 1

# /////////////////////////////////////////////////////

# Set X11 keyboard layout
{
    echo 'Section "InputClass"'
    echo '    Identifier "keyboard"'
    echo '    MatchIsKeyboard "yes"'
    echo '    Option "XkbLayout" "'"${ENVIRONMENT_X11_KEYBOARD_LAYOUT}"'"'
    echo '    Option "XkbModel" "pc105"'
    echo '    Option "XkbVariant" "'"${ENVIRONMENT_X11_KEYBOARD_VARIANT}"'"'
    echo 'EndSection'
} | sudo tee /etc/X11/xorg.conf.d/00-keyboard.conf &>/dev/null || exit 1

# Set X11 mouse layout
{
    echo 'Section "InputClass"'
    echo '    Identifier "mouse"'
    echo '    Driver "libinput"'
    echo '    MatchIsPointer "yes"'
    echo '    Option "AccelProfile" "flat"'
    echo '    Option "AccelSpeed" "0"'
    echo 'EndSection'
} | sudo tee /etc/X11/xorg.conf.d/50-mouse.conf &>/dev/null || exit 1

# Set X11 touchpad layout
{
    echo 'Section "InputClass"'
    echo '    Identifier "touchpad"'
    echo '    Driver "libinput"'
    echo '    MatchIsTouchpad "on"'
    echo '    Option "ClickMethod" "clickfinger"'
    echo '    Option "Tapping" "off"'
    echo '    Option "NaturalScrolling" "true"'
    echo 'EndSection'
} | sudo tee /etc/X11/xorg.conf.d/70-touchpad.conf &>/dev/null || exit 1

# /////////////////////////////////////////////////////

# Enable system services
sudo systemctl enable gdm.service || exit 1       # GNOME
sudo systemctl enable bluetooth.service || exit 1 # Bluetooth
sudo systemctl enable avahi-daemon || exit 1      # Network browsing service
sudo systemctl enable cups.service || exit 1      # Printer
sudo systemctl enable smb.service || exit 1       # Samba
sudo systemctl enable nmb.service || exit 1       # Samba

# Enable user services
systemctl enable --user pipewire.service || exit 1       # Pipewire
systemctl enable --user pipewire-pulse.service || exit 1 # Pipewire
systemctl enable --user wireplumber.service || exit 1    # Pipewire

# /////////////////////////////////////////////////////

if [ "$ENVIRONMENT_DRIVER" = "intel-hd" ]; then

    # https://wiki.archlinux.org/title/Intel_graphics#Installation

    # Intel Driver
    packages=()
    #packages+=("xf86-video-intel") # Not recommended
    packages+=("vulkan-intel")
    packages+=("lib32-vulkan-intel")
    packages+=("intel-media-driver")
    packages+=("libva-intel-driver")
    packages+=("libva-utils")
    packages+=("virtualgl")
    packages+=("lib32-virtualgl")
    packages+=("gamemode")
    packages+=("lib32-gamemode")

    # Install packages
    sudo pacman -Sy --noconfirm --needed "${packages[@]}" || exit 1

    # Configure mkinitcpio
    sudo sed -i "s/MODULES=()/MODULES=(i915)/g" /etc/mkinitcpio.conf || exit 1

    # Rebuild initramfs
    sudo mkinitcpio -P || exit 1
fi

# /////////////////////////////////////////////////////

if [ "$ENVIRONMENT_DRIVER" = "nvidia" ]; then

    # https://wiki.archlinux.org/title/NVIDIA#Installation

    # NVIDIA Driver
    packages=()
    packages+=("xorg-xrandr")
    packages+=("nvidia")
    packages+=("lib32-nvidia-utils")
    packages+=("nvidia-settings")
    packages+=("opencl-nvidia")
    packages+=("lib32-opencl-nvidia")
    packages+=("virtualgl")
    packages+=("lib32-virtualgl")
    packages+=("gamemode")
    packages+=("lib32-gamemode")

    # Install packages
    sudo pacman -Sy --noconfirm --needed "${packages[@]}" || exit 1

    # Enable Wayland Support (https://wiki.archlinux.org/title/GDM#Wayland_and_the_proprietary_NVIDIA_driver)
    sudo ln -s /dev/null /etc/udev/rules.d/61-gdm.rules || exit 1

    # Early Loading
    sudo sed -i "s/MODULES=()/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/g" /etc/mkinitcpio.conf || exit 1

    # DRM kernel mode setting
    sudo sed -i "s/nowatchdog quiet/nowatchdog nvidia_drm.modeset=1 quiet/g" /boot/loader/entries/arch.conf || exit 1

    # Rebuild
    sudo mkinitcpio -P || exit 1
fi

# /////////////////////////////////////////////////////

if [ "$ENVIRONMENT_DRIVER" = "nvidia-optimus" ]; then

    # https://wiki.archlinux.org/title/NVIDIA_Optimus#Use_NVIDIA_graphics_only

    packages=()

    # Intel Driver
    #packages+=("xf86-video-intel") # Not recommended
    packages+=("vulkan-intel")
    packages+=("lib32-vulkan-intel")
    packages+=("intel-media-driver")
    packages+=("libva-intel-driver")
    packages+=("libva-utils")

    # NVIDIA Driver
    packages+=("xorg-xrandr")
    packages+=("nvidia")
    packages+=("lib32-nvidia-utils")
    packages+=("nvidia-settings")
    packages+=("opencl-nvidia")
    packages+=("lib32-opencl-nvidia")
    packages+=("virtualgl")
    packages+=("lib32-virtualgl")
    packages+=("gamemode")
    packages+=("lib32-gamemode")

    # Install packages
    sudo pacman -Sy --noconfirm --needed "${packages[@]}" || exit 1

    # Early Loading
    sudo sed -i "s/MODULES=()/MODULES=(i915 nvidia nvidia_modeset nvidia_uvm nvidia_drm)/g" /etc/mkinitcpio.conf || exit 1

    # DRM kernel mode setting (enable prime sync and fix screen-tearing issues)
    sudo sed -i "s/nowatchdog quiet/nowatchdog nvidia_drm.modeset=1 quiet/g" /boot/loader/entries/arch.conf || exit 1

    # Rebuild
    sudo mkinitcpio -P || exit 1

    # Configure Xorg
    {
        echo 'Section "OutputClass"'
        echo '    Identifier "intel"'
        echo '    MatchDriver "i915"'
        echo '    Driver "modesetting"'
        echo 'EndSection'
        echo ''
        echo 'Section "OutputClass"'
        echo '    Identifier "nvidia"'
        echo '    MatchDriver "nvidia-drm"'
        echo '    Driver "nvidia"'
        echo '    Option "AllowEmptyInitialConfiguration"'
        echo '    Option "PrimaryGPU" "yes"'
        echo '    ModulePath "/usr/lib/nvidia/xorg"'
        echo '    ModulePath "/usr/lib/xorg/modules"'
        echo 'EndSection'
    } | sudo tee /etc/X11/xorg.conf.d/10-nvidia-drm-outputclass.conf &>/dev/null || exit 1

    # Configure GDM
    {
        echo '[Desktop Entry]'
        echo 'Type=Application'
        echo 'Name=Optimus'
        echo 'Exec=sh -c "xrandr --setprovideroutputsource modesetting NVIDIA-0; xrandr --auto"'
        echo 'NoDisplay=true'
        echo 'X-GNOME-Autostart-Phase=DisplayServer'
    } | sudo tee /usr/share/gdm/greeter/autostart/optimus.desktop /etc/xdg/autostart/optimus.desktop &>/dev/null || exit 1

    # Disable Wayland Support (https://wiki.archlinux.org/title/GDM#Wayland_and_the_proprietary_NVIDIA_driver)
    sudo rm -f /etc/udev/rules.d/61-gdm.rules || exit 1

    # GNOME: Enable X11 instead of Wayland
    sudo sed -i "s/^#WaylandEnable=false/WaylandEnable=false/g" /etc/gdm/custom.conf || exit 1
fi

# /////////////////////////////////////////////////////

# Set correct permissions
sudo chown -R "$USER":"$USER" "/home/${USER}" || exit 1
