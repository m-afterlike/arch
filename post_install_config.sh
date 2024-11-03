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
        sudo sed -i '/GRUB_CMDLINE_LINUX_DEFAULT/ s/"$/ debug"/' /etc/default/grub
        sudo grub-mkconfig -o /boot/grub/grub.cfg
        echo "GRUB verbose logging enabled."
        ;;
    2)
        echo "Disabling GRUB verbose logging..."
        sudo sed -i '/GRUB_CMDLINE_LINUX_DEFAULT/ s/ debug"/"/' /etc/default/grub
        sudo grub-mkconfig -o /boot/grub/grub.cfg
        echo "GRUB verbose logging disabled."
        ;;
    3)
        echo "Setting up Secure Boot..."
        # Verify you are in setup mode
        sudo sbctl status

        # Create custom Secure Boot keys
        sudo sbctl create-keys

        # Enroll custom keys including Microsoft's certificates
        sudo sbctl enroll-keys -m

        # Verify key enrollment
        sudo sbctl status

        # Sign EFI binaries
        sudo sbctl sign -s /boot/EFI/GRUB/grubx64.efi
        sudo sbctl sign -s /boot/vmlinuz-linux

        # If NVIDIA drivers are installed, sign the modules
        KERNEL_VER=$(uname -r)
        if [ -d "/usr/lib/modules/$KERNEL_VER/kernel/drivers/video" ]; then
            sudo find "/usr/lib/modules/$KERNEL_VER/kernel/drivers/video" -name "*.ko" -exec sbctl sign -s {} \;
        fi

        # Rebuild initramfs
        sudo mkinitcpio -P

        # Regenerate GRUB configuration
        sudo grub-mkconfig -o /boot/grub/grub.cfg

        echo "Secure Boot configuration completed successfully."
        ;;
    4)
        echo "Enabling os-prober..."
        # Install os-prober
        sudo pacman -S --noconfirm os-prober

        # Enable os-prober in GRUB configuration
        echo "GRUB_DISABLE_OS_PROBER=false" | sudo tee -a /etc/default/grub

        # Regenerate GRUB configuration
        sudo grub-mkconfig -o /boot/grub/grub.cfg

        echo "os-prober enabled. GRUB will now detect other operating systems."
        ;;
    5)
        echo "Disabling os-prober..."
        # Remove or comment out the os-prober line in GRUB configuration
        sudo sed -i '/GRUB_DISABLE_OS_PROBER=true/d' /etc/default/grub
        sudo sed -i '/GRUB_DISABLE_OS_PROBER=false/d' /etc/default/grub
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
