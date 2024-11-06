# Arch Dual-Boot & Utilities Scripts

A simple script for installing Arch Linux alongside Windows, with an additional script for Secure Boot and useful post-install utilities.

## Repository Contents

- **`archinstall.sh`**: A simple installation script for Arch Linux in a dual-boot configuration with Windows.
- **`archutils.sh`**: A utility script for post-install configuration, including Secure Boot setup and other system utilities.

## Instructions

### Arch Install Script

**Download and run the script**:
  ```bash
  curl -O https://afterlike.org/archinstall.sh
  chmod +x archinstall.sh
  ./archinstall.sh
  ```

**The script will guide you through**:
- Selecting your region, hostname, and username.
- Choosing optional configurations such as NVIDIA drivers, NetworkManager, and GRUB setup for dual-booting.
- Manually partitioning (using gdisk).
- Setting up the base system, configuring Secure Boot, and installing essential packages.

## Utility Script

**Download and run the script**:
  ```bash
  curl -O https://afterlike.org/archutils.sh
  chmod +x archutils.sh
  ./archutils.sh
  ```

**Utility Script Options**:
- Enable/Disable GRUB Verbose Logging: Adjust debug logging settings in GRUB.
- Set Up Secure Boot: Generates and enrolls Secure Boot keys and signs necessary EFI files.
- Enable/Disable os-prober: Toggles detection of other installed operating systems in GRUB.
- Create User Directories: Sets up standard directories like `~/Desktop` and `~/Music`.
- Boot into UEFI Firmware Settings: Restarts the system directly into UEFI.

**Notes on Secure Boot**:
The `archutils.sh` script uses `sbctl` to generate Secure Boot keys and sign EFI files. Run Secure Boot setup only if Secure Boot is disabled in UEFI firmware and in Setup Mode until keys are enrolled. Only proceed with Secure Boot setup if you understand custom key enrollment.
