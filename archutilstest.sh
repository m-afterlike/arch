#!/bin/bash
set -e

echo "-----------------------------------------------"
echo "        Archutils Post-Install Script          "
echo "-----------------------------------------------"
echo ""
echo "   _            _           _   _ _     "
echo "  /_\  _ __ ___| |__  /\ /\| |_(_) |___ "
echo " //_\\| '__/ __| '_ \/ / \ \ __| | / __|"
echo "/  _  \ | | (__| | | \ \_/ / |_| | \__ \\"
echo "\_/ \_/_|  \___|_| |_|\___/ \__|_|_|___/"
echo ""

# Define the options
OPTIONS=(
    "Enable GRUB verbose logging"
    "Disable GRUB verbose logging"
    "Set up Secure Boot"
    "Enable os-prober (detect other OSes in GRUB)"
    "Disable os-prober"
    "Set system clock for dual booting Windows"
    "Install paru"
    "Install yay"
    "Install Xorg apps (with selectors)"
    "Create user directories like ~/Desktop and ~/Music"
    "Git clone dwm, dmenu, and st from suckless"
    "Boot into UEFI Firmware Settings"
    "Exit"
)

# Functions for each option
function enable_grub_verbose_logging() {
    echo "Enabling GRUB verbose logging..."
    sudo sed -i '/^GRUB_CMDLINE_LINUX_DEFAULT=/ s/"$/ debug"/' /etc/default/grub
    sudo grub-mkconfig -o /boot/grub/grub.cfg
    echo "GRUB verbose logging enabled."
}

function disable_grub_verbose_logging() {
    echo "Disabling GRUB verbose logging..."
    sudo sed -i '/^GRUB_CMDLINE_LINUX_DEFAULT=/ s/ debug"$/"/' /etc/default/grub
    sudo grub-mkconfig -o /boot/grub/grub.cfg
    echo "GRUB verbose logging disabled."
}

