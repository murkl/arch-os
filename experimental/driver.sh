#!/usr/bin/env bash
set -Eeuo pipefail

# ///////////////////////////////////////////////////////////////////
# Print functions
# ///////////////////////////////////////////////////////////////////

print_green() { echo -e "\e[32m${1}\e[0m"; }
print_red() { echo -e "\e[31m${1}\e[0m"; }
print_blue() { echo -e "\e[34m${1}\e[0m"; }
print_yellow() { echo -e "\e[33m${1}\e[0m"; }
print_purple() { echo -e "\e[35m${1}\e[0m"; }
print_cyan() { echo -e "\e[36m${1}\e[0m"; }

# ///////////////////////////////////////////////////////////////////
# Menu
# ///////////////////////////////////////////////////////////////////

clear
print_yellow '┌───────────────────────────────────────────────────────────────────┐'
print_yellow '│                      ARCH GRAPHICS DRIVER                         │'
print_yellow '└───────────────────────────────────────────────────────────────────┘'
print_yellow '┌───────────────────────────────────────────────────────────────────┐'
print_yellow '│   1:  Intel HD                                                    │'
print_yellow '│   2:  NVIDIA                                                      │'
print_yellow '│   3:  NVIDIA Optimus                                              │'
print_yellow '│   4:  AMD                                                         │'
print_yellow '│   5:  AMD Legacy                                                  │'
print_yellow '│                                                                   │'
print_yellow '│   q:  Quit                                                        │'
print_yellow '└───────────────────────────────────────────────────────────────────┘'

echo -e "" && read -r -p ": > " ARCH_DRIVER
case "${ARCH_DRIVER}" in

# ///////////////////////////////////////////////////////////////////
# Intel HD
# ///////////////////////////////////////////////////////////////////

1) # https://wiki.archlinux.org/title/Intel_graphics#Installation

    # Packages
    packages=()
    packages+=("vulkan-intel") && packages+=("lib32-vulkan-intel")
    packages+=("gamemode") && packages+=("lib32-gamemode")
    packages+=("libva-intel-driver")
    packages+=("intel-media-driver")

    # Install packages
    sudo pacman -S --noconfirm --needed --disable-download-timeout "${packages[@]}"

    # Configure mkinitcpio
    sudo sed -i "s/MODULES=()/MODULES=(i915)/g" /etc/mkinitcpio.conf

    # Rebuild initramfs
    sudo mkinitcpio -P
    ;;

# ///////////////////////////////////////////////////////////////////
# NVIDIA
# ///////////////////////////////////////////////////////////////////

2) # https://wiki.archlinux.org/title/NVIDIA#Installation

    # Packages
    packages=()
    packages+=("xorg-xrandr")
    packages+=("nvidia-lts")
    packages+=("nvidia-settings")
    packages+=("nvidia-utils") && packages+=("lib32-nvidia-utils")
    packages+=("opencl-nvidia") && packages+=("lib32-opencl-nvidia")
    packages+=("gamemode") && packages+=("lib32-gamemode")

    # Install packages
    sudo pacman -S --noconfirm --needed --disable-download-timeout "${packages[@]}"

    # Early Loading
    sudo sed -i "s/MODULES=()/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/g" /etc/mkinitcpio.conf

    # DRM kernel mode setting
    sudo sed -i "s/nowatchdog quiet/nowatchdog nvidia_drm.modeset=1 quiet/g" /boot/loader/entries/arch.conf

    # Rebuild
    sudo mkinitcpio -P

    # Enable Wayland Support (https://wiki.archlinux.org/title/GDM#Wayland_and_the_proprietary_NVIDIA_driver)
    sudo ln -s /dev/null /etc/udev/rules.d/61-gdm.rules
    ;;

# ///////////////////////////////////////////////////////////////////
# NVIDIA Optimus
# ///////////////////////////////////////////////////////////////////

