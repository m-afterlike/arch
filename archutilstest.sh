#!/bin/bash
set -e

# Ensure whiptail is installed
if ! command -v whiptail >/dev/null 2>&1; then
    echo "Whiptail is required for this script. Installing..."
    sudo pacman -S --noconfirm libnewt
fi

# Prompt for sudo password upfront
if sudo -v; then
    echo "Sudo access granted."
else
    echo "Failed to obtain sudo access."
    exit 1
fi

# Keep sudo session alive
( while true; do sudo -v; sleep 60; done ) &

# ASCII Art Header
echo "-----------------------------------------------"
echo "┌─────────────────────────────────────────────┐"
echo "│                                             │"
echo "│   _            _           _   _ _          │"
echo "│  /_\  _ __ ___| |__  /\ /\| |_(_) |___      │"
echo "│ //_\\| '__/ __| '_ \/ / \ \ __| | / __|     │"
echo "│/  _  \ | | (__| | | \ \_/ / |_| | \__ \     │"
echo "│\_/ \_/_|  \___|_| |_|\___/ \__|_|_|___/     │"
echo "│                                             │"
echo "└─────────────────────────────────────────────┘"
echo "-----------------------------------------------"
echo ""

# Function definitions

function install_aur_helper() {
    CHOICE=$(whiptail --title "Install AUR Helper" --menu "Choose an AUR helper to install:" 15 60 2 \
    "1" "paru" \
    "2" "yay" 3>&1 1>&2 2>&3)

    case "$CHOICE" in
        1)
            if command -v paru >/dev/null 2>&1; then
                whiptail --title "Info" --msgbox "Paru is already installed." 8 40
            else
                whiptail --title "Installing" --infobox "Installing paru..." 8 40
                sudo pacman -S --noconfirm base-devel git
                git clone https://aur.archlinux.org/paru.git
                cd paru
                makepkg -si --noconfirm
                cd ..
                rm -rf paru
                whiptail --title "Success" --msgbox "Paru installed successfully." 8 40
            fi
            ;;
        2)
            if command -v yay >/dev/null 2>&1; then
                whiptail --title "Info" --msgbox "Yay is already installed." 8 40
            else
                whiptail --title "Installing" --infobox "Installing yay..." 8 40
                sudo pacman -S --noconfirm base-devel git
                git clone https://aur.archlinux.org/yay.git
                cd yay
                makepkg -si --noconfirm
                cd ..
                rm -rf yay
                whiptail --title "Success" --msgbox "Yay installed successfully." 8 40
            fi
            ;;
        *)
            whiptail --title "Error" --msgbox "Invalid choice. Returning to main menu." 8 40
            ;;
    esac
}

function install_xorg_apps() {
    XORG_APPS=(
        "xorg-server"
        "xorg-apps"
        "xorg-xinit"
        "xorg-xinput"
        "xterm"
        "xorg-xclock"
        "xorg-twm"
        "xorg-xrandr"
        "xorg-xsetroot"
    )

    OPTIONS=()
    for app in "${XORG_APPS[@]}"; do
        OPTIONS+=("$app" "" OFF)
    done

    SELECTED_APPS=$(whiptail --title "Install Xorg Apps" --checklist \
    "Select Xorg apps to install:" 20 78 12 "${OPTIONS[@]}" 3>&1 1>&2 2>&3)

    if [ -n "$SELECTED_APPS" ]; then
        # Remove quotes and convert to array
        SELECTED_APPS=($(echo $SELECTED_APPS | tr -d '"'))
        sudo pacman -S --noconfirm "${SELECTED_APPS[@]}"
        whiptail --title "Success" --msgbox "Selected Xorg apps installed successfully." 8 60
    else
        whiptail --title "Info" --msgbox "No apps selected." 8 40
    fi
}

