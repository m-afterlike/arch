#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Function to prompt user for input
prompt() {
    read -rp "$1: " "$2"
}

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
    echo "Set root password:"
    passwd

    # Install additional packages
    pacman -S --noconfirm networkmanager sudo grub efibootmgr sbctl linux-headers dkms

    # Enable NetworkManager
    systemctl enable NetworkManager

    # Install NVIDIA drivers if desired
    if [ "$INSTALL_NVIDIA" == "yes" ]; then
        pacman -S --noconfirm nvidia-dkms nvidia-utils
        # Update mkinitcpio.conf
        sed -i 's/^MODULES=.*/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
    fi

    # Generate initramfs
    mkinitcpio -P

    # Install GRUB
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB

    # Modify GRUB for verbose logging if desired
    if [ "$ENABLE_LOGGING" == "yes" ]; then
        sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="[^"]*/& debug/' /etc/default/grub
    fi

    # Generate GRUB configuration
    grub-mkconfig -o /boot/grub/grub.cfg

    # Create new user and add to wheel group
    useradd -m -G wheel -s /bin/bash "$USERNAME"
    echo "Set password for user $USERNAME:"
    passwd "$USERNAME"

    # Grant sudo privileges to wheel group
    sed -i '/^# %wheel ALL=(ALL) ALL$/s/^# //' /etc/sudoers

    # Inform user about post-install Secure Boot setup
    echo "Secure Boot setup will be completed after rebooting into the new system."
}

# Main script execution starts here

# Function to display partitioning instructions
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
    echo "   - Size: ${MEM_SIZE}G"
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

# Prompt for region, city, hostname
prompt "Enter your region (e.g., 'America')" REGION
prompt "Enter your city (e.g., 'New_York')" CITY
prompt "Enter your hostname" HOSTNAME

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
mkdir -p /mnt/boot/efi
mount "$EFI_PARTITION" /mnt/boot/efi

# Install base system
echo "Installing base system..."
pacstrap /mnt base linux linux-firmware

# Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab

# Prompt for additional configurations
prompt "Enter your username" USERNAME
prompt "Do you want to install NVIDIA drivers? (yes/no)" INSTALL_NVIDIA
prompt "Do you want to enable verbose logging in GRUB? (yes/no)" ENABLE_LOGGING

# Copy variables to chroot environment
echo "REGION='$REGION'" >> /mnt/root/install.conf
echo "CITY='$CITY'" >> /mnt/root/install.conf
echo "HOSTNAME='$HOSTNAME'" >> /mnt/root/install.conf
echo "USERNAME='$USERNAME'" >> /mnt/root/install.conf
echo "INSTALL_NVIDIA='$INSTALL_NVIDIA'" >> /mnt/root/install.conf
echo "ENABLE_LOGGING='$ENABLE_LOGGING'" >> /mnt/root/install.conf

# Copy functions to chroot environment
declare -f prompt > /mnt/root/functions.sh
declare -f configure_system >> /mnt/root/functions.sh

# Chroot into the new system and run configuration
arch-chroot /mnt /bin/bash -c "
source /root/install.conf
source /root/functions.sh
configure_system
rm /root/install.conf /root/functions.sh
"

# Unmount and reboot with warning
echo "Installation complete!"
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
