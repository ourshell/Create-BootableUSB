# Create a Bootable USB Drive or Deploy Windows

## Overview
To create a bootable USB drive or install/deploy Windows on it (SSD or HDD is preferred), you can use the `Create-BootableUSB.ps1` script. Simply download the `Create-BootableUSB.ps1` file, run it as an administrator, and follow the instructions. 

Alternatively, if you prefer not to change the execution policy or are unsure how to run the script directly, you can download both `Create-BootableUSB.ps1` and `Create-BootableUSB.bat` into the same folder. Then, simply double-click on `Create-BootableUSB.bat` to execute the script with the required administrative permissions.

**Note:** If you prefer to run the script directly (instead of using the batch file), you may need to bypass the execution policy on your system. You can do this by running the following command in an elevated PowerShell prompt:


    Set-ExecutionPolicy Bypass -Scope Process -Force

## Key Point
- **FAT32** is required for booting (supports both BIOS and UEFI).

---

## Prerequisites
- **Administrative permissions** are required.
- Run these commands in an **elevated Command Prompt** (Run CMD as Admin).

---

## Step 1: Prepare the USB Drive
1. Open Command Prompt as Administrator.
2. Enter these commands, replacing `#` with your USB drive's number:

    ```cmd
    diskpart
    list disk
    select disk #
    clean
    create partition primary
    select partition 1
    active
    format fs=fat32 quick
    assign
    exit
    ```

**Note:** Use FAT32 for compatibility with both BIOS and UEFI. Avoid NTFS.

---

## Step 2: Copy Installation Files

### Assumptions:
- `D:` is the source (mounted ISO).
- `E:` is the USB drive.

### Commands:
1. Make the USB bootable:

    ```cmd
    D:\boot\bootsect.exe /nt60 E:
    ```

2. Copy installation files:

    ```cmd
    robocopy D:\ E:\ /e /max:4294967296
    ```

3. Split the large `.wim` file if needed:

    ```cmd
    Dism /Split-Image /ImageFile:D:\sources\install.wim /SWMFile:E:\sources\install.swm /FileSize:4096
    ```

---

## For USB Drives Over 32GB

### Steps:
1. Open Command Prompt as Administrator.
2. Replace `#` with your USB drive number and adjust the size (e.g., 12GB = 12288 MB):

    ```cmd
    diskpart
    list disk
    select disk #
    clean

    create partition primary size=12288
    select partition 1
    active
    format fs=fat32 quick label="BOOT-FAT32"
    assign

    create partition primary
    select partition 2
    format fs=ntfs quick label="DATA-NTFS"
    assign

    exit
    ```

3. Follow the same instructions described in **Step 2**.

---
---

# Install Windows on a Portable USB Drive

This guide will help you install Windows on a portable USB drive.

---

## Prerequisites:
- A USB drive with at least **32 GB** size. An HDD or SSD is highly recommended.
- A Windows ISO file. You can download official versions here:
  - [Microsoft Windows 10](https://www.microsoft.com/en-us/software-download/windows10)
  - [Microsoft Windows 11](https://www.microsoft.com/en-us/software-download/windows11)
- A computer running Windows with **Administrative privileges**.

---

## Step 1: Prepare the USB Drive

First, format and prepare the USB drive to make it bootable. Follow these commands carefully:

### Instructions:
1. Open Command Prompt as **Administrator**.
2. Run the following commands, replacing **X** with the correct disk number for your USB drive:

    ```cmd
    diskpart
    list disk
    select disk X
    clean
    convert gpt
    create partition efi size=256
    format quick fs=fat32 label="System"
    assign letter="S"

    create partition msr size=512
    create partition primary size=1024
    format quick fs=ntfs label="Windows RE Tools"
    assign letter="T"
    set id="de94bba4-06d1-4d40-a16a-bfd50179d6ac"
    gpt attributes=0x8000000000000001

    create partition primary size=8192
    format quick fs=ntfs label="Recovery Image"
    assign letter="R"
    set id="de94bba4-06d1-4d40-a16a-bfd50179d6ac"
    gpt attributes=0x8000000000000001

    create partition primary size=132000
    format quick fs=ntfs label="Windows"
    assign letter="W"
    list volume
    exit
    ```

### Explanation:
- **`diskpart`**: Launches the disk partitioning tool.
- **`list disk`**: Displays all available disks. Identify your USB drive by its size.
- **`select disk X`**: Selects the USB drive. Replace **X** with the disk number corresponding to your USB drive.
- **`clean`**: Deletes all existing data and partitions from the USB drive.
- **`convert gpt`**: Converts the drive to the GPT partition style (required for UEFI booting).
- **Partition creation and formatting**:
  - Creates necessary partitions for EFI, recovery tools, and the Windows installation.
  - Assigns drive letters (`S`, `T`, `R`, `W`) for easier identification.
  - Configures recovery and system partitions with appropriate attributes.

---

## Step 2: Deploy Windows Installation

Once your USB drive is ready, apply the Windows image to it.

### Instructions:
1. Mount the Windows ISO file to a virtual drive (e.g., `D:`).
2. Open Command Prompt as **Administrator** and run the following commands:

    ```cmd
    dism /Get-WimInfo /WimFile:D:\sources\install.wim
    md R:\RecoveryImage
    copy D:\sources\install.wim R:\RecoveryImage\install.wim

    dism /Apply-Image /ImageFile:R:\RecoveryImage\install.wim /Index:5 /ApplyDir:W:\

    md T:\Recovery\WindowsRE
    copy W:\Windows\System32\Recovery\winre.wim T:\Recovery\WindowsRE\winre.wim

    bcdboot W:\Windows /s S: /f UEFI
    W:\Windows\System32\reagentc /setosimage /path R:\RecoveryImage /target W:\Windows /index 5
    W:\Windows\System32\reagentc /setreimage /path T:\Recovery\WindowsRE /target W:\Windows
    ```

### Explanation:
- **`dism /Get-WimInfo`**: Displays details about the Windows image in the `install.wim` file.
- **`md R:\RecoveryImage`**: Creates a folder on the USB drive for the recovery image.
- **`copy D:\sources\install.wim`**: Copies the Windows installation image to the USB drive.
- **`dism /Apply-Image`**: Applies the selected Windows image to the USB drive. Use the appropriate index (e.g., `5` for Windows Pro).
- **`md T:\Recovery\WindowsRE`**: Creates a folder for Windows Recovery Environment (WinRE).
- **`bcdboot`**: Configures the USB drive to boot Windows in UEFI mode by copying the boot files.
- **`reagentc`**: Registers the recovery and system images for Windows.
