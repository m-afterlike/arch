#!/bin/bash

# ============================================
# BASE FUNCTIONS
# ============================================

print_ascii_art() {
    clear
    cat <<"EOF"

 █████╗ ██████╗  ██████╗██╗  ██╗██╗███╗   ██╗███████╗████████╗ █████╗ ██╗     ██╗     
██╔══██╗██╔══██╗██╔════╝██║  ██║██║████╗  ██║██╔════╝╚══██╔══╝██╔══██╗██║     ██║     
███████║██████╔╝██║     ███████║██║██╔██╗ ██║███████╗   ██║   ███████║██║     ██║     
██╔══██║██╔══██╗██║     ██╔══██║██║██║╚██╗██║╚════██║   ██║   ██╔══██║██║     ██║     
██║  ██║██║  ██║╚██████╗██║  ██║██║██║ ╚████║███████║   ██║   ██║  ██║███████╗███████╗
╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝╚═╝╚═╝  ╚═══╝╚══════╝   ╚═╝   ╚═╝  ╚═╝╚══════╝╚══════╝
                                                                                      
EOF
}

if [ ! -f /usr/bin/pacstrap ]; then
    print_ascii_art
    echo "This script must be run from an Arch Linux ISO environment."
    exit 1
fi

install_packages() {
    for pkg in "$@"; do
        pacman -S --needed --noconfirm "$pkg" || echo "Failed to install package $pkg, continuing..."
    done
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

# Modified select_option for multiple selections
select_multiple_options() {
    local options=("$@")
    local num_options=${#options[@]}
    local selected=0
    local last_selected=-1
    local selections=()

    # Initialize selections array
    for ((i=0; i<num_options; i++)); do
        selections[$i]=false
    done

    while true; do
        if [ $last_selected -ne -1 ]; then
            echo -ne "\033[${num_options}A"
        fi

        if [ $last_selected -eq -1 ]; then
            echo "Please select options using the arrow keys and Space to toggle selection. Press Enter when done:"
        fi
        for i in "${!options[@]}"; do
            if [ "${selections[$i]}" = true ]; then
                prefix="[x]"
            else
                prefix="[ ]"
            fi
            if [ "$i" -eq $selected ]; then
                echo -e "\e[7m ▶ $prefix ${options[$i]} \e[0m"
            else
                echo "   $prefix ${options[$i]} "
            fi
        done

        last_selected=$selected

        read -rsn1 key
        case $key in
        ' ')
            selections[$selected]=$(! ${selections[$selected]})
            ;;
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

    SELECTED_OPTIONS=()
    for i in "${!options[@]}"; do
        if [ "${selections[$i]}" = true ]; then
            SELECTED_OPTIONS+=("${options[$i]}")
        fi
    done
}

# ============================================
# MENUS
# ============================================

main_menu() {
    print_ascii_art
    options=(
        "Install Arch Linux"
        "Exit"
    )
    select_option "${options[@]}"
    selected=$?
    case $selected in
    0) dual_boot_menu ;; # Install Arch Linux
    1) clear && exit 0 ;;     # Exit
    esac
}

dual_boot_menu() {
    print_ascii_art
    echo "Are you planning to dual boot?"
    options=("Yes" "No" "Back")
    select_option "${options[@]}"
    selected=$?
    case $selected in
    0)
        DUAL_BOOT="yes"
        disk_selection_menu
        ;;
    1)
        DUAL_BOOT="no"
        disk_selection_menu
        ;;
    2) main_menu ;;
    esac
}

disk_selection_menu() {
    print_ascii_art
    echo "Available Disks:"
    mapfile -t disks < <(lsblk -dpno NAME,SIZE | grep -E "/dev/sd|/dev/nvme|/dev/vd")
    disks+=("Back")
    select_option "${disks[@]}"
    selected=$?
    if [ "${disks[$selected]}" == "Back" ]; then
        dual_boot_menu
    else
        DISK=$(echo "${disks[$selected]}" | awk '{print $1}')
        confirm_disk
    fi
}

confirm_disk() {
    print_ascii_art
    echo "WARNING: This will erase all data on $DISK"
    echo "Are you sure you want to continue?"
    options=("Yes" "No")
    select_option "${options[@]}"
    selected=$?
    case $selected in
    0) filesystem_menu ;;     # Yes
    1) disk_selection_menu ;; # No
    esac
}

filesystem_menu() {
    print_ascii_art
    echo "Choose a filesystem:"
    options=("ext4" "btrfs" "Back")
    select_option "${options[@]}"
    selected=$?
    case $selected in
    0)
        FS="ext4"
        swap_size_menu
        ;;
    1)
        FS="btrfs"
        btrfs_subvolume_menu
        ;;
    2) disk_selection_menu ;;
    esac
}