function install_suckless_tools() {
    SUCKLESS_TOOLS=("dwm" "dmenu" "st")
    OPTIONS=()
    for tool in "${SUCKLESS_TOOLS[@]}"; do
        OPTIONS+=("$tool" "" OFF)
    done

    SELECTED_TOOLS=$(whiptail --title "Install Suckless Tools" --checklist \
    "Select tools to clone and install:" 15 60 5 "${OPTIONS[@]}" 3>&1 1>&2 2>&3)

    if [ -n "$SELECTED_TOOLS" ]; then
        # Remove quotes and convert to array
        SELECTED_TOOLS=($(echo $SELECTED_TOOLS | tr -d '"'))
        declare -A SUCKLESS_REPOS=(
            ["dwm"]="https://git.suckless.org/dwm"
            ["dmenu"]="https://git.suckless.org/dmenu"
            ["st"]="https://git.suckless.org/st"
        )
        for tool in "${SELECTED_TOOLS[@]}"; do
            TARGET_DIR="$HOME/.config/$tool"
            mkdir -p "$TARGET_DIR"
            git clone "${SUCKLESS_REPOS[$tool]}" "$TARGET_DIR"
            whiptail --title "Cloning" --infobox "$tool cloned into $TARGET_DIR" 8 60
            if [ "$tool" == "dwm" ]; then
                # Install dependencies for dwm
                sudo pacman -S --noconfirm libx11 libxft libxinerama
                whiptail --title "Dependencies" --msgbox "Dependencies for dwm installed." 8 60
            fi
        done
        whiptail --title "Success" --msgbox "Selected suckless tools cloned successfully." 8 60
    else
        whiptail --title "Info" --msgbox "No tools selected." 8 40
    fi
}

function toggle_grub_verbose_logging() {
    CURRENT_SETTING=$(grep "^GRUB_CMDLINE_LINUX_DEFAULT" /etc/default/grub)
    if [[ "$CURRENT_SETTING" == *"debug"* ]]; then
        # Currently enabled, so disable
        sudo sed -i '/^GRUB_CMDLINE_LINUX_DEFAULT=/ s/ debug"$/"/' /etc/default/grub
        sudo grub-mkconfig -o /boot/grub/grub.cfg
        whiptail --title "GRUB Verbose Logging" --msgbox "GRUB verbose logging disabled." 8 60
    else
        # Currently disabled, so enable
        sudo sed -i '/^GRUB_CMDLINE_LINUX_DEFAULT=/ s/"$/ debug"/' /etc/default/grub
        sudo grub-mkconfig -o /boot/grub/grub.cfg
        whiptail --title "GRUB Verbose Logging" --msgbox "GRUB verbose logging enabled." 8 60
    fi
}

function toggle_os_prober() {
    CURRENT_SETTING=$(grep "^GRUB_DISABLE_OS_PROBER" /etc/default/grub | cut -d'=' -f2)
    if [[ "$CURRENT_SETTING" == "true" ]]; then
        sudo sed -i '/^GRUB_DISABLE_OS_PROBER=/d' /etc/default/grub
        echo "GRUB_DISABLE_OS_PROBER=false" | sudo tee -a /etc/default/grub
        sudo grub-mkconfig -o /boot/grub/grub.cfg
        whiptail --title "OS Prober" --msgbox "os-prober enabled." 8 40
    else
        sudo sed -i '/^GRUB_DISABLE_OS_PROBER=/d' /etc/default/grub
        echo "GRUB_DISABLE_OS_PROBER=true" | sudo tee -a /etc/default/grub
        sudo grub-mkconfig -o /boot/grub/grub.cfg
        whiptail --title "OS Prober" --msgbox "os-prober disabled." 8 40
    fi
}

