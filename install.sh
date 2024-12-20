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
    pacman -Sy --noconfirm --needed "$@" || echo "Failed to install packages: $@"
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
        selections[$i]=false
    done

    while true; do
        # Clear the screen and redraw the menu
        if [ $last_selected -ne -1 ]; then
            echo -ne "\033[${num_options}A"
        fi

        if [ $last_selected -eq -1 ]; then
            echo "Please select options using the arrow keys and Enter to toggle selection."
            echo "Select 'Continue' when you are done:"
        fi

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
    SELECTED_OPTIONS=()
    for ((i=0; i<num_options-1; i++)); do
        if [ "${selections[$i]}" == true ]; then
            SELECTED_OPTIONS+=("${options[$i]}")
        fi
    done
}

error_message() {
    echo -e "ERROR: $1"
    sleep 2
}

detect_efi_partition() {
    lsblk -lnpo NAME,FSTYPE,PARTLABEL | while read -r line; do
        name=$(echo "$line" | awk '{print $1}')
        fstype=$(echo "$line" | awk '{print $2}')
        partlabel=$(echo "$line" | awk '{print $3}')
        if [[ "$fstype" == "vfat" ]] && [[ "$partlabel" == *"EFI"* ]]; then
            echo "$name"
            return 0
        fi
    done
    return 1
}

create_swap_partition() {
    sgdisk -n0:0:+${SWAP_SIZE} -t0:8200 -c0:"Linux Swap" "$DISK"
}

create_root_partition() {
    sgdisk -n0:0:0 -t0:8300 -c0:"Linux filesystem" "$DISK"
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
    SELECTED_SUBVOLUMES=()
    while true; do
        print_ascii_art
        echo "Selected BTRFS subvolumes:"
        if [ "${#SELECTED_SUBVOLUMES[@]}" -eq 0 ]; then
            echo "None"
        else
            for subvol in "${SELECTED_SUBVOLUMES[@]}"; do
                IFS='|' read -r subvol_name mount_point <<< "$subvol"
                echo "  $subvol_name --> $mount_point"
            done
        fi
        echo ""
        echo "Options:"
        options=("Add Default Subvolumes" "Add Custom Subvolume" "Remove Subvolume" "Done")
        select_option "${options[@]}"
        selected=$?
        case $selected in
        0) # Add Default Subvolumes
            btrfs_add_default_subvolumes
            ;;
        1) # Add Custom Subvolume
            btrfs_custom_subvolume_menu
            ;;
        2) # Remove Subvolume
            btrfs_remove_subvolume_menu
            ;;
        3) # Done
            swap_size_menu
            break
            ;;
        esac
    done
}

btrfs_add_default_subvolumes() {
    print_ascii_art
    echo "Select default BTRFS subvolumes to add:"
    default_options=("@home --> /home" "@tmp --> /tmp" "@snapshots --> /.snapshots" "@var --> /var")
    select_multiple_options "${default_options[@]}"
    for opt in "${SELECTED_OPTIONS[@]}"; do
        case $opt in
        "@home --> /home")
            SELECTED_SUBVOLUMES+=("@home|/home")
            ;;
        "@tmp --> /tmp")
            SELECTED_SUBVOLUMES+=("@tmp|/tmp")
            ;;
        "@snapshots --> /.snapshots")
            SELECTED_SUBVOLUMES+=("@snapshots|/.snapshots")
            ;;
        "@var --> /var")
            SELECTED_SUBVOLUMES+=("@var|/var")
            ;;
        esac
    done
}

btrfs_custom_subvolume_menu() {
    while true; do
        echo "Enter custom subvolume name (without '@'), or type 'done' to finish adding custom subvolumes:"
        read -r subvol_name < /dev/tty
        if [ "$subvol_name" == "done" ]; then
            break
        fi
        subvol_name_cleaned=$(echo "$subvol_name" | sed 's/[^a-zA-Z0-9_-]//g')
        subvol_name="@$subvol_name_cleaned"

        echo "Enter mount point for $subvol_name:"
        read -r mount_point < /dev/tty

        SELECTED_SUBVOLUMES+=("$subvol_name|$mount_point")
        echo "Added custom subvolume: $subvol_name --> $mount_point"
    done
}

