#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Function to prompt user for input
prompt() {
    read -rp "$1: " "$2"
}

# Function to install packages and handle errors
install_packages() {
    for pkg in "$@"; do
        pacman -S --needed --noconfirm "$pkg" || echo "Failed to install package $pkg, continuing..."
    done
}

# Main script execution starts here

# Prompt for initial configurations
prompt "Enter your region (e.g., 'America')" REGION
prompt "Enter your city (e.g., 'New_York')" CITY
prompt "Enter your hostname" HOSTNAME
prompt "Enter your username" USERNAME
prompt "Do you want to install NVIDIA drivers? (yes/no)" INSTALL_NVIDIA
prompt "Do you want to enable verbose logging in GRUB? (yes/no)" ENABLE_LOGGING
prompt "Do you want to set up OpenSSH for local networks? (yes/no)" INSTALL_OPENSSH
prompt "Do you want to install NetworkManager? (yes/no)" INSTALL_NETWORKMANAGER
prompt "Enter any extra packages to install (space-separated, e.g., 'neovim git')" EXTRA_PACKAGES
prompt "Do you want to install GRUB for dual booting? (yes/no)" INSTALL_GRUB_DUALBOOT
prompt "Do you want to generate the post-install script? (yes/no)" GENERATE_POST_INSTALL_SCRIPT

# Set keyboard layout
loadkeys us

# Generate locales
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen

# Prompt for swap size
prompt "Enter the amount of RAM in GB (for swap partition)" MEM_SIZE

# Detect available disks and partitions
echo "Available disks and partitions:"
lsblk -p -o NAME,SIZE,FSTYPE,MOUNTPOINT

# Prompt for the disk
prompt "Enter the disk to install Arch Linux on (e.g., '/dev/sda')" DISK

# Confirm disk selection
echo "You have selected $DISK"
prompt "Type 'yes' to confirm" CONFIRM_DISK
if [ "$CONFIRM_DISK" != "yes" ]; then
    echo "Installation aborted."
    exit 1
fi

# Inform the user about non-destructive partitioning and display instructions
echo "The script will now guide you through partitioning the disk without deleting existing data."
display_partitioning_instructions() {
    echo "-----------------------------------------------"
    echo "          Manual Partitioning Instructions     "
    echo "-----------------------------------------------"
    echo ""
    echo "You will now use 'gdisk' to manually partition your disk."
    echo ""
    echo "Please create the following partitions in the unallocated space:"
    echo ""
    echo "1. Swap Partition:"
    echo "   - Type: Linux swap (Hex code: 8200)"
    echo "   - Size: ${MEM_SIZE}"
    echo ""
    echo "2. Root Partition:"
    echo "   - Type: Linux filesystem (Hex code: 8300)"
    echo "   - Size: Remaining space"
    echo ""
    echo "Steps:"
    echo "a) Type 'n' to create a new partition."
    echo "b) Accept defaults for partition number and first sector."
    echo "c) For the last sector, enter '+${MEM_SIZE}G' for the swap partition."
    echo "   For the root partition, accept the default to use remaining space."
    echo "d) Enter the appropriate hex code when prompted:"
    echo "   - '8200' for the swap partition"
    echo "   - '8300' for the root partition"
    echo "e) Repeat the steps to create both partitions."
    echo "f) When done, type 'w' to write changes and exit."
    echo ""
    echo "Press Enter to launch 'gdisk'..."
    read -r
}
display_partitioning_instructions

# Launch gdisk for manual partitioning
gdisk "$DISK"

# After gdisk exits, list partitions
echo "Current partition layout:"
lsblk -p "$DISK"

# Prompt for swap and root partition paths
prompt "Enter the swap partition (e.g., '/dev/sda5')" SWAP_PARTITION
prompt "Enter the root partition (e.g., '/dev/sda6')" ROOT_PARTITION

# Set up swap space
echo "Setting up swap space..."
mkswap -L "Linux Swap" "$SWAP_PARTITION"
swapon "$SWAP_PARTITION"
free -m

# Format and mount root partition
echo "Formatting and mounting root partition..."
mkfs.ext4 -L "root" "$ROOT_PARTITION"
mount "$ROOT_PARTITION" /mnt

# Identify existing EFI partition
EFI_PARTITION=$(lsblk -lp | grep -Ei "efi|boot" | grep "part" | awk '{print $1}' | head -n 1)

if [ -z "$EFI_PARTITION" ]; then
    echo "EFI partition not found."
    echo "Available partitions:"
    lsblk -p -o NAME,SIZE,FSTYPE,MOUNTPOINT
    prompt "Please enter the EFI partition (e.g., '/dev/nvme0n1p1')" EFI_PARTITION
fi

echo "EFI partition found at $EFI_PARTITION"

# Mount EFI partition
mkdir -p /mnt/boot
mount "$EFI_PARTITION" /mnt/boot

# Install base system
echo "Installing base system..."
pacstrap /mnt base linux linux-firmware

# Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab

