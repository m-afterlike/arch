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
echo "6) Create user directories like ~/Desktop and ~/Music"
echo "7) Boot into UEFI Firmware Settings"
echo "8) Exit"
echo ""
read -p "Enter your choice [1-8]: " CHOICE

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
        # Install xdg-user-dirs
        sudo pacman -S --noconfirm xdg-user-dirs

        xdg-user-dirs-update

        echo "Directories were successfully created"
        ;;
    7)
        # Boot into UEFI
        echo "Rebooting now..."
        sleep 5
        sudo systemctl reboot --firmware-setup
        ;;
    8)
        echo "Exiting."
        ;;
    *)
        echo "Invalid choice. Exiting."
        ;;
esac
