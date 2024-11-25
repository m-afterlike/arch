#!/bin/bash

# ============================================
# BASE FUNCTIONS
# ============================================

print_ascii_art() {
    clear
    cat <<"EOF"

██╗   ██╗████████╗██╗██╗     ██████╗  ██████╗ ██╗  ██╗
██║   ██║╚══██╔══╝██║██║     ██╔══██╗██╔═══██╗╚██╗██╔╝
██║   ██║   ██║   ██║██║     ██████╔╝██║   ██║ ╚███╔╝ 
██║   ██║   ██║   ██║██║     ██╔══██╗██║   ██║ ██╔██╗ 
╚██████╔╝   ██║   ██║███████╗██████╔╝╚██████╔╝██╔╝ ██╗
 ╚═════╝    ╚═╝   ╚═╝╚══════╝╚═════╝  ╚═════╝ ╚═╝  ╚═╝
                                                        

EOF
}

install_packages() {
    sudo pacman -Sy --noconfirm --needed "$@" || echo "Failed to install packages: $@"
}

select_option() {
    local options=("$@")
    local num_options=${#options[@]}
    local selected=0
    local last_selected=-1

    while true; do
        if [ $last_selected -ne -1 ]; then
            echo -ne "\033[${num_options}A"
        fi

        if [ $last_selected -eq -1 ]; then
            echo "Please select an option using the arrow keys and Enter:"
        fi
        for i in "${!options[@]}"; do
            if [ "$i" -eq $selected ]; then
                echo -e "\e[7m ▶ ${options[$i]} \e[0m"
            else
                echo "   ${options[$i]} "
            fi
        done

        last_selected=$selected

        read -rsn1 key < /dev/tty
        case $key in
        $'\x1b')
            read -rsn2 -t 0.1 key < /dev/tty
            case $key in
            '[A')
                ((selected--))
                [ $selected -lt 0 ] && selected=$((num_options - 1))
                ;;
            '[B')
                ((selected++))
                [ $selected -ge $num_options ] && selected=0
                ;;
            esac
            ;;
        '') break ;;
        esac
    done

    return $selected
}

select_multiple_options() {
    local options=("$@")
    options+=("Continue")  # Add "Continue" option at the end
    local num_options=${#options[@]}
    local selected=0
    local last_selected=-1
    declare -A selections  # Use an associative array for selections

    # Initialize selections array
    for ((i=0; i<num_options-1; i++)); do  # Exclude "Continue" from selections
        selections[$i]=true  # Default to all selected
    done

    while true; do
        # Clear the screen and redraw the menu
        clear
        print_ascii_art
        echo "Select files to sign:"
        echo "Use arrow keys to navigate, Enter to select/deselect, and choose 'Continue' when done."

        # Render the options
        for i in "${!options[@]}"; do
            if [ "$i" -lt $((num_options-1)) ]; then  # Regular options
                if [ "${selections[$i]}" == true ]; then
                    prefix="[x]"
                else
                    prefix="[ ]"
                fi
            else  # "Continue" option
                prefix="   "
            fi

            if [ "$i" -eq $selected ]; then
                echo -e "\e[7m ▶ $prefix ${options[$i]} \e[0m"
            else
                echo "   $prefix ${options[$i]} "
            fi
        done

        last_selected=$selected

        # Read a single keypress
        read -rsn1 key < /dev/tty

        # Handle keypress
        case "$key" in
        $'\x1b')  # Arrow keys
            read -rsn2 -t 0.1 key < /dev/tty
            case "$key" in
            '[A')  # Up arrow
                ((selected--))
                [ $selected -lt 0 ] && selected=$((num_options - 1))
                ;;
            '[B')  # Down arrow
                ((selected++))
                [ $selected -ge $num_options ] && selected=0
                ;;
            esac
            ;;
        '')  # Enter key
            if [ "$selected" -eq $((num_options - 1)) ]; then
                # "Continue" selected
                break
            elif [ "${options[$selected]}" == "Add Custom File" ]; then
                echo "Enter the full path of the custom file to sign:"
                read -r custom_file < /dev/tty
                if [ -f "$custom_file" ]; then
                    options=("${options[@]:0:${#options[@]}-2}" "$custom_file" "${options[@]: -2}")
                    selections[$((num_options-1))]=true
                    ((num_options++))
                else
                    error_message "File not found: $custom_file"
                fi
            else
                # Toggle selection
                if [ "${selections[$selected]}" == true ]; then
                    selections[$selected]=false
                else
                    selections[$selected]=true
                fi
            fi
            ;;
        esac
    done

    # Gather selected options
    SELECTED_FILES=()
    for ((i=0; i<num_options-1; i++)); do
        if [ "${selections[$i]}" == true ]; then
            SELECTED_FILES+=("${options[$i]}")
        fi
    done
}

