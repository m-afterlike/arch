# Arch Dual-Boot & Utilities Scripts

A simple script for installing Arch Linux alongside Windows, with an additional script for Secure Boot and useful post-install utilities.

## Repository Contents

- **`install.sh`**: An installation script for Arch Linux with options for a dual-boot configuration with Windows.
- **`utilbox.sh`**: A utility script for application and system setup, including Secure Boot setup and other system utilities.

## Arch Install Script

**Curl and run the script**:
  ```bash
  curl -fsSL https://afterlike.org/arch | bash
  ```

> [!CAUTION]
> By using this script, you acknowledge that:
>
> - **I am not responsible for any data loss, system issues, or other problems.**
> - **Read the script thoroughly** before running it.
> - **Backup your data** before running the script.

## Utilbox Script

**Download and run the script**:
  ```bash
  curl -fsSL https://afterlike.org/utilbox | bash
  ```

> [!NOTE]
> The `archutils.sh` script uses `sbctl` to generate Secure Boot keys and sign EFI files. Run Secure Boot setup only if Secure Boot is disabled in UEFI firmware and in Setup Mode until keys are enrolled. Only proceed with Secure Boot setup if you understand custom key enrollment.
