#!/bin/bash
set -e

echo "-----------------------------------------------"
echo "        Post-Install Configuration Script      "
echo "-----------------------------------------------"
echo ""
echo "Please choose an option:"
echo "1) Enable GRUB verbose logging"
echo "2) Disable GRUB verbose logging"
echo "3) Set up Secure Boot"
echo "4) Enable os-prober (detect other OSes in GRUB)"
echo "5) Disable os-prober"
echo "6) Exit"
echo ""
read -p "Enter your choice [1-6]: " CHOICE

case "$CHOICE" in
    1)
        echo "Enabling GRUB verbose logging..."
        sudo sed -i '/^GRUB_CMDLINE_LINUX_DEFAULT=/ s/"$/ debug"/' /etc/default/grub
        sudo grub-mkconfig -o /boot/grub/grub.cfg
        echo "GRUB verbose logging enabled."
        ;;
    2)
        echo "Disabling GRUB verbose logging..."
        sudo sed -i '/^GRUB_CMDLINE_LINUX_DEFAULT=/ s/ debug"$/"/' /etc/default/grub
        sudo grub-mkconfig -o /boot/grub/grub.cfg
        echo "GRUB verbose logging disabled."
        ;;
    3)
        echo "Setting up Secure Boot..."
        # Check sbctl status
        SBCTL_STATUS=$(sudo sbctl status)
        echo "$SBCTL_STATUS"

        SETUP_MODE=$(echo "$SBCTL_STATUS" | grep "Setup Mode:" | awk '{print $3}')
        SECURE_BOOT=$(echo "$SBCTL_STATUS" | grep "Secure Boot:" | awk '{print $3}')

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
                exit 1
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

        # Search for 'grubx64.efi' and 'vmlinuz-linux'
        echo "Detecting paths to sign..."
        GRUB_EFI_PATH=$(sudo find /boot -name 'grubx64.efi' | head -n 1)
        VMLINUZ_PATH=$(sudo find /boot -name 'vmlinuz-linux' | head -n 1)

        echo "Detected paths:"
        echo "GRUB EFI: $GRUB_EFI_PATH"
        echo "vmlinuz-linux: $VMLINUZ_PATH"

        read -p "Do these paths look correct? (yes/no): " PATHS_CORRECT
        if [[ "$PATHS_CORRECT" != "yes" ]]; then
            echo "Please verify the paths and enter the correct paths."
            echo "Enter the path to GRUB EFI (e.g., /boot/EFI/GRUB/grubx64.efi):"
            read -p "> " GRUB_EFI_PATH
            echo "Enter the path to vmlinuz-linux (e.g., /boot/vmlinuz-linux):"
            read -p "> " VMLINUZ_PATH
        fi

        # Sign the detected files
        sudo sbctl sign -s "$GRUB_EFI_PATH"
        sudo sbctl sign -s "$VMLINUZ_PATH"

        # Ask if user wants to add more paths
        read -p "Do you need to sign additional files? (yes/no): " ADD_FILES
        if [[ "$ADD_FILES" == "yes" ]]; then
            echo "Enter additional paths to sign, separated by spaces:"
            read -p "> " ADDITIONAL_PATHS
            for path in $ADDITIONAL_PATHS; do
                sudo sbctl sign -s "$path"
            done
        fi

        # Run sbctl verify
        sudo sbctl verify

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
        ;;
    4)
        echo "Enabling os-prober..."
        # Install os-prober
        sudo pacman -S --noconfirm os-prober

        # Enable os-prober in GRUB configuration
        sudo sed -i '/^GRUB_DISABLE_OS_PROBER=/d' /etc/default/grub
        echo "GRUB_DISABLE_OS_PROBER=false" | sudo tee -a /etc/default/grub

        # Regenerate GRUB configuration
        sudo grub-mkconfig -o /boot/grub/grub.cfg

        echo "os-prober enabled. GRUB will now detect other operating systems."
        ;;
    5)
        echo "Disabling os-prober..."
        # Remove or comment out the os-prober line in GRUB configuration
        sudo sed -i '/^GRUB_DISABLE_OS_PROBER=/d' /etc/default/grub
        echo "GRUB_DISABLE_OS_PROBER=true" | sudo tee -a /etc/default/grub

        # Regenerate GRUB configuration
        sudo grub-mkconfig -o /boot/grub/grub.cfg

        echo "os-prober disabled. GRUB will not detect other operating systems."
        ;;
    6)
        echo "Exiting."
        ;;
    *)
        echo "Invalid choice. Exiting."
        ;;
esac
