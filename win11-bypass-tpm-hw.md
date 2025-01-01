# How to Bypass Windows 11 TPM Check and Other Hardware Requirements

Windows 11 has strict hardware requirements such as TPM, Secure Boot, CPU, RAM, and storage. However, it is possible to bypass these requirements using several methods during installation. Below are detailed instructions on how to bypass these checks.

---

## Method 1: Modify the Registry During Installation

This method involves modifying the registry during the installation process to bypass the hardware checks for TPM, CPU, RAM, Secure Boot, and more.

### Step-by-Step Instructions:
1. **Start the Windows 11 Installer**:
   - Boot your computer using the Windows 11 installation media (USB or DVD).

2. **Open the Command Prompt**:
   - On the screen where it asks "Where do you want to install Windows?", press `Shift + F10` to open the Command Prompt.

3. **Open the Registry Editor**:
   - In the Command Prompt, type `regedit` and press Enter.

4. **Navigate to the Registry Key**:
   - In the Registry Editor, go to: `HKEY_LOCAL_MACHINE\SYSTEM\Setup`.

5. **Create a New Key**:
   - Right-click on `Setup` → Select `New → Key` → Name it `LabConfig`.

6. **Add Values to Bypass Hardware Requirements**:
   - Right-click on `LabConfig` → Select `New → DWORD (32-bit) Value` → Add the following values:
     - `BypassTPMCheck` = `1`
     - `BypassCPUCheck` = `1`
     - `BypassRAMCheck` = `1`
     - `BypassStorageCheck` = `1`
     - `BypassSecureBootCheck` = `1`

7. **Close the Registry Editor**:
   - After adding the registry values, close the Registry Editor and continue with the installation.

---

## Method 2: Modify the Installation Media (ISO)

This method involves modifying the Windows 11 installation files to remove the TPM, CPU, RAM, and other compatibility checks.

### Step-by-Step Instructions:
1. **Mount the ISO or Extract Files**:
   - Simply extract the files from the ISO on your PC.

2. **Delete the `appraiserres.dll` File**:
   - Navigate to the `sources` folder in the installation media.
   - Locate the file `appraiserres.dll` and delete it. This file is responsible for checking hardware compatibility.

3. **Rebuild the ISO (Optional)**:
   - If you've extracted the ISO, use a tool like `OSCDIMG` to rebuild the ISO with the modified files.

4. **Create a Bootable USB**:
   - If you modified the ISO, create a new bootable USB drive using a tool like Rufus.

---

## Bypass Virtualization-Based Security (VBS) Requirement

If VBS or Hyper-V is enabled, it may interfere with installation. Here's how to disable it:

### Instructions:
1. **Disable Hyper-V and VBS**:
   - Before installation, open an elevated Command Prompt and run the following command:
     ```bash
     dism.exe /Online /Disable-Feature:Microsoft-Hyper-V-All
     ```
