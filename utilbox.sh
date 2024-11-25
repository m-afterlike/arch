#!/bin/bash

# ============================================
# BASE FUNCTIONS
# ============================================

print_ascii_art() {
    cat <<"EOF"

██╗   ██╗████████╗██╗██╗     ██████╗  ██████╗ ██╗  ██╗
██║   ██║╚══██╔══╝██║██║     ██╔══██╗██╔═══██╗╚██╗██╔╝
██║   ██║   ██║   ██║██║     ██████╔╝██║   ██║ ╚███╔╝ 
██║   ██║   ██║   ██║██║     ██╔══██╗██║   ██║ ██╔██╗ 
╚██████╔╝   ██║   ██║███████╗██████╔╝╚██████╔╝██╔╝ ██╗
 ╚═════╝    ╚═╝   ╚═╝╚══════╝╚═════╝  ╚═════╝ ╚═╝  ╚═╝
                                                      
EOF
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

        read -rsn1 key
        case $key in
        $'\x1b')
            read -rsn2 -t 0.1 key
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
    else
        echo -e "\n\e[31m✖ $task_name failed. Please check for errors.\e[0m"
    fi

    # Pause briefly and return to the main menu
    read -p "Press Enter to return to the main menu..." </dev/tty
    main_menu
}

# ============================================
# MENUS
# ============================================

main_menu() {
    clear
    print_ascii_art
    options=(
        "Boot Utilities"
        "System Utilities"
        "Application Setup"
        "Exit"
    )
    select_option "${options[@]}"
    selected=$?
    case $selected in
    0) boot_utils_menu ;;   # Boot Utilities
    1) system_utils_menu ;; # System Utilities
    2) app_setup_menu ;;    # Application Setup
    3) clear && exit 0 ;;   # Exit
    esac
}

boot_utils_menu() {
    clear
    print_ascii_art
    options=(
        "Enable GRUB verbose logging"
        "Disable GRUB verbose logging"
        "Set up Secure Boot"
        "Enable os-prober (detect other OSes in GRUB)"
        "Disable os-prober"
        "Boot into UEFI Firmware Settings"
        "Back"
    )
    select_option "${options[@]}"
    selected=$?
    case $selected in
    0) run_with_status "Enable GRUB verbose logging" enable_grub_verbose_logging ;;
    1) run_with_status "Disable GRUB verbose logging" disable_grub_verbose_logging ;;
    2) run_with_status "Set up Secure Boot" setup_secure_boot ;;
    3) run_with_status "Enable os-prober" enable_os_prober ;;
    4) run_with_status "Disable os-prober" disable_os_prober ;;
    5) run_with_status "Boot into UEFI Firmware Settings" boot_into_uefi ;;
    6) main_menu ;;
    esac
}

app_setup_menu() {
    clear
    print_ascii_art
    options=(
        "Install Paru"
        "Install Yay"
        "Back"
    )
    select_option "${options[@]}"
    selected=$?
    case $selected in
    0) run_with_status "Install Paru" install_paru ;;
    1) run_with_status "Install Yay" install_yay ;;
    2) main_menu ;;
    esac
}

system_utils_menu() {
    clear
    print_ascii_art
    options=(
        "Create user directories like ~/Desktop and ~/Music"
        "Back"
    )
    select_option "${options[@]}"
    selected=$?
    case $selected in
    0) run_with_status "Create user directories" create_user_dirs ;;
    1) main_menu ;;
    esac
}

# ============================================
# SCRIPT FUNCTIONS
# ============================================

# BOOT UTILS
enable_grub_verbose_logging() {
    sudo -v &&
    sudo sed -i '/^GRUB_CMDLINE_LINUX_DEFAULT=/ s/"$/ debug"/' /etc/default/grub &&
    sudo grub-mkconfig -o /boot/grub/grub.cfg
}

disable_grub_verbose_logging() {
    sudo -v &&
    sudo sed -i '/^GRUB_CMDLINE_LINUX_DEFAULT=/ s/ debug"$/"/' /etc/default/grub &&
    sudo grub-mkconfig -o /boot/grub/grub.cfg
}

setup_secure_boot() {
    echo "Test"
}

enable_os_prober() {
    sudo -v &&
    sudo pacman -S --noconfirm os-prober &&
    sudo sed -i '/^GRUB_DISABLE_OS_PROBER=/d' /etc/default/grub &&
    echo "GRUB_DISABLE_OS_PROBER=false" | sudo tee -a /etc/default/grub &&
    sudo grub-mkconfig -o /boot/grub/grub.cfg
}

disable_os_prober() {
    sudo -v &&
    echo "Disabling os-prober..." &&
    sudo sed -i '/^GRUB_DISABLE_OS_PROBER=/d' /etc/default/grub &&
    echo "GRUB_DISABLE_OS_PROBER=true" | sudo tee -a /etc/default/grub &&
    sudo grub-mkconfig -o /boot/grub/grub.cfg
}

boot_into_uefi() {
    echo "Rebooting in 3 seconds..." && sleep 1 &&
    echo "Rebooting in 2 seconds..." && sleep 1 &&
    echo "Rebooting in 1 second..." && sleep 1 &&
    systemctl reboot --firmware-setup
}

# APP SETUP
install_paru() {
    sudo -v &&
    sudo pacman -S --needed --noconfirm base-devel git &&
    cd && git clone https://aur.archlinux.org/paru.git &&
    cd paru && makepkg --noconfirm -si &&
    cd ../ && rm -rf paru
}

install_yay() {
    sudo -v &&
    sudo pacman -S --needed --noconfirm base-devel git &&
    cd && git clone https://aur.archlinux.org/yay.git &&
    cd yay && makepkg --noconfirm -si &&
    cd ../ && rm -rf yay
}

# SYSTEM UTILS
create_user_dirs() {
    sudo -v &&
    sudo pacman -S --noconfirm xdg-user-dirs &&
    xdg-user-dirs-update
}

# ============================================
# SCRIPT START
# ============================================

clear
print_ascii_art
main_menu