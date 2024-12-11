# Create a Bootable USB Drive

## Key Point
- **FAT32** is required for booting (supports BIOS and UEFI).

## Prerequisites
- Administrative permissions are required.
- Run these commands in an elevated Command Prompt (Run CMD as Admin).

## Step 1: Prepare the USB Drive
1. Open Command Prompt as Administrator.
2. Enter these commands (replace `#` with your USB drive's number):

```bash
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

> **Note:** Use FAT32 for compatibility with both BIOS and UEFI. Avoid NTFS.

## Step 2: Copy Installation Files

### Assumptions
- `D:` is the source (mounted ISO).
- `E:` is the USB drive.

### Steps
1. Make the USB bootable:

```bash
D:\boot\bootsect.exe /nt60 E:
```

2. Copy installation files:

```bash
robocopy D:\ E:\ /e /max:4294967296
```

3. Split large `.wim` files if needed:

```bash
Dism /Split-Image /ImageFile:D:\sources\install.wim /SWMFile:E:\sources\install.swm /FileSize:4096
```

## For USB Drives Over 32GB
Follow these steps for drives larger than 32GB:

1. Open Command Prompt as Administrator.
2. Replace `#` with your USB drive number and adjust the size (e.g., 12GB = 12288 MB):

```bash
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