btrfs_remove_subvolume_menu() {
    if [ "${#SELECTED_SUBVOLUMES[@]}" -eq 0 ]; then
        echo "No subvolumes to remove."
        sleep 1
        return
    fi
    print_ascii_art
    echo "Select subvolumes to remove:"
    options=()
    for subvol in "${SELECTED_SUBVOLUMES[@]}"; do
        IFS='|' read -r subvol_name mount_point <<< "${subvol}"
        options+=("$subvol_name --> $mount_point")
    done
    select_multiple_options "${options[@]}"
    for opt in "${SELECTED_OPTIONS[@]}"; do
        for i in "${!SELECTED_SUBVOLUMES[@]}"; do
            IFS='|' read -r subvol_name mount_point <<< "${SELECTED_SUBVOLUMES[$i]}"
            if [ "$opt" == "$subvol_name --> $mount_point" ]; then
                unset 'SELECTED_SUBVOLUMES[$i]'
            fi
        done
    done
    # Remove empty elements
    SELECTED_SUBVOLUMES=("${SELECTED_SUBVOLUMES[@]}")
}

swap_size_menu() {
    print_ascii_art
    RAM_SIZE=$(grep MemTotal /proc/meminfo | awk '{print int($2/1024/1024)+1}')
    echo "Detected RAM size: ${RAM_SIZE}GB"
    echo "Recommended swap size is equal to RAM size."
    echo "Do you want to use ${RAM_SIZE}G for swap?"
    options=("Yes" "No")
    select_option "${options[@]}"
    selected=$?
    case $selected in
    0)
        SWAP_SIZE="${RAM_SIZE}G"
        timezone_menu
        ;;
    1)
        echo "Enter desired swap size in GB (e.g., 4):"
        read -r SWAP_INPUT < /dev/tty
        if [[ "$SWAP_INPUT" =~ ^[0-9]+$ ]]; then
            SWAP_SIZE="${SWAP_INPUT}G"
            timezone_menu
        else
            error_message "Invalid input. Please enter a number."
            swap_size_menu
        fi
        ;;
    esac
}

timezone_menu() {
    print_ascii_art
    time_zone="$(curl --fail https://ipapi.co/timezone 2>/dev/null)"
    if [ -z "$time_zone" ]; then
        echo "Unable to detect timezone."
        echo "Please enter your desired timezone (e.g., America/New_York):"
        read -r TIMEZONE < /dev/tty
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
            read -r TIMEZONE < /dev/tty
            ;;
        esac
    fi
    userinfo_menu
}