btrfs_subvolume_menu() {
    print_ascii_art
    echo "Select BTRFS subvolumes to create:"
    options=("@home for /home" "@tmp for /tmp" "@snapshots for /.snapshots" "@var for /var")
    select_multiple_options "${options[@]}"
    SELECTED_SUBVOLUMES=("${SELECTED_OPTIONS[@]}")
    swap_size_menu
}

swap_size_menu() {
    print_ascii_art
    RAM_SIZE=$(grep MemTotal /proc/meminfo | awk '{print int($2/1024/1024)+1}')
    echo "Detected RAM size: ${RAM_SIZE}GB"
    echo "Recommended swap size is equal to RAM size."
    echo "Do you want to use ${RAM_SIZE}GB for swap?"
    options=("Yes" "No")
    select_option "${options[@]}"
    selected=$?
    case $selected in
    0)
        SWAP_SIZE="${RAM_SIZE}G"
        timezone_menu
        ;;
    1)
        echo "Enter desired swap size in GB (e.g., 4G):"
        read -r SWAP_SIZE
        timezone_menu
        ;;
    esac
}

timezone_menu() {
    print_ascii_art
    time_zone="$(curl --fail https://ipapi.co/timezone 2>/dev/null)"
    if [ -z "$time_zone" ]; then
        echo "Unable to detect timezone."
        echo "Please enter your desired timezone (e.g., America/New_York):"
        read -r TIMEZONE
    else
        echo "System detected your timezone to be '$time_zone'"
        echo "Is this correct?"
        options=("Yes" "No")
        select_option "${options[@]}"
        selected=$?
        case $selected in
        0)
            TIMEZONE=$time_zone
            ;;
        1)
            echo "Please enter your desired timezone (e.g., America/New_York):"
            read -r TIMEZONE
            ;;
        esac
    fi
    userinfo_menu
}

userinfo_menu() {
    print_ascii_art
    # Loop through user input until the user gives a valid username
    while true; do
        read -r -p "Please enter username: " USERNAME
        if [[ "${USERNAME,,}" =~ ^[a-z_]([a-z0-9_-]{0,31}|[a-z0-9_-]{0,30}\$)$ ]]; then
            break
        fi
        echo "Incorrect username."
    done

    while true; do
        read -rs -p "Please enter password: " PASSWORD1
        echo -ne "\n"
        read -rs -p "Please re-enter password: " PASSWORD2
        echo -ne "\n"
        if [[ "$PASSWORD1" == "$PASSWORD2" ]]; then
            PASSWORD=$PASSWORD1
            break
        else
            echo -ne "ERROR! Passwords do not match. \n"
        fi
    done

    # Loop through user input until the user gives a valid hostname, but allow the user to force save
    while true; do
        read -r -p "Please name your machine: " HOSTNAME
        if [[ "${HOSTNAME,,}" =~ ^[a-z][a-z0-9_.-]{0,62}[a-z0-9]$ ]]; then
            break
        fi
        # if validation fails allow the user to force saving of the hostname
        read -r -p "Hostname doesn't seem correct. Do you still want to save it? (y/n): " force
        if [[ "${force,,}" = "y" ]]; then
            break
        fi
    done
    additional_options_menu
}

additional_options_menu() {
    print_ascii_art
    echo "Select additional options:"
    options=("Install graphics drivers" "Enable verbose logging in GRUB" "Set up OpenSSH" "Install NetworkManager")
    select_multiple_options "${options[@]}"
    INSTALL_GRAPHICS_DRIVERS="no"
    ENABLE_LOGGING="no"
    INSTALL_OPENSSH="no"
    INSTALL_NETWORKMANAGER="no"
    for opt in "${SELECTED_OPTIONS[@]}"; do
        case $opt in
        "Install graphics drivers")
            INSTALL_GRAPHICS_DRIVERS="yes"
            ;;
        "Enable verbose logging in GRUB")
            ENABLE_LOGGING="yes"
            ;;
        "Set up OpenSSH")
            INSTALL_OPENSSH="yes"
            ;;
        "Install NetworkManager")
            INSTALL_NETWORKMANAGER="yes"
            ;;
        esac
    done
    secure_boot_menu
}

secure_boot_menu() {
    print_ascii_art
    echo "Will you be setting up Secure Boot?"
    options=("Yes" "No")
    select_option "${options[@]}"
    selected=$?
    case $selected in
    0)
        SECURE_BOOT="yes"
        ;;
    1)
        SECURE_BOOT="no"
        ;;
    esac
    confirm_settings
}