run_with_status() {
    local task_name="$1"
    shift
    local command="$@"

    clear
    print_ascii_art

    # Execute the command and capture the status
    echo "Running: $task_name..."
    if eval "$command"; then
        echo -e "\n\e[32m✔ $task_name succeeded.\e[0m"
        return 0
    else
        echo -e "\n\e[31m✖ $task_name failed. Please check for errors.\e[0m"
        return 1
    fi
}

error_message() {
    echo -e "ERROR: $1"
    sleep 2
}

# ============================================
# APPLICATIONS SETUP FUNCTIONS
# ============================================

install_kitty() {
    run_with_status "Installing Kitty" "install_packages kitty"
    read -p "Press Enter to return to the main menu..." </dev/tty
    main_menu
}

install_rofi() {
    run_with_status "Installing Rofi" "install_packages rofi"
    read -p "Press Enter to return to the main menu..." </dev/tty
    main_menu
}

install_yay() {
    sudo -v
    run_with_status "Installing Yay AUR Helper" "
        install_packages base-devel git &&
        cd \$HOME &&
        git clone https://aur.archlinux.org/yay.git &&
        cd yay &&
        makepkg --noconfirm -si &&
        cd ../ &&
        rm -rf yay
    "
    read -p "Press Enter to return to the main menu..." </dev/tty
    main_menu
}

install_paru() {
    sudo -v
    run_with_status "Installing Paru AUR Helper" "
        install_packages base-devel git &&
        cd \$HOME &&
        git clone https://aur.archlinux.org/paru.git &&
        cd paru &&
        makepkg --noconfirm -si &&
        cd ../ &&
        rm -rf paru
    "
    read -p "Press Enter to return to the main menu..." </dev/tty
    main_menu
}

install_oh_my_zsh() {
    sudo -v
    clear
    print_ascii_art
    echo "Installing Oh My Zsh..."

    if ! run_with_status "Installing Zsh" "install_packages zsh"; then
        read -p "Press Enter to return to the main menu..." </dev/tty
        main_menu
        return
    fi

    echo "Changing default shell to Zsh for current user..."
    if ! run_with_status "Changing default shell" "sudo chsh -s $(which zsh) $USER"; then
        error_message "Failed to change default shell."
        read -p "Press Enter to return to the main menu..." </dev/tty
        main_menu
        return
    fi

    echo "Installing Oh My Zsh..."
    if ! run_with_status "Installing Oh My Zsh" 'sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"'; then
        error_message "Failed to install Oh My Zsh."
        read -p "Press Enter to return to the main menu..." </dev/tty
        main_menu
        return
    fi

    echo -e "\n\e[32m✔ Oh My Zsh installation completed.\e[0m"
    read -p "Press Enter to return to the main menu..." </dev/tty
    main_menu
}

# ============================================
# SYSTEM SETUP FUNCTIONS
# ============================================