function setup_secure_boot() {
    # Check if sbctl is installed
    if ! command -v sbctl >/dev/null 2>&1; then
        whiptail --title "Secure Boot Setup" --yesno "sbctl is not installed. Do you want to install it now?" 8 60
        if [ $? -eq 0 ]; then
            sudo pacman -S --noconfirm sbctl
            whiptail --title "Installation Complete" --msgbox "sbctl has been installed." 8 40
        else
            whiptail --title "Secure Boot Setup" --msgbox "sbctl is required for Secure Boot setup. Exiting." 8 60
            return
        fi
    fi

    # Regenerate the GRUB EFI binary with required modules
    whiptail --title "Secure Boot Setup" --infobox "Regenerating GRUB EFI binary..." 8 60
    sudo grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB --modules="tpm" --disable-shim-lock

    # Check sbctl status
    SBCTL_STATUS=$(sudo sbctl status)
    SETUP_MODE=$(echo "$SBCTL_STATUS" | grep "Setup Mode:" | awk '{print $4}')
    SECURE_BOOT=$(echo "$SBCTL_STATUS" | grep "Secure Boot:" | awk '{print $4}')

    # Display current Secure Boot status
    whiptail --title "Secure Boot Status" --msgbox "Setup Mode: $SETUP_MODE\nSecure Boot: $SECURE_BOOT" 8 60

    if [[ "$SETUP_MODE" != "Enabled" || "$SECURE_BOOT" != "Disabled" ]]; then
        whiptail --title "Warning" --msgbox "You must be in Setup Mode with Secure Boot disabled to proceed." 8 60
        whiptail --title "Secure Boot Setup" --yesno "Do you want to proceed anyway?" 8 60
        if [ $? -ne 0 ]; then
            whiptail --title "Secure Boot Setup" --msgbox "Exiting Secure Boot setup." 8 40
            return
        fi
    fi

    # Create custom Secure Boot keys
    if [ ! -f "/var/db/sbctl/secureboot.crt" ]; then
        whiptail --title "Secure Boot Setup" --infobox "Creating custom Secure Boot keys..." 8 60
        sudo sbctl create-keys
        whiptail --title "Keys Created" --msgbox "Custom Secure Boot keys have been created." 8 60
    else
        whiptail --title "Secure Boot Setup" --msgbox "Custom Secure Boot keys already exist." 8 60
    fi

    # Enroll custom keys including Microsoft's certificates
    whiptail --title "Secure Boot Setup" --yesno "Do you want to enroll the custom keys now? (This includes Microsoft's certificates)" 8 70
    if [ $? -eq 0 ]; then
        sudo sbctl enroll-keys -m
        whiptail --title "Keys Enrolled" --msgbox "Custom keys have been enrolled successfully." 8 60
    else
        whiptail --title "Secure Boot Setup" --msgbox "Custom keys were not enrolled. Exiting." 8 60
        return
    fi

    # Verify key enrollment
    SBCTL_STATUS=$(sudo sbctl status)
    whiptail --title "Secure Boot Status" --msgbox "$SBCTL_STATUS" 15 70

    # Detect EFI files excluding those under 'Microsoft' directories
    whiptail --title "Secure Boot Setup" --infobox "Detecting EFI files to sign..." 8 60
    mapfile -t EFI_FILES < <(sudo find /boot -type f -name "*.efi" ! -path "*/Microsoft/*")

    # Detect kernel images
    KERNEL_IMAGES=($(sudo find /boot -type f -name "vmlinuz-linux*" -o -name "vmlinuz-linux-lts" -o -name "vmlinuz-linux-hardened" -o -name "vmlinuz-linux-zen"))

    # Combine the files into a list
    FILES_TO_SIGN=("${EFI_FILES[@]}" "${KERNEL_IMAGES[@]}")

    # Prepare options for checklist
    OPTIONS=()
    for file in "${FILES_TO_SIGN[@]}"; do
        OPTIONS+=("$file" "" ON)
    done

    # Allow user to select files to sign
    SELECTED_FILES=$(whiptail --title "Files to Sign" --checklist \
    "Select the files you want to sign for Secure Boot:" 20 78 12 "${OPTIONS[@]}" 3>&1 1>&2 2>&3)

    if [ -n "$SELECTED_FILES" ]; then
        # Remove quotes and convert to array
        SELECTED_FILES=($(echo $SELECTED_FILES | tr -d '"'))
        # Sign selected files
        whiptail --title "Signing Files" --infobox "Signing selected files..." 8 60
        sudo sbctl sign-all
        for file in "${SELECTED_FILES[@]}"; do
            sudo sbctl sign -s "$file"
        done
        whiptail --title "Signing Complete" --msgbox "Selected files have been signed." 8 60
    else
        whiptail --title "No Files Selected" --msgbox "No files were selected for signing. Exiting." 8 60
        return
    fi

    # Run sbctl verify
    VERIFY_OUTPUT=$(sudo sbctl verify)
    whiptail --title "Verification Results" --msgbox "$VERIFY_OUTPUT" 15 70

    # Rebuild initramfs
    whiptail --title "Rebuilding initramfs" --infobox "Rebuilding initramfs..." 8 60
    sudo mkinitcpio -P
    whiptail --title "Rebuilding initramfs" --msgbox "initramfs has been rebuilt." 8 60

    # Regenerate GRUB configuration
    whiptail --title "Updating GRUB" --infobox "Regenerating GRUB configuration..." 8 60
    sudo grub-mkconfig -o /boot/grub/grub.cfg
    whiptail --title "Updating GRUB" --msgbox "GRUB configuration has been updated." 8 60

    # Completion message
    whiptail --title "Secure Boot Setup Complete" --msgbox "Secure Boot setup is complete." 8 60

    # Ask to reboot into UEFI settings
    whiptail --title "Reboot Required" --yesno "Would you like to reboot now to enable Secure Boot in UEFI settings?" 8 70
    if [ $? -eq 0 ]; then
        whiptail --title "Rebooting" --msgbox "The system will reboot into UEFI firmware settings." 8 60
        sleep 2
        sudo systemctl reboot --firmware-setup
    else
        whiptail --title "Reboot Later" --msgbox "You can reboot and enable Secure Boot from UEFI settings later." 8 70
    fi
}