function setup_secure_boot() {
    echo "Setting up Secure Boot..."
    # Regenerate the GRUB EFI binary with required modules
    echo "Regenerating GRUB EFI binary..."
    sudo grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB --modules="tpm" --disable-shim-lock

    # Check sbctl status
    SBCTL_STATUS=$(sudo sbctl status)
    echo "$SBCTL_STATUS"

    SETUP_MODE=$(echo "$SBCTL_STATUS" | grep "Setup Mode:" | awk '{print $4}')
    SECURE_BOOT=$(echo "$SBCTL_STATUS" | grep "Secure Boot:" | awk '{print $4}')

    if [[ "$SETUP_MODE" == "Enabled" && "$SECURE_BOOT" == "Disabled" ]]; then
        echo "System is in Setup Mode with Secure Boot disabled."
    else
        echo "Warning: You must be in Setup Mode with Secure Boot disabled to proceed."
        echo "Current Setup Mode: $SETUP_MODE"
        echo "Current Secure Boot: $SECURE_BOOT"
        echo ""
        read -p "Do you want to proceed anyway? (yes/no): " PROCEED
        if [[ "$PROCEED" != "yes" ]]; then
            echo "Exiting Secure Boot setup."
            return 1
        fi
    fi

    # Create custom Secure Boot keys
    sudo sbctl create-keys

    # Enroll custom keys including Microsoft's certificates
    sudo sbctl enroll-keys -m

    # Verify key enrollment
    sudo sbctl status

    # Pause
    read -p "Press Enter to continue..."

    # Detect EFI files excluding those under 'Microsoft' directories
    echo "Detecting EFI files to sign..."
    mapfile -t EFI_FILES < <(sudo find /boot -type f -name "*.efi" ! -path "*/Microsoft/*")

    # Detect vmlinuz-linux and other kernels
    KERNEL_IMAGES=($(sudo find /boot -type f -name "vmlinuz-linux*" -o -name "vmlinuz-linux-lts" -o -name "vmlinuz-linux-hardened" -o -name "vmlinuz-linux-zen"))

    # Combine the files into a list
    FILES_TO_SIGN=("${EFI_FILES[@]}" "${KERNEL_IMAGES[@]}")

    # Remove empty entries
    FILES_TO_SIGN=("${FILES_TO_SIGN[@]}")

    # List the files with numbers
    echo "Files detected for signing:"
    i=1
    for file in "${FILES_TO_SIGN[@]}"; do
        echo "$i) $file"
        ((i++))
    done

    # Ask if user wants to edit the list
    read -p "Do you want to edit the list? (yes/no): " EDIT_LIST
    if [[ "$EDIT_LIST" == "yes" ]]; then
        while true; do
            echo "Options:"
            echo "1) Remove an entry"
            echo "2) Add an entry"
            echo "3) Proceed with current list"
            read -p "Choose an option [1-3]: " EDIT_OPTION
            case "$EDIT_OPTION" in
                1)
                    read -p "Enter the number of the entry to remove: " REMOVE_NUM
                    if [[ "$REMOVE_NUM" -gt 0 && "$REMOVE_NUM" -le "${#FILES_TO_SIGN[@]}" ]]; then
                        unset 'FILES_TO_SIGN[REMOVE_NUM-1]'
                        # Re-index the array
                        FILES_TO_SIGN=("${FILES_TO_SIGN[@]}")
                        # Re-list the files
                        echo "Updated list:"
                        i=1
                        for file in "${FILES_TO_SIGN[@]}"; do
                            echo "$i) $file"
                            ((i++))
                        done
                    else
                        echo "Invalid number."
                    fi
                    ;;
                2)
                    read -p "Enter the full path of the file to add: " ADD_PATH
                    if [[ -f "$ADD_PATH" ]]; then
                        FILES_TO_SIGN+=("$ADD_PATH")
                        # Re-list the files
                        echo "Updated list:"
                        i=1
                        for file in "${FILES_TO_SIGN[@]}"; do
                            echo "$i) $file"
                            ((i++))
                        done
                    else
                        echo "File does not exist."
                    fi
                    ;;
                3)
                    break
                    ;;
                *)
                    echo "Invalid option."
                    ;;
            esac
        done
    fi

    # Sign all files using sbctl
    echo "Signing files..."
    sudo sbctl sign-all
    for file in "${FILES_TO_SIGN[@]}"; do
        sudo sbctl sign -s "$file"
    done

    # Run sbctl verify
    sudo sbctl verify

    # Ask if user wants to proceed or add more paths
    read -p "Do you need to sign additional files? (yes/no): " ADD_FILES
    if [[ "$ADD_FILES" == "yes" ]]; then
        while true; do
            read -p "Enter the full path of the file to sign (or 'done' to finish): " EXTRA_PATH
            if [[ "$EXTRA_PATH" == "done" ]]; then
                break
            elif [[ -f "$EXTRA_PATH" ]]; then
                sudo sbctl sign -s "$EXTRA_PATH"
            else
                echo "File does not exist."
            fi
        done
    fi

    # Rebuild initramfs
    sudo mkinitcpio -P

    # Regenerate GRUB configuration
    sudo grub-mkconfig -o /boot/grub/grub.cfg

    # Completion message
    echo "Secure Boot setup script completed."

    read -p "Would you like to reboot into UEFI to enable Secure Boot? (yes/no): " REBOOT_CHOICE
    if [[ "$REBOOT_CHOICE" == "yes" ]]; then
        echo "Rebooting into UEFI firmware setup..."
        sudo systemctl reboot --firmware-setup
    else
        echo "You can reboot and enable Secure Boot from UEFI settings later."
    fi
}

function enable_os_prober() {
    echo "Enabling os-prober..."
    # Install os-prober
    sudo pacman -S --noconfirm os-prober

    # Enable os-prober in GRUB configuration
    sudo sed -i '/^GRUB_DISABLE_OS_PROBER=/d' /etc/default/grub
    echo "GRUB_DISABLE_OS_PROBER=false" | sudo tee -a /etc/default/grub

    # Regenerate GRUB configuration
    sudo grub-mkconfig -o /boot/grub/grub.cfg

    echo "os-prober enabled. GRUB will now detect other operating systems."
}

function disable_os_prober() {
    echo "Disabling os-prober..."
    # Remove or comment out the os-prober line in GRUB configuration
    sudo sed -i '/^GRUB_DISABLE_OS_PROBER=/d' /etc/default/grub
    echo "GRUB_DISABLE_OS_PROBER=true" | sudo tee -a /etc/default/grub

    # Regenerate GRUB configuration
    sudo grub-mkconfig -o /boot/grub/grub.cfg

    echo "os-prober disabled. GRUB will not detect other operating systems."
}

function set_system_clock_dual_boot_windows() {
    local rtc_setting=$(timedatectl | grep "RTC in local TZ" | awk '{print $NF}')
    if [[ "$rtc_setting" == "yes" ]]; then
        echo "System clock is already set to localtime for dual booting Windows."
    else
        echo "Setting system clock for dual booting Windows..."
        echo "This will set the hardware clock to localtime."

        # Set hardware clock to localtime
        sudo timedatectl set-local-rtc 1 --adjust-system-clock

        # Confirm
        timedatectl

        echo "System clock set to localtime. This should help with dual booting Windows."
    fi
}