setup_secure_boot() {
    sudo -v
    clear
    print_ascii_art
    echo "Setting up Secure Boot..."

    # Regenerate GRUB EFI binary
    if ! run_with_status "Regenerating GRUB EFI binary" "
        sudo grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB --modules=\"tpm\" --disable-shim-lock
    "; then
        read -p "Press Enter to return to the main menu..." </dev/tty
        main_menu
        return
    fi

    # Install sbctl
    if ! run_with_status "Installing sbctl" "install_packages sbctl"; then
        read -p "Press Enter to return to the main menu..." </dev/tty
        main_menu
        return
    fi

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
        echo "Do you want to proceed anyway?"
        options=("Yes" "No")
        select_option "${options[@]}"
        selected=$?
        if [[ $selected -ne 0 ]]; then
            echo "Exiting Secure Boot setup."
            read -p "Press Enter to return to the main menu..." </dev/tty
            main_menu
            return
        fi
    fi

    # Create custom secure boot keys
    if ! run_with_status "Creating custom Secure Boot keys" "sudo sbctl create-keys"; then
        read -p "Press Enter to return to the main menu..." </dev/tty
        main_menu
        return
    fi

    # Enroll keys including Microsoft keys
    if ! run_with_status "Enrolling keys (including Microsoft keys)" "sudo sbctl enroll-keys -m"; then
        read -p "Press Enter to return to the main menu..." </dev/tty
        main_menu
        return
    fi

    # Detect EFI files to sign
    mapfile -t EFI_FILES < <(sudo find /boot -type f -name "*.efi" ! -path "*/Microsoft/*")

    # Detect kernel images
    KERNEL_IMAGES=($(sudo find /boot -type f -name "vmlinuz-linux*" -o -name "vmlinuz-linux-lts" -o -name "vmlinuz-linux-hardened" -o -name "vmlinuz-linux-zen"))

    # Combine files to sign
    FILES_TO_SIGN=("${EFI_FILES[@]}" "${KERNEL_IMAGES[@]}" "Add Custom File")

    # Remove empty entries
    FILES_TO_SIGN=("${FILES_TO_SIGN[@]}")

    # Allow user to select files to sign
    select_multiple_options "${FILES_TO_SIGN[@]}"

    # Auto sign all files first
    if ! run_with_status "Auto-signing all EFI binaries" "sudo sbctl sign-all"; then
        read -p "Press Enter to return to the main menu..." </dev/tty
        main_menu
        return
    fi

    # Manually sign selected files
    for file in "${SELECTED_FILES[@]}"; do
        if [ "$file" != "Add Custom File" ]; then
            if ! run_with_status "Signing $file" "sudo sbctl sign -s \"$file\""; then
                echo "Failed to sign $file. Continuing with next file."
            fi
        fi
    done

    # Rebuild initramfs
    if ! run_with_status "Rebuilding initramfs" "sudo mkinitcpio -P || true"; then
        echo "Continuing despite mkinitcpio exit code."
    fi

    # Regenerate GRUB configuration
    if ! run_with_status "Regenerating GRUB configuration" "sudo grub-mkconfig -o /boot/grub/grub.cfg"; then
        read -p "Press Enter to return to the main menu..." </dev/tty
        main_menu
        return
    fi

    # Completion message
    clear
    print_ascii_art
    echo "Secure Boot setup is complete."
    echo "What would you like to do now?"
    options=("Boot into UEFI Firmware Settings to enable Secure Boot" "Return to Main Menu")
    select_option "${options[@]}"
    selected=$?
    case $selected in
    0)
        reboot_to_uefi
        ;;
    1)
        main_menu
        ;;
    esac
}

create_user_directories() {
    sudo -v
    run_with_status "Creating user directories" "
        install_packages xdg-user-dirs &&
        xdg-user-dirs-update
    "
    read -p "Press Enter to return to the main menu..." </dev/tty
    main_menu
}