confirm_settings() {
    print_ascii_art
    echo "Please review your settings:"
    echo "-----------------------------------------------"
    echo "Disk: $DISK"
    echo "Dual Boot: $DUAL_BOOT"
    echo "Filesystem: $FS"
    if [ "$FS" == "btrfs" ]; then
        echo "BTRFS Subvolumes: ${SELECTED_SUBVOLUMES[*]}"
    fi
    echo "Swap Size: $SWAP_SIZE"
    echo "Timezone: $TIMEZONE"
    echo "Username: $USERNAME"
    echo "Hostname: $HOSTNAME"
    echo "Install graphics drivers: $INSTALL_GRAPHICS_DRIVERS"
    echo "Enable verbose logging in GRUB: $ENABLE_LOGGING"
    echo "Set up OpenSSH: $INSTALL_OPENSSH"
    echo "Install NetworkManager: $INSTALL_NETWORKMANAGER"
    echo "Secure Boot: $SECURE_BOOT"
    echo "-----------------------------------------------"
    echo "Are these settings correct?"
    options=("Yes" "No")
    select_option "${options[@]}"
    selected=$?
    case $selected in
    0)
        start_installation
        ;;
    1)
        main_menu
        ;;
    esac
}

start_installation() {
    print_ascii_art
    echo "Starting installation..."
    sleep 2

    # Update system clock
    timedatectl set-ntp true

    # Refresh pacman keys
    pacman -Sy --noconfirm
    pacman -S --noconfirm archlinux-keyring

    # Unmount any mounted partitions on /mnt
    umount -A --recursive /mnt || true

    # Partition the disk
    if [ "$DUAL_BOOT" == "no" ]; then
        # Create new GPT partition table
        parted -s "$DISK" mklabel gpt

        # Create partitions
        parted -s "$DISK" mkpart primary fat32 1MiB 512MiB
        parted -s "$DISK" set 1 esp on
        parted -s "$DISK" mkpart primary linux-swap 512MiB "$((512 + ${SWAP_SIZE%G} * 1024))"MiB
        parted -s "$DISK" mkpart primary ext4 "$((512 + ${SWAP_SIZE%G} * 1024))"MiB 100%

        # Get partition names
        EFI_PARTITION="${DISK}1"
        SWAP_PARTITION="${DISK}2"
        ROOT_PARTITION="${DISK}3"

        # Format partitions
        mkfs.fat -F32 "$EFI_PARTITION"
    else
        # For dual booting, find existing EFI partition
        EFI_PARTITION=$(lsblk -lp | grep -Ei "efi|boot" | grep "part" | awk '{print $1}' | head -n 1)
        if [ -z "$EFI_PARTITION" ]; then
            echo "EFI partition not found."
            echo "Available partitions:"
            lsblk -p -o NAME,SIZE,FSTYPE,MOUNTPOINT
            echo "Please enter the EFI partition (e.g., '/dev/nvme0n1p1'):"
            read -r EFI_PARTITION
        fi

        # Create partitions
        parted -s "$DISK" mkpart primary linux-swap 1MiB "${SWAP_SIZE}"
        parted -s "$DISK" mkpart primary ext4 "${SWAP_SIZE}" 100%

        # Get partition names
        SWAP_PARTITION="${DISK}1"
        ROOT_PARTITION="${DISK}2"
    fi

    # Set up swap
    mkswap "$SWAP_PARTITION"
    swapon "$SWAP_PARTITION"

    # Format and mount root partition
    if [ "$FS" == "btrfs" ]; then
        mkfs.btrfs -f "$ROOT_PARTITION"
        mount "$ROOT_PARTITION" /mnt
        btrfs subvolume create /mnt/@
        for subvol in "${SELECTED_SUBVOLUMES[@]}"; do
            subvol_name=$(echo "$subvol" | awk '{print $1}')
            btrfs subvolume create "/mnt/$subvol_name"
        done
        umount /mnt
        mount -o subvol=@ "$ROOT_PARTITION" /mnt
        for subvol in "${SELECTED_SUBVOLUMES[@]}"; do
            subvol_name=$(echo "$subvol" | awk '{print $1}')
            mount_point=$(echo "$subvol" | awk '{print $3}')
            mkdir -p "/mnt$mount_point"
            mount -o subvol="$subvol_name" "$ROOT_PARTITION" "/mnt$mount_point"
        done
    else
        mkfs.ext4 "$ROOT_PARTITION"
        mount "$ROOT_PARTITION" /mnt
    fi

    # Mount EFI partition
    mkdir -p /mnt/boot
    mount "$EFI_PARTITION" /mnt/boot

    # Install base system
    pacstrap /mnt base linux linux-firmware

    # Install microcode
    if grep -q "GenuineIntel" /proc/cpuinfo; then
        echo "Installing Intel microcode"
        arch-chroot /mnt pacman -S --noconfirm --needed intel-ucode
    elif grep -q "AuthenticAMD" /proc/cpuinfo; then
        echo "Installing AMD microcode"
        arch-chroot /mnt pacman -S --noconfirm --needed amd-ucode
    else
        echo "Unable to determine CPU vendor. Skipping microcode installation."
    fi

    # Generate fstab
    genfstab -U /mnt >> /mnt/etc/fstab

    # Copy variables to chroot environment
    cat <<EOT >> /mnt/root/install.conf
TIMEZONE='$TIMEZONE'
HOSTNAME='$HOSTNAME'
USERNAME='$USERNAME'
PASSWORD='$PASSWORD'
INSTALL_GRAPHICS_DRIVERS='$INSTALL_GRAPHICS_DRIVERS'
ENABLE_LOGGING='$ENABLE_LOGGING'
INSTALL_OPENSSH='$INSTALL_OPENSSH'
INSTALL_NETWORKMANAGER='$INSTALL_NETWORKMANAGER'
SECURE_BOOT='$SECURE_BOOT'
EOT

    # Function to perform tasks inside chroot
    configure_system() {
        source /root/install.conf

        # Set timezone
        ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
        hwclock --systohc

        # Generate locales
        echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
        locale-gen
        echo "LANG=en_US.UTF-8" > /etc/locale.conf

        # Set hostname
        echo "$HOSTNAME" > /etc/hostname
        cat <<EOF > /etc/hosts
127.0.0.1       localhost
::1             localhost
127.0.1.1       $HOSTNAME.localdomain    $HOSTNAME
EOF

        # Set root password
        echo "root:$PASSWORD" | chpasswd

        # Initialize packages to install
        PACKAGES="sudo grub efibootmgr linux-headers dkms"

        # Install NetworkManager if selected
        if [ "$INSTALL_NETWORKMANAGER" == "yes" ]; then
            PACKAGES="$PACKAGES networkmanager"
            systemctl enable NetworkManager
        fi

        # Install OpenSSH if selected
        if [ "$INSTALL_OPENSSH" == "yes" ]; then
            PACKAGES="$PACKAGES openssh"
            systemctl enable sshd
        fi

        # Install graphics drivers if desired
        if [ "$INSTALL_GRAPHICS_DRIVERS" == "yes" ]; then
            gpu_type=$(lspci)
            if echo "${gpu_type}" | grep -E "NVIDIA|GeForce"; then
                PACKAGES="$PACKAGES nvidia-dkms nvidia-utils"
                # Update mkinitcpio.conf
                sed -i 's/^MODULES=.*/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
            elif echo "${gpu_type}" | grep 'VGA' | grep -E "Radeon|AMD"; then
                PACKAGES="$PACKAGES xf86-video-amdgpu"
            elif echo "${gpu_type}" | grep -E "Integrated Graphics Controller|Intel Corporation UHD"; then
                PACKAGES="$PACKAGES libva-intel-driver libvdpau-va-gl lib32-vulkan-intel vulkan-intel libva-utils lib32-mesa"
            else
                echo "No compatible GPU detected. Skipping graphics drivers installation."
            fi
        fi

        # Install packages
        install_packages $PACKAGES

        # Generate initramfs
        mkinitcpio -P

        # Install GRUB
        if [ "$SECURE_BOOT" == "yes" ]; then
            grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB --modules="tpm" --disable-shim-lock
        else
            grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
        fi

        # Modify GRUB for verbose logging if desired
        if [ "$ENABLE_LOGGING" == "yes" ]; then
            sed -i '/^GRUB_CMDLINE_LINUX_DEFAULT=/ s/"$/ debug"/' /etc/default/grub
        fi

        # Generate GRUB configuration
        grub-mkconfig -o /boot/grub/grub.cfg

        # Create new user and add to wheel group
        useradd -m -G wheel -s /bin/bash "$USERNAME"
        echo "$USERNAME:$PASSWORD" | chpasswd

        # Grant sudo privileges to wheel group
        echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/10-wheel
        chmod 440 /etc/sudoers.d/10-wheel
    }

    # Copy functions to chroot environment
    declare -f install_packages > /mnt/root/functions.sh
    declare -f configure_system >> /mnt/root/functions.sh

    # Chroot into the new system and run configuration
    arch-chroot /mnt /bin/bash -c "
    source /root/functions.sh
    configure_system
    rm /root/install.conf /root/functions.sh
    "

    # Unmount and reboot
    print_ascii_art
    echo "Installation complete!"
    echo ""
    echo "Please remove the installation media (USB) before rebooting."
    echo ""
    echo "What would you like to do now?"
    options=("Reboot Now" "Cancel")
    select_option "${options[@]}"
    selected=$?
    case $selected in
    0)
        echo "Rebooting now..."
        sleep 5
        umount -R /mnt
        reboot
        ;;
    1)
        echo "Reboot cancelled. You can now perform additional tasks or reboot manually when ready."
        ;;
    esac
}

main_menu