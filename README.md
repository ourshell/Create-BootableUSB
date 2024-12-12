# Create a Bootable USB Drive

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