setup_getty_autologin() {
    sudo -v
    print_ascii_art
    echo "WARNING: Setting up Getty autologin will cause your system to automatically log in the specified user on tty1."
    echo "This may log you out of the current session and exit this script."
    echo "Do you want to proceed?"
    options=("Yes" "No")
    select_option "${options[@]}"
    selected=$?
    if [ $selected -ne 0 ]; then
        main_menu
    fi

    echo "Enter the username for autologin:"
    read -r AUTOLOGIN_USER < /dev/tty

    if id -u "$AUTOLOGIN_USER" >/dev/null 2>&1; then
        sudo mkdir -p /etc/systemd/system/getty@tty1.service.d
        sudo bash -c "cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf <<EOL
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -f -- \\\\u' --noclear --autologin $AUTOLOGIN_USER %I \$TERM
EOL"
        sudo systemctl daemon-reload
        run_with_status "Enabling autologin for $AUTOLOGIN_USER" "sudo systemctl restart getty@tty1.service"
    else
        error_message "User $AUTOLOGIN_USER does not exist."
        main_menu
    fi
    read -p "Press Enter to return to the main menu..." </dev/tty
    main_menu
}

# ============================================
# UTILITIES FUNCTIONS
# ============================================

toggle_grub_os_prober() {
    sudo -v
    clear
    print_ascii_art
    GRUB_CONFIG="/etc/default/grub"
    if grep -q "^GRUB_DISABLE_OS_PROBER=false" "$GRUB_CONFIG"; then
        echo "os-prober is currently ENABLED."
        echo "Would you like to DISABLE it?"
        options=("Yes" "No")
        select_option "${options[@]}"
        selected=$?
        if [[ $selected -eq 0 ]]; then
            sudo sed -i 's/^GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=true/' "$GRUB_CONFIG"
            run_with_status "Disabling os-prober" "sudo grub-mkconfig -o /boot/grub/grub.cfg"
        else
            main_menu
        fi
    else
        echo "os-prober is currently DISABLED."
        echo "Would you like to ENABLE it?"
        options=("Yes" "No")
        select_option "${options[@]}"
        selected=$?
        if [[ $selected -eq 0 ]]; then
            sudo sed -i 's/^GRUB_DISABLE_OS_PROBER=true/GRUB_DISABLE_OS_PROBER=false/' "$GRUB_CONFIG"
            run_with_status "Enabling os-prober" "sudo grub-mkconfig -o /boot/grub/grub.cfg"
        else
            main_menu
        fi
    fi
    read -p "Press Enter to return to the main menu..." </dev/tty
    main_menu
}

toggle_grub_verbose_logging() {
    sudo -v
    clear
    print_ascii_art
    GRUB_CONFIG="/etc/default/grub"
    if grep -q '^GRUB_CMDLINE_LINUX_DEFAULT=".*debug.*"' "$GRUB_CONFIG"; then
        echo "GRUB verbose logging is currently ENABLED."
        echo "Would you like to DISABLE it?"
        options=("Yes" "No")
        select_option "${options[@]}"
        selected=$?
        if [[ $selected -eq 0 ]]; then
            sudo sed -i 's/\(GRUB_CMDLINE_LINUX_DEFAULT="[^"]*\) debug\(.*"\)/\1\2/' "$GRUB_CONFIG"
            run_with_status "Disabling GRUB verbose logging" "sudo grub-mkconfig -o /boot/grub/grub.cfg"
        else
            main_menu
        fi
    else
        echo "GRUB verbose logging is currently DISABLED."
        echo "Would you like to ENABLE it?"
        options=("Yes" "No")
        select_option "${options[@]}"
        selected=$?
        if [[ $selected -eq 0 ]]; then
            sudo sed -i 's/^\(GRUB_CMDLINE_LINUX_DEFAULT="[^"]*\)"/\1 debug"/' "$GRUB_CONFIG"
            run_with_status "Enabling GRUB verbose logging" "sudo grub-mkconfig -o /boot/grub/grub.cfg"
        else
            main_menu
        fi
    fi
    read -p "Press Enter to return to the main menu..." </dev/tty
    main_menu
}