# Copy variables to chroot environment
echo "REGION='$REGION'" >> /mnt/root/install.conf
echo "CITY='$CITY'" >> /mnt/root/install.conf
echo "HOSTNAME='$HOSTNAME'" >> /mnt/root/install.conf
echo "USERNAME='$USERNAME'" >> /mnt/root/install.conf
echo "INSTALL_NVIDIA='$INSTALL_NVIDIA'" >> /mnt/root/install.conf
echo "ENABLE_LOGGING='$ENABLE_LOGGING'" >> /mnt/root/install.conf
echo "INSTALL_OPENSSH='$INSTALL_OPENSSH'" >> /mnt/root/install.conf
echo "INSTALL_NETWORKMANAGER='$INSTALL_NETWORKMANAGER'" >> /mnt/root/install.conf
echo "EXTRA_PACKAGES='$EXTRA_PACKAGES'" >> /mnt/root/install.conf
echo "INSTALL_GRUB_DUALBOOT='$INSTALL_GRUB_DUALBOOT'" >> /mnt/root/install.conf
echo "GENERATE_POST_INSTALL_SCRIPT='$GENERATE_POST_INSTALL_SCRIPT'" >> /mnt/root/install.conf

# Function to perform tasks inside chroot
configure_system() {
    # Set timezone
    ln -sf "/usr/share/zoneinfo/$REGION/$CITY" /etc/localtime
    hwclock --systohc

    # Generate locales
    echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
    locale-gen
    echo "LANG=en_US.UTF-8" > /etc/locale.conf

    # Set hostname
    echo "$HOSTNAME" > /etc/hostname
    cat <<EOT > /etc/hosts
127.0.0.1       localhost
::1             localhost
127.0.1.1       $HOSTNAME.localdomain    $HOSTNAME
EOT

    # Set root password
    echo "-----------------------------------------------"
    echo "             Set Root Password                 "
    echo "-----------------------------------------------"
    passwd

    # Initialize packages to install
    PACKAGES="sudo grub efibootmgr sbctl linux-headers dkms"

    # Add NetworkManager if selected
    if [ "$INSTALL_NETWORKMANAGER" == "yes" ]; then
        PACKAGES="$PACKAGES networkmanager"
    fi

    # Add OpenSSH if selected
    if [ "$INSTALL_OPENSSH" == "yes" ]; then
        PACKAGES="$PACKAGES openssh"
    fi

    # Add NVIDIA drivers if desired
    if [ "$INSTALL_NVIDIA" == "yes" ]; then
        PACKAGES="$PACKAGES nvidia-dkms nvidia-utils"
    fi

    # Install packages
    install_packages $PACKAGES $EXTRA_PACKAGES

    # Enable NetworkManager if installed
    if [ "$INSTALL_NETWORKMANAGER" == "yes" ]; then
        systemctl enable NetworkManager
    fi

    # Enable and start OpenSSH if installed
    if [ "$INSTALL_OPENSSH" == "yes" ]; then
        systemctl enable sshd
        systemctl start sshd
    fi

    # Configure NVIDIA drivers if installed
    if [ "$INSTALL_NVIDIA" == "yes" ]; then
        # Update mkinitcpio.conf
        sed -i 's/^MODULES=.*/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
    fi

    # Generate initramfs
    mkinitcpio -P

    # Install GRUB
    if [ "$INSTALL_GRUB_DUALBOOT" == "yes" ]; then
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
    echo "-----------------------------------------------"
    echo "          Set Password for User $USERNAME       "
    echo "-----------------------------------------------"
    passwd "$USERNAME"

    # Grant sudo privileges to wheel group
    echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/10-wheel
    chmod 440 /etc/sudoers.d/10-wheel

    # Generate post-install script if selected
    if [ "$GENERATE_POST_INSTALL_SCRIPT" == "yes" ]; then
        curl -o /home/"$USERNAME"/archutils.sh https://raw.githubusercontent.com/m-afterlike/arch/main/archutils.sh
        chmod +x /home/"$USERNAME"/archutils.sh
        chown "$USERNAME":"$USERNAME" /home/"$USERNAME"/archutils.sh
    fi

    # Inform user about the post-install script
    if [ "$GENERATE_POST_INSTALL_SCRIPT" == "yes" ]; then
        echo "A post-install configuration script has been downloaded to your home directory as 'archutils.sh'."
        echo "You can run it after rebooting to perform additional configurations."
    fi
}

# Copy functions to chroot environment
declare -f prompt > /mnt/root/functions.sh
declare -f install_packages >> /mnt/root/functions.sh
declare -f configure_system >> /mnt/root/functions.sh

# Chroot into the new system and run configuration
arch-chroot /mnt /bin/bash -c "
source /root/install.conf
source /root/functions.sh
configure_system
rm /root/install.conf /root/functions.sh
"

# Unmount and reboot
echo "Installation complete!"
echo ""
echo "Please remove the installation media (USB) before rebooting."
echo ""
prompt "Press Enter to reboot now or type 'cancel' to stay in the live environment" REBOOT_CHOICE
if [ "$REBOOT_CHOICE" == "cancel" ]; then
    echo "Reboot cancelled. You can now perform additional tasks or reboot manually when ready."
else
    echo "Rebooting now..."
    sleep 5
    umount -R /mnt
    reboot
fi