function install_paru() {
    if command -v paru >/dev/null 2>&1; then
        echo "Paru is already installed."
    else
        echo "Installing paru..."
        # Install prerequisites
        sudo pacman -S --noconfirm base-devel git

        # Clone the paru repo
        git clone https://aur.archlinux.org/paru.git

        # Build and install paru
        cd paru
        makepkg -si --noconfirm

        # Clean up
        cd ..
        rm -rf paru

        echo "Paru installed."
    fi
}

function install_yay() {
    if command -v yay >/dev/null 2>&1; then
        echo "Yay is already installed."
    else
        echo "Installing yay..."
        # Install prerequisites
        sudo pacman -S --noconfirm base-devel git

        # Clone the yay repo
        git clone https://aur.archlinux.org/yay.git

        # Build and install yay
        cd yay
        makepkg -si --noconfirm

        # Clean up
        cd ..
        rm -rf yay

        echo "Yay installed."
    fi
}

function install_xorg_apps() {
    echo "Installing Xorg apps..."

    # Define an array of available Xorg apps
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

    # Display the apps with numbers
    echo "Available Xorg apps:"
    i=1
    for app in "${XORG_APPS[@]}"; do
        echo "$i) $app"
        ((i++))
    done

    echo ""
    echo "Enter the numbers of the apps you want to install, separated by spaces (e.g., 1 2 5):"
    read -p "> " APP_SELECTION

    # Convert the selection into an array
    read -a SELECTED_NUMBERS <<< "$APP_SELECTION"

    # Build the list of selected apps
    SELECTED_APPS=()
    for num in "${SELECTED_NUMBERS[@]}"; do
        if [[ "$num" -gt 0 && "$num" -le "${#XORG_APPS[@]}" ]]; then
            SELECTED_APPS+=("${XORG_APPS[$num-1]}")
        else
            echo "Invalid selection: $num"
        fi
    done

    # Install the selected apps
    if [ "${#SELECTED_APPS[@]}" -gt 0 ]; then
        echo "Installing selected Xorg apps..."
        sudo pacman -S --noconfirm "${SELECTED_APPS[@]}"
        echo "Selected Xorg apps installed."
    else
        echo "No valid apps selected."
    fi
}

function create_user_directories() {
    echo "Creating user directories like ~/Desktop and ~/Music..."
    # Install xdg-user-dirs
    sudo pacman -S --noconfirm xdg-user-dirs

    xdg-user-dirs-update

    echo "Directories were successfully created."
}

function git_clone_suckless() {
    echo "Cloning dwm, dmenu, and st from suckless..."

    declare -A SUCKLESS_REPOS=(
        ["dwm"]="https://git.suckless.org/dwm"
        ["dmenu"]="https://git.suckless.org/dmenu"
        ["st"]="https://git.suckless.org/st"
    )

    for repo in "${!SUCKLESS_REPOS[@]}"; do
        read -p "Enter the directory where you want to clone $repo (default is ~/$repo): " TARGET_DIR
        TARGET_DIR=${TARGET_DIR:-~/$repo}
        # Expand tilde in path
        TARGET_DIR=$(eval echo "$TARGET_DIR")
        # Create directory if it doesn't exist
        mkdir -p "$TARGET_DIR"
        # Clone the repo
        git clone "${SUCKLESS_REPOS[$repo]}" "$TARGET_DIR"
        echo "$repo cloned into $TARGET_DIR"
    done
}

function boot_into_uefi() {
    echo "Rebooting into UEFI firmware settings..."
    sleep 5
    sudo systemctl reboot --firmware-setup
}

function exit_script() {
    echo "Exiting."
    exit 0
}

# Main loop
while true; do
    echo ""
    echo "Please choose an option:"
    i=1
    for option in "${OPTIONS[@]}"; do
        echo "$i) $option"
        ((i++))
    done
    echo ""
    read -p "Enter your choice [1-${#OPTIONS[@]}]: " CHOICE

    case "$CHOICE" in
        1) enable_grub_verbose_logging ;;
        2) disable_grub_verbose_logging ;;
        3) setup_secure_boot ;;
        4) enable_os_prober ;;
        5) disable_os_prober ;;
        6) set_system_clock_dual_boot_windows ;;
        7) install_paru ;;
        8) install_yay ;;
        9) install_xorg_apps ;;
        10) create_user_directories ;;
        11) git_clone_suckless ;;
        12) boot_into_uefi ;;
        13) exit_script ;;
        *)
            echo "Invalid choice. Please try again."
            ;;
    esac
done