disable_mouse_acceleration() {
    sudo -v
    clear
    print_ascii_art
    echo "Disabling mouse acceleration..."
    echo "The following file will be created:"
    echo "/etc/X11/xorg.conf.d/40-libinput.conf"
    echo ""
    echo "File content:"
    echo 'Section "InputClass"
    Identifier "libinput pointer catchall"
    MatchIsPointer "on"
    MatchDevicePath "/dev/input/event*"
    Driver "libinput"
    Option "AccelProfile" "flat"
EndSection'
    echo ""
    echo "Do you want to proceed?"
    options=("Yes" "No")
    select_option "${options[@]}"
    selected=$?
    if [[ $selected -eq 0 ]]; then
        run_with_status "Disabling mouse acceleration" "
            sudo mkdir -p /etc/X11/xorg.conf.d &&
            sudo bash -c 'cat > /etc/X11/xorg.conf.d/40-libinput.conf <<EOL
Section \"InputClass\"
    Identifier \"libinput pointer catchall\"
    MatchIsPointer \"on\"
    MatchDevicePath \"/dev/input/event*\"
    Driver \"libinput\"
    Option \"AccelProfile\" \"flat\"
EndSection
EOL'
        "
    else
        main_menu
    fi
    read -p "Press Enter to return to the main menu..." </dev/tty
    main_menu
}

reboot_to_uefi() {
    sudo -v
    run_with_status "Rebooting into UEFI Firmware Settings" "
        echo \"Rebooting in 3 seconds...\" && sleep 1 &&
        echo \"Rebooting in 2 seconds...\" && sleep 1 &&
        echo \"Rebooting in 1 second...\" && sleep 1 &&
        sudo systemctl reboot --firmware-setup
    "
}

# ============================================
# MENUS
# ============================================

main_menu() {
    print_ascii_art
    echo "Select a category:"
    options=(
        "Applications Setup"
        "System Setup"
        "Utilities"
        "Exit"
    )
    select_option "${options[@]}"
    selected=$?
    case $selected in
    0) applications_setup_menu ;;
    1) system_setup_menu ;;
    2) utilities_menu ;;
    3) clear && exit 0 ;;
    esac
}

applications_setup_menu() {
    print_ascii_art
    echo "Applications Setup:"
    options=(
        "Install Kitty"
        "Install Rofi"
        "Install Yay AUR Helper"
        "Install Paru AUR Helper"
        "Install Oh My Zsh"
        "Back"
    )
    select_option "${options[@]}"
    selected=$?
    case $selected in
    0) install_kitty ;;
    1) install_rofi ;;
    2) install_yay ;;
    3) install_paru ;;
    4) install_oh_my_zsh ;;
    5) main_menu ;;
    esac
}

system_setup_menu() {
    print_ascii_art
    echo "System Setup:"
    options=(
        "Setup Secure Boot"
        "Create User Directories"
        "Setup Getty Autologin"
        "Back"
    )
    select_option "${options[@]}"
    selected=$?
    case $selected in
    0) setup_secure_boot ;;
    1) create_user_directories ;;
    2) setup_getty_autologin ;;
    3) main_menu ;;
    esac
}

utilities_menu() {
    print_ascii_art
    echo "Utilities:"
    options=(
        "Toggle GRUB os-prober"
        "Toggle GRUB Verbose Logging"
        "Disable Mouse Acceleration"
        "Boot into UEFI Firmware Settings"
        "Back"
    )
    select_option "${options[@]}"
    selected=$?
    case $selected in
    0) toggle_grub_os_prober ;;
    1) toggle_grub_verbose_logging ;;
    2) disable_mouse_acceleration ;;
    3) reboot_to_uefi ;;
    4) main_menu ;;
    esac
}

# ============================================
# SCRIPT ENTRY POINT
# ============================================

main_menu