function create_user_directories() {
    sudo pacman -S --noconfirm xdg-user-dirs
    xdg-user-dirs-update
    whiptail --title "Success" --msgbox "User directories created successfully." 8 60
}

function set_system_clock_dual_boot_windows() {
    local rtc_setting=$(timedatectl | grep "RTC in local TZ" | awk '{print $NF}')
    if [[ "$rtc_setting" == "yes" ]]; then
        whiptail --title "System Clock" --msgbox "System clock is already set for Windows dual boot." 8 60
    else
        sudo timedatectl set-local-rtc 1 --adjust-system-clock
        whiptail --title "System Clock" --msgbox "System clock set for Windows dual boot." 8 60
    fi
}

function boot_into_uefi() {
    whiptail --title "Rebooting" --msgbox "System will reboot into UEFI firmware settings." 8 60
    sleep 2
    sudo systemctl reboot --firmware-setup
}

function exit_script() {
    whiptail --title "Exit" --msgbox "Exiting archutils." 8 40
    # Kill the sudo keep-alive background job
    kill %%
    exit 0
}

# Main Menu Loop
while true; do
    MAIN_CHOICE=$(whiptail --title "Archutils Menu" --menu "Choose an option:" 20 78 10 \
    "1" "Installs" \
    "2" "Boot Configuration" \
    "3" "Utils" \
    "4" "Exit" 3>&1 1>&2 2>&3)

    case "$MAIN_CHOICE" in
        1)
            # Installs submenu
            INSTALL_CHOICE=$(whiptail --title "Installs" --menu "Choose an option:" 20 78 10 \
            "1" "Install AUR Helper" \
            "2" "Install Xorg Apps" \
            "3" "Install Suckless Tools" \
            "4" "Back to Main Menu" 3>&1 1>&2 2>&3)
            case "$INSTALL_CHOICE" in
                1) install_aur_helper ;;
                2) install_xorg_apps ;;
                3) install_suckless_tools ;;
                4) continue ;;
                *) whiptail --title "Error" --msgbox "Invalid choice. Returning to main menu." 8 60 ;;
            esac
            ;;
        2)
            # Boot Configuration submenu
            BOOT_CHOICE=$(whiptail --title "Boot Configuration" --menu "Choose an option:" 20 78 10 \
            "1" "Toggle GRUB Verbose Logging" \
            "2" "Toggle OS Prober" \
            "3" "Setup Secure Boot" \
            "4" "Back to Main Menu" 3>&1 1>&2 2>&3)
            case "$BOOT_CHOICE" in
                1) toggle_grub_verbose_logging ;;
                2) toggle_os_prober ;;
                3) setup_secure_boot ;;
                4) continue ;;
                *) whiptail --title "Error" --msgbox "Invalid choice. Returning to main menu." 8 60 ;;
            esac
            ;;
        3)
            # Utils submenu
            UTILS_CHOICE=$(whiptail --title "Utils" --menu "Choose an option:" 20 78 10 \
            "1" "Create User Directories" \
            "2" "Set System Clock for Windows Dual Boot" \
            "3" "Boot into UEFI Firmware Settings" \
            "4" "Back to Main Menu" 3>&1 1>&2 2>&3)
            case "$UTILS_CHOICE" in
                1) create_user_directories ;;
                2) set_system_clock_dual_boot_windows ;;
                3) boot_into_uefi ;;
                4) continue ;;
                *) whiptail --title "Error" --msgbox "Invalid choice. Returning to main menu." 8 60 ;;
            esac
            ;;
        4) exit_script ;;
        *)
            whiptail --title "Error" --msgbox "Invalid choice. Please try again." 8 60
            ;;
    esac
done