userinfo_menu() {
    print_ascii_art
    unset USERNAME
    # Loop through user input until the user gives a valid username
    while true; do
        read -r -p "Please enter username: " USERNAME < /dev/tty
        if [[ "$USERNAME" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
            echo "Username accepted: $USERNAME"
            break
        else
            error_message "Incorrect username. Only lowercase letters, numbers, '_', and '-' are allowed, and must start with a letter."
        fi
    done

    while true; do
        read -rs -p "Please enter password: " PASSWORD1 < /dev/tty
        echo -ne "\n"
        read -rs -p "Please re-enter password: " PASSWORD2 < /dev/tty
        echo -ne "\n"
        if [[ "$PASSWORD1" == "$PASSWORD2" ]]; then
            PASSWORD=$PASSWORD1
            break
        else
            error_message "Passwords do not match."
        fi
    done

    # Loop through user input until the user gives a valid hostname
    while true; do
        read -r -p "Please name your machine (hostname): " HOSTNAME < /dev/tty
        if [[ "$HOSTNAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]]; then
            echo "Hostname accepted: $HOSTNAME"
            break
        else
            error_message "Incorrect hostname. Only letters, numbers, '_', '-', and '.' are allowed, and must start with a letter or number."
        fi
    done
    additional_options_menu
}

additional_options_menu() {
    print_ascii_art
    echo "Select additional options:"
    options=("Install graphics drivers" "Enable verbose logging in GRUB" "Set up OpenSSH" "Install NetworkManager" "Install extra packages")
    select_multiple_options "${options[@]}"
    INSTALL_GRAPHICS_DRIVERS="no"
    ENABLE_LOGGING="no"
    INSTALL_OPENSSH="no"
    INSTALL_NETWORKMANAGER="no"
    INSTALL_EXTRA_PACKAGES="no"
    EXTRA_PACKAGES=""
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
        "Install extra packages")
            INSTALL_EXTRA_PACKAGES="yes"
            ;;
        esac
    done
    if [ "$INSTALL_EXTRA_PACKAGES" == "yes" ]; then
        echo "Enter the packages you wish to install separated by spaces (e.g., fastfetch git neovim):"
        read -r EXTRA_PACKAGES < /dev/tty
    fi
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
        echo "BTRFS Subvolumes:"
        for subvol in "${SELECTED_SUBVOLUMES[@]}"; do
            IFS='|' read -r subvol_name mount_point <<< "$subvol"
            echo "  $subvol_name mounted at $mount_point"
        done
    fi
    echo "Swap Size: $SWAP_SIZE"
    echo "Timezone: $TIMEZONE"
    echo "Username: $USERNAME"
    echo "Hostname: $HOSTNAME"
    echo "Install graphics drivers: $INSTALL_GRAPHICS_DRIVERS"
    echo "Enable verbose logging in GRUB: $ENABLE_LOGGING"
    echo "Set up OpenSSH: $INSTALL_OPENSSH"
    echo "Install NetworkManager: $INSTALL_NETWORKMANAGER"
    echo "Install extra packages: $EXTRA_PACKAGES"
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

    # Update system clock and refresh keys
    timedatectl set-ntp true
    install_packages archlinux-keyring gptfdisk

    # Unmount any mounted partitions on /mnt
    umount -A --recursive /mnt || true

    # Detect EFI partition
    EFI_PARTITION=$(detect_efi_partition)
    if [ "$DUAL_BOOT" == "yes" ]; then
        if [ -z "$EFI_PARTITION" ]; then
            echo "EFI partition not found."
            echo "Available partitions:"
            lsblk -p -o NAME,SIZE,FSTYPE,MOUNTPOINT,PARTLABEL
            echo "Please enter the EFI partition (e.g., '/dev/nvme0n1p1'):"
            read -r EFI_PARTITION < /dev/tty
        else
            echo "Found EFI partition: $EFI_PARTITION"
        fi

        # On the selected disk, zap all partitions except EFI partition if present
        EFI_PARTITION_ON_DISK=$(lsblk -lnpo NAME,FSTYPE,PARTLABEL "$DISK" | grep -i 'vfat' | grep -i 'EFI' | awk '{print $1}')
        if [ -n "$EFI_PARTITION_ON_DISK" ]; then
            echo "EFI partition found on $DISK ($EFI_PARTITION_ON_DISK). Preserving EFI partition and deleting other partitions."
            # Delete all other partitions on the disk
            OTHER_PARTITIONS=$(lsblk -lnpo NAME "$DISK" | grep -v "$EFI_PARTITION_ON_DISK")
            for partition in $OTHER_PARTITIONS; do
                wipefs -a "$partition"
                PART_NUM=$(lsblk -no PARTNUM "$partition")
                sgdisk --delete "$PART_NUM" "$DISK"
            done
        else
            echo "No EFI partition found on $DISK. Wiping the disk."
            sgdisk --zap-all "$DISK"
        fi

    else
        # Not dual booting
        sgdisk --zap-all "$DISK"

        # Create EFI partition
        sgdisk -n1:1MiB:+512MiB -t1:EF00 -c1:"EFI System Partition" "$DISK"
        EFI_PARTITION=$(lsblk -lnpo NAME,PARTLABEL "$DISK" | grep "EFI System Partition" | awk '{print $1}')
        mkfs.fat -F32 "$EFI_PARTITION"
    fi

    # Create swap and root partitions
    create_swap_partition
    create_root_partition

    # Run partprobe to update the partition table
    partprobe "$DISK"

    # Get partition names
    SWAP_PARTITION=$(lsblk -lnpo NAME,PARTLABEL "$DISK" | grep "Linux Swap" | awk '{print $1}')
    ROOT_PARTITION=$(lsblk -lnpo NAME,PARTLABEL "$DISK" | grep "Linux filesystem" | awk '{print $1}')

    # Set up swap
    mkswap "$SWAP_PARTITION"
    swapon "$SWAP_PARTITION"

    # Format and mount root partition
    if [ "$FS" == "btrfs" ]; then
        mkfs.btrfs -f "$ROOT_PARTITION"
        mount "$ROOT_PARTITION" /mnt
        btrfs subvolume create /mnt/@
        for subvol in "${SELECTED_SUBVOLUMES[@]}"; do
            IFS='|' read -r subvol_name mount_point <<< "$subvol"
            btrfs subvolume create "/mnt/$subvol_name"
        done
        umount /mnt
        mount -o subvol=@,compress=zstd "$ROOT_PARTITION" /mnt
        for subvol in "${SELECTED_SUBVOLUMES[@]}"; do
            IFS='|' read -r subvol_name mount_point <<< "$subvol"
            mkdir -p "/mnt$mount_point"
            mount -o subvol="$subvol_name",compress=zstd "$ROOT_PARTITION" "/mnt$mount_point"
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
EXTRA_PACKAGES='$EXTRA_PACKAGES'
DUAL_BOOT='$DUAL_BOOT'
EOT

    # Function to perform tasks inside chroot
    configure_system() {
        source /root/install.conf

        # Define install_packages function
        install_packages() {
            pacman -Sy --noconfirm --needed "$@" || echo "Failed to install packages: $@"
        }

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
        PACKAGES=(sudo grub efibootmgr linux-headers dkms)

        # Install NetworkManager if selected
        [[ "$INSTALL_NETWORKMANAGER" == "yes" ]] && PACKAGES+=(networkmanager)

        # Install OpenSSH if selected
        if [ "$INSTALL_OPENSSH" == "yes" ]; then
            PACKAGES+=(openssh)
            systemctl enable sshd
            sed -i 's/^#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
        fi

        # Install graphics drivers if desired
        if [ "$INSTALL_GRAPHICS_DRIVERS" == "yes" ]; then
            gpu_type=$(lspci)
            if echo "${gpu_type}" | grep -E "NVIDIA|GeForce"; then
                PACKAGES+=(nvidia-dkms nvidia-utils)
                # Update mkinitcpio.conf
                sed -i 's/^MODULES=.*/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
            elif echo "${gpu_type}" | grep 'VGA' | grep -E "Radeon|AMD"; then
                PACKAGES+=(xf86-video-amdgpu)
            elif echo "${gpu_type}" | grep -E "Integrated Graphics Controller|Intel Corporation UHD"; then
                PACKAGES+=(mesa xf86-video-intel vulkan-intel libva-intel-driver libva-utils lib32-mesa)
            else
                echo "No compatible GPU detected. Skipping graphics drivers installation."
            fi
        fi

        # Install microcode
        if grep -q "GenuineIntel" /proc/cpuinfo; then
            echo "Installing Intel microcode"
            PACKAGES+=(intel-ucode)
        elif grep -q "AuthenticAMD" /proc/cpuinfo; then
            echo "Installing AMD microcode"
            PACKAGES+=(amd-ucode)
        else
            echo "Unable to determine CPU vendor. Skipping microcode installation."
        fi

        # Include extra packages
        if [ -n "$EXTRA_PACKAGES" ]; then
            PACKAGES+=($EXTRA_PACKAGES)
        fi

        # Install all packages
        install_packages "${PACKAGES[@]}"

        # Enable NetworkManager if selected
        if [ "$INSTALL_NETWORKMANAGER" == "yes" ]; then
            systemctl enable NetworkManager
        fi

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

        # Add os-prober to GRUB
        if [ "$DUAL_BOOT" == "yes" ]; then
            install_packages os-prober
            sed -i '/^GRUB_DISABLE_OS_PROBER=/d' /etc/default/grub
            echo "GRUB_DISABLE_OS_PROBER=false" >> /etc/default/grub
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
    declare -f configure_system > /mnt/root/functions.sh

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