3) # https://wiki.archlinux.org/title/NVIDIA_Optimus#Use_NVIDIA_graphics_only

    # Packages
    packages=()
    packages+=("xorg-xrandr")
    packages+=("nvidia-lts")
    packages+=("nvidia-settings")
    packages+=("nvidia-utils") && packages+=("lib32-nvidia-utils")
    packages+=("opencl-nvidia") && packages+=("lib32-opencl-nvidia")
    packages+=("gamemode") && packages+=("lib32-gamemode")
    packages+=("libva-intel-driver") # (fixed errors on loading NVIDIA)
    packages+=("intel-media-driver")

    # Install packages
    sudo pacman -S --noconfirm --needed --disable-download-timeout "${packages[@]}"

    # Early Loading
    sudo sed -i "s/MODULES=()/MODULES=(i915 nvidia nvidia_modeset nvidia_uvm nvidia_drm)/g" /etc/mkinitcpio.conf

    # DRM kernel mode setting (enable prime sync and fix screen-tearing issues)
    sudo sed -i "s/nowatchdog quiet/nowatchdog nvidia_drm.modeset=1 quiet/g" /boot/loader/entries/arch.conf

    # Rebuild
    sudo mkinitcpio -P

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
    } | sudo tee /etc/X11/xorg.conf.d/10-nvidia-drm-outputclass.conf

    # Configure GDM
    {
        echo '[Desktop Entry]'
        echo 'Type=Application'
        echo 'Name=Optimus'
        echo 'Exec=sh -c "xrandr --setprovideroutputsource modesetting NVIDIA-0; xrandr --auto"'
        echo 'NoDisplay=true'
        echo 'X-GNOME-Autostart-Phase=DisplayServer'
    } | sudo tee /usr/share/gdm/greeter/autostart/optimus.desktop /etc/xdg/autostart/optimus.desktop

    # Disable Wayland Support (https://wiki.archlinux.org/title/GDM#Wayland_and_the_proprietary_NVIDIA_driver)
    [ -f /etc/udev/rules.d/61-gdm.rules ] && sudo rm -f /etc/udev/rules.d/61-gdm.rules

    # GNOME: Enable X11 instead of Wayland
    sudo sed -i "s/^#WaylandEnable=false/WaylandEnable=false/g" /etc/gdm/custom.conf
    ;;

# ///////////////////////////////////////////////////////////////////
# AMD
# ///////////////////////////////////////////////////////////////////

4) # https://wiki.archlinux.org/title/AMDGPU#Installation

    # Packages
    packages=()
    packages+=("xf86-video-amdgpu")
    packages+=("libva-mesa-driver") && packages+=("lib32-libva-mesa-driver")
    packages+=("vulkan-radeon") && packages+=("lib32-vulkan-radeon")
    packages+=("mesa-vdpau") && packages+=("lib32-mesa-vdpau")
    packages+=("gamemode") && packages+=("lib32-gamemode")

    # Install packages
    sudo pacman -S --noconfirm --needed --disable-download-timeout "${packages[@]}"

    # Early Loading
    sudo sed -i "s/MODULES=()/MODULES=(radeon)/g" /etc/mkinitcpio.conf

    # Rebuild
    sudo mkinitcpio -P
    ;;

# ///////////////////////////////////////////////////////////////////
# AMD Legacy
# ///////////////////////////////////////////////////////////////////

5) # https://wiki.archlinux.org/title/ATI#Installation

    # Packages
    packages=()
    packages+=("xf86-video-ati")
    packages+=("libva-mesa-driver") && packages+=("lib32-libva-mesa-driver")
    packages+=("mesa-vdpau") && packages+=("lib32-mesa-vdpau")
    packages+=("gamemode") && packages+=("lib32-gamemode")

    # Install packages
    sudo pacman -S --noconfirm --needed --disable-download-timeout "${packages[@]}"

    # Early Loading
    sudo sed -i "s/MODULES=()/MODULES=(amdgpu radeon)/g" /etc/mkinitcpio.conf

    # Rebuild
    sudo mkinitcpio -P
    ;;

# ///////////////////////////////////////////////////////////////////
# Empty
# ///////////////////////////////////////////////////////////////////

*)
    print_red "Error: Input was empty"
    exit 1
    ;;

esac

# ///////////////////////////////////////////////////////////////////
# Finished
# ///////////////////////////////////////////////////////////////////

print_green "Graphics driver successfull installed!"
