# Import the required assemblies
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Windows.Forms

# Check for Administrative Privileges
$IsUser = cmd /c "NET SESSION 2>&1" | Out-String

if ($IsUser -like "*Access*denied*") {
    if ($MyInvocation.MyCommand.Path) {
        Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Path)`"" -Verb RunAs
        return "The script is ran a user and wont work. Administrative privileges are required."
    }
    else {
        return "Save the script and prior to run, or run the code as administrator."
    }
}
else {
    Write-Host "Generating the graphic interface . . ."
}

#### Define the main logic in following script blocks to execute in a runspace ####

# Logic to check for update

$ScriptUpdate = {
    param ([string]$Action)

    $TimeStamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $output = "================ Begin: $TimeStamp ================`r`n`r`n"
    $output += "Checking for new version, please wait . . ."
    $SyncHash.UpdateLog.Invoke(@($output, $Error))

    try {
        $Json = Invoke-RestMethod -Uri $SyncHash.ScriptInfo.Json -UseBasicParsing -Method Get -ErrorAction Stop
        $SyncHash.UpdateLog.Invoke("Local Version: $($SyncHash.ScriptInfo.Version)`r`nLatest Version: $($Json.Version)")

        if ($Action -eq "ButtonUpdate") {
            if ([double]$Json.Version -gt [double]$SyncHash.ScriptInfo.Version) {
                $Content = (Invoke-WebRequest -Uri $Json.UrlContent -UseBasicParsing -ErrorAction Stop).Content

                if ($Content -and $SyncHash.ScriptInfo.LocalPath) {
                    try {
                        Set-Content -Path $SyncHash.ScriptInfo.LocalPath -Value $Content -Force -ErrorAction Stop
                        $SyncHash.UpdateLog.Invoke("Update finished successfully. Restart the script to take effect.")
                    } catch {
                        $SyncHash.UpdateLog.Invoke("Unable to update the script due to an internal error.", $_)
                    }
                } else {
                    $SyncHash.UpdateLog.Invoke("Missing script's local path or repo is not available.")
                }
            } else {
                $SyncHash.UpdateLog.Invoke("There is no new version.")
            }
        } else {
            $SyncHash.UpdateLog.Invoke("If there is a new version, you can proceed with the update.")
        }
    } catch {
        $SyncHash.UpdateLog.Invoke("An error occurred while checking for updates.", $_)
    } finally {
        $SyncHash.UpdateLog.Invoke("Finished!")

        # Enable GUI objects after completion
        $SyncHash.Window.Dispatcher.Invoke([action] {
            & $SyncHash.EnableValidObjects
            $TimeStamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            $SyncHash.TextBoxUpdate.AppendText("================ End: $TimeStamp ================`r`n`r`n")
            $SyncHash.TextBoxUpdate.ScrollToEnd()
        })
    }
}

# Logic to verify the image
$GetImageHealth = {
    $TimeStamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $output = "================ Begin: $TimeStamp ================`r`n`r`n"
    $output += "Operation: Get Image Health`r`n"
    $output += "Selected File: $($SyncHash.IsoPath)`r`n"
    $output += "The selected image is being verified, please wait . . ."

    $SyncHash.WriteOutput.Invoke(@($output, $Error))

    try {
        $Image = Get-DiskImage -ImagePath $SyncHash.IsoPath -ErrorAction Stop

        if (-not $Image.Attached) {
            Mount-DiskImage -ImagePath $SyncHash.IsoPath -ErrorAction Stop
        }

        $SyncHash.IsoDrive = ($Image | Get-Volume -ErrorAction Stop).DriveLetter

        if (Test-Path -Path "$($SyncHash.IsoDrive)`:\sources\install.wim" -ErrorAction SilentlyContinue) {
            $SyncHash.OSEditions = Get-WindowsImage -ImagePath "$($SyncHash.IsoDrive)`:\sources\install.wim" -ErrorAction SilentlyContinue
        }

        if ($SyncHash.OSEditions) {
            $SyncHash.Window.Dispatcher.Invoke([action] {
                foreach ($edition in $SyncHash.OSEditions) {
                    $ComboBoxItem = New-Object System.Windows.Controls.ComboBoxItem
                    $ComboBoxItem.Content = $edition.ImageName
                    $ComboBoxItem.ToolTip = $edition.ImageDescription
                    $SyncHash.OSEditionsComboBox.Items.Add($ComboBoxItem) | Out-Null
                }
            })
        } else {
            $SyncHash.WriteOutput.Invoke("No Windows Editions found!`r`nIf it's Linux, VMware or other bootable ISO, you can still burn it on a USB drive.")
        }
    } catch {
        $SyncHash.WriteOutput.Invoke("Error occurred:", $_)
    } finally {
        $SyncHash.WriteOutput.Invoke("Finished!")

        # Enable GUI objects after completion
        $SyncHash.Window.Dispatcher.Invoke([action] {
            if ($SyncHash.OSEditionsComboBox.Items) {
                $SyncHash.OSEditionsComboBox.SelectedIndex = 0
            }

            & $SyncHash.EnableValidObjects
            $TimeStamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            $SyncHash.OutputTextBox.AppendText("================ End: $TimeStamp ================`r`n`r`n")
            $SyncHash.OutputTextBox.ScrollToEnd()
        })
    }
}

# Logic to get File Hash
$GetFileHash = {
    param ([string]$algorithm)

    $TimeStamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $output = "================ Begin: $TimeStamp ================`r`n`r`n"
    $output += "Operation: Get File Hash`r`n"
    $output += "Selected File: $($SyncHash.IsoPath)`r`n"
    $output += "Calculating Hash $algorithm, please wait . . ."

    $SyncHash.WriteOutput.Invoke($output, $Error)

    try {
        $hash = Get-FileHash -Path $SyncHash.IsoPath -Algorithm $algorithm -ErrorAction Stop
        $SyncHash.WriteOutput.Invoke($hash.Hash)
    } catch {
        $SyncHash.WriteOutput.Invoke("Error occurred during hash calculation.", $_)
    } finally {
        $SyncHash.WriteOutput.Invoke("Finished!")

        # Enable GUI objects after completion
        $SyncHash.Window.Dispatcher.Invoke([action] {
            & $SyncHash.EnableValidObjects
            $TimeStamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            $SyncHash.OutputTextBox.AppendText("================ End: $TimeStamp ================`r`n`r`n")
            $SyncHash.OutputTextBox.ScrollToEnd()
        })
    }
}

# Logic for Bootable USB
$CreateBootableDrive = {
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $output = "================ Begin: $timestamp ================`r`n`r`n"
    $output += "Operation: Create Bootable (USB) Drive`r`n"
    $output += "Selected Disk: $($SyncHash.SelectedDrive.Caption)`r`n"
    $output += "Selected Image: $($SyncHash.IsoPath)`r`n"
    $output += "Repartitioning the drive . . ."

    $SyncHash.WriteOutput.Invoke(@($output, $Error))

    try {
        if ($SyncHash.SelectedDrive.Size -le (32 * 1GB)) {
            $DrivePartition2 = $false

            $DiskPartScript = "select disk $($SyncHash.SelectedDrive.Index)" + "`r`n"
            $DiskPartScript += "clean" + "`r`n"
            $DiskPartScript += "create partition primary" + "`r`n"
            $DiskPartScript += "select partition 1" + "`r`n"
            $DiskPartScript += "active" + "`r`n"
            $DiskPartScript += "format fs=fat32 quick" + "`r`n"
            $DiskPartScript += "assign" + "`r`n"
            $DiskPartScript += "exit" + "`r`n"
        } else {
            $DrivePartition2 = $true
            $PartitionSize = [math]::Min([System.Math]::Floor($SyncHash.SelectedDrive.Size / 2MB), 32 * 1024)

            $DiskPartScript = "select disk $($SyncHash.SelectedDrive.Index)" + "`r`n"
            $DiskPartScript += "clean" + "`r`n"
            $DiskPartScript += "create partition primary size=$PartitionSize" + "`r`n"
            $DiskPartScript += "select partition 1" + "`r`n"
            $DiskPartScript += "active" + "`r`n"
            $DiskPartScript += "format fs=fat32 quick label=`"BOOT-FAT32`"" + "`r`n"
            $DiskPartScript += "assign" + "`r`n"
            $DiskPartScript += "create partition primary" + "`r`n"
            $DiskPartScript += "select partition 2" + "`r`n"
            $DiskPartScript += "format fs=ntfs quick label=`"DATA-NTFS`"" + "`r`n"
            $DiskPartScript += "assign" + "`r`n"
            $DiskPartScript += "exit" + "`r`n"
        }

        # $DiskPartOutput = diskpart.exe /s ([System.IO.Path]::GetTempFileName() | Set-Content -Value $DiskPartScript -PassThru) 2>&1
        $DiskPartOutput = $DiskPartScript | diskpart 2>&1 | Out-String

        $SyncHash.WriteOutput.Invoke($DiskPartOutput)
        $SyncHash.WriteOutput.Invoke("Burning ISO Image . . .")

        Start-Sleep -Seconds 2

        $FlashDrive = Get-Partition -DiskNumber $SyncHash.SelectedDrive.Index -PartitionNumber 1 -ErrorAction Stop | Select-Object -ExpandProperty DriveLetter

        if (Test-Path -Path "$($SyncHash.IsoDrive)`:\boot\bootsect.exe") {
            $output = "Updating the boot code from $FlashDrive`: to $($SyncHash.IsoDrive)`:"
            $SyncHash.WriteOutput.Invoke($output)

            $BootSectOutput = cmd /c "$($SyncHash.IsoDrive)`:\boot\bootsect.exe /nt60 $FlashDrive`:" 2>&1 | Out-String
            $SyncHash.WriteOutput.Invoke($BootSectOutput)
        }

        $source = "$($SyncHash.IsoDrive)`:\"
        $destination = "$FlashDrive`:\"
        $MaxSize = 4294967296  # 4 GB in bytes

        $SyncHash.WriteOutput.Invoke("Copying files from $source to $destination")
        $output = ""

        Get-ChildItem -Path $source -Recurse -ErrorAction Stop | ForEach-Object {
            $DestPath = Join-Path -Path $destination -ChildPath ($_.FullName -replace [regex]::Escape($source), "") -ErrorAction Stop

            if ($_.PSIsContainer) {
                New-Item -ItemType Directory -Path $DestPath -Force -ErrorAction Stop | Out-Null
            } elseif ($_.Length -le $MaxSize) {
                Copy-Item -Path $_.FullName -Destination $DestPath -Force -ErrorAction Stop | Out-Null
            } else {
                $output += "Skip file '$($_.FullName)' with size $($_.Length) bytes. The size is over 4GB for FAT32`r`n"
            }
        }

        $SyncHash.WriteOutput.Invoke($output)

        if ((Test-Path -Path "$($source)sources\install.wim") -and ((Get-Item -Path "$($source)sources\install.wim").Length -gt 4GB)) {
            $output = "DISM: Split file '$($source)sources\install.wim' to '$($destination)sources\install.swm'"
            $SyncHash.WriteOutput.Invoke($output)

            $DismOutput = cmd /c "dism /Split-Image /ImageFile:$($source)sources\install.wim /SWMFile:$($destination)sources\install.swm /FileSize:4096" 2>&1 | Out-String

            $SyncHash.WriteOutput.Invoke($DismOutput)
        }
    } catch {
        $SyncHash.WriteOutput.Invoke("Error during operation:", $_)
    } finally {
        $SyncHash.WriteOutput.Invoke("Finished!")

        $SyncHash.Window.Dispatcher.Invoke([action] {
            & $SyncHash.EnableValidObjects
            $TimeStamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            $SyncHash.OutputTextBox.AppendText("================ End: $TimeStamp ================`r`n`r`n")
            $SyncHash.OutputTextBox.ScrollToEnd()
        })
    }
}

# Logic for Windows Preinstallation Environment.
$InstallWindowsOnDrive = {
    param ($PartitionSize)

    $output = "================ Begin: $((Get-Date).ToString("yyyy-MM-dd HH:mm:ss")) ================`r`n`r`n"
    $output += "Operation: Install Windows on (USB) Drive" + "`r`n"
    $output += "Selected Disk: $($SyncHash.SelectedDrive.Caption)`r`n"
    $output += "Selected Image: $($SyncHash.IsoPath)`r`n`r`n"

    $output += "Name: $($SyncHash.SelectedOSEdition.ImageName)`r`n"
    $output += "Description: $($SyncHash.SelectedOSEdition.ImageDescription)`r`n"
    $output += "Size: $(($SyncHash.SelectedOSEdition.ImageSize / 1GB).ToString("F2")) GB`r`n`r`n"

    $output += "Repartitioning the drive . . ."

    $SyncHash.WriteOutput.Invoke($output, $Error)
    $Error.Clear()

    Clear-Disk -Number $SyncHash.SelectedDrive.Index -RemoveData -RemoveOEM -Confirm:$false
    Start-Sleep -Seconds 1
    Initialize-Disk -Number $SyncHash.SelectedDrive.Index -PartitionStyle GPT
    Start-Sleep -Seconds 1
    Set-Disk -Number $SyncHash.SelectedDrive.Index -PartitionStyle GPT
    Start-Sleep -Seconds 1

    $efiPartition = New-Partition -DiskNumber $SyncHash.SelectedDrive.Index -Size $PartitionSize.efi -GptType "{C12A7328-F81F-11D2-BA4B-00A0C93EC93B}"
    Format-Volume -Partition $efiPartition -FileSystem FAT32 -NewFileSystemLabel "System" -Confirm:$false
    Start-Sleep -Seconds 1

    $msrPartition = New-Partition -DiskNumber $SyncHash.SelectedDrive.Index -Size $PartitionSize.msr -GptType "{E3C9E316-0B5C-4DB8-817D-F92DF00215AE}"
    Start-Sleep -Seconds 1

    $reToolsPartition = New-Partition -DiskNumber $SyncHash.SelectedDrive.Index -Size $PartitionSize.retools -GptType "{DE94BBA4-06D1-4D40-A16A-BFD50179D6AC}"
    Format-Volume -Partition $reToolsPartition -FileSystem NTFS -NewFileSystemLabel "Windows RE Tools" -Confirm:$false
    Start-Sleep -Seconds 1

    $recoveryImagePartition = New-Partition -DiskNumber $SyncHash.SelectedDrive.Index -Size $PartitionSize.recovery -GptType "{DE94BBA4-06D1-4D40-A16A-BFD50179D6AC}"
    Format-Volume -Partition $recoveryImagePartition -FileSystem NTFS -NewFileSystemLabel "Recovery Image" -Confirm:$false
    Start-Sleep -Seconds 1

    if ($PartitionSize.windows -eq "max") {
        $windowsPartition = New-Partition -DiskNumber $SyncHash.SelectedDrive.Index -UseMaximumSize
    }
    else {
        $windowsPartition = New-Partition -DiskNumber $SyncHash.SelectedDrive.Index -Size $PartitionSize.windows
    }

    Format-Volume -Partition $windowsPartition -FileSystem NTFS -NewFileSystemLabel "Windows" -Confirm:$false
    Start-Sleep -Seconds 1

    $Unallocated = Get-Disk -Number $SyncHash.SelectedDrive.Index | Select-Object -ExpandProperty LargestFreeExtent
    $DataPartition = $null

    # Check if there is an unallocated space. Applies if custom Windows partition size is set. The minimum requirement for NTFS partition is 16MB
    if ($Unallocated -gt 16MB) {
        $DataPartition = New-Partition -DiskNumber $SyncHash.SelectedDrive.Index -UseMaximumSize
        Format-Volume -Partition $DataPartition -FileSystem NTFS -NewFileSystemLabel "DATA" -Confirm:$false
        Start-Sleep -Seconds 1
    }

    $output = "Assigning custom GPT attributes for partitions 'Windows RE Tools' and 'Recovery Image' . . ."
    $SyncHash.WriteOutput.Invoke($output, $Error)
    $Error.Clear()

    $diskpart = (@"
select disk $($SyncHash.SelectedDrive.Index)
select partition $($reToolsPartition.PartitionNumber)
gpt attributes=0x8000000000000001
select partition $($recoveryImagePartition.PartitionNumber)
gpt attributes=0x8000000000000001
exit
"@ | diskpart.exe 2>&1)

    $output = ($diskpart | Out-String).Trim()
    $output += "Internal script preparation for deployment. Modules, symlinks, folders, files . . ."
    $SyncHash.WriteOutput.Invoke($output, $Error)
    $Error.Clear()

    Start-Sleep -Seconds 1

    if (Test-Path -Path "$env:TEMP\Create-BootableUSB") {
        Remove-Item -Path "$env:TEMP\Create-BootableUSB" -Recurse -Force
    }

    Import-Module DISM

    $efi = $efiPartition | Select-Object -First 1 -ExpandProperty AccessPaths
    $retools = $reToolsPartition | Select-Object -First 1 -ExpandProperty AccessPaths
    $recovery = $recoveryImagePartition | Select-Object -First 1 -ExpandProperty AccessPaths
    $windows = $windowsPartition | Select-Object -First 1 -ExpandProperty AccessPaths

    New-Item -ItemType Directory "$env:TEMP\Create-BootableUSB" -Force | Out-Null
    Start-Sleep -Seconds 1

    cmd.exe /c "mklink /D `"$env:TEMP\Create-BootableUSB\efi`" `"$efi`""
    cmd.exe /c "mklink /D `"$env:TEMP\Create-BootableUSB\retools`" `"$retools`""
    cmd.exe /c "mklink /D `"$env:TEMP\Create-BootableUSB\recovery`" `"$recovery`""
    cmd.exe /c "mklink /D `"$env:TEMP\Create-BootableUSB\windows`" `"$windows`""

    $efi = "$env:TEMP\Create-BootableUSB\efi"
    $retools = "$env:TEMP\Create-BootableUSB\retools"
    $recovery = "$env:TEMP\Create-BootableUSB\recovery"
    $windows = "$env:TEMP\Create-BootableUSB\windows"

    New-Item -ItemType Directory "$recovery\RecoveryImage" -Force | Out-Null
    New-Item -ItemType Directory -Path "$retools\Recovery\WindowsRE" -Force | Out-Null
    Start-Sleep -Seconds 1

    $output = "Copy '$($SyncHash.IsoDrive)`:\sources\install.wim' to '$recovery\RecoveryImage\install.wim'"
    $SyncHash.WriteOutput.Invoke($output, $Error)
    $Error.Clear()

    Copy-Item -Path "$($SyncHash.IsoDrive)`:\sources\install.wim" -Destination "$recovery\RecoveryImage\install.wim"

    $output = "DISM: Deploy '$($SyncHash.IsoDrive)`:\sources\install.wim' to $windows"
    $SyncHash.WriteOutput.Invoke($output, $Error)
    $Error.Clear()

    $output = (cmd /c "dism /Apply-Image /ImageFile:$($SyncHash.IsoDrive)`:\sources\install.wim /Index:$($SyncHash.SelectedOSEdition.ImageIndex) /ApplyDir:$windows 2>&1" | Out-String).Trim() + "`r`n`r`n"

    $output += "Copy '$windows\Windows\System32\Recovery\winre.wim' to '$retools\Recovery\WindowsRE\winre.wim'"
    $SyncHash.WriteOutput.Invoke($output, $Error)
    $Error.Clear()

    Copy-Item -Path "$windows\Windows\System32\Recovery\winre.wim" -Destination "$retools\Recovery\WindowsRE\winre.wim"

    $output = "Updating boot code and configure Windows Recovery Environment . . ."
    $SyncHash.WriteOutput.Invoke($output, $Error)
    $Error.Clear()

    Add-PartitionAccessPath -DiskNumber $windowsPartition.DiskNumber -PartitionNumber $windowsPartition.PartitionNumber -AssignDriveLetter
    $WinDrive = Get-Partition -DiskNumber $windowsPartition.DiskNumber -PartitionNumber $windowsPartition.PartitionNumber | Select-Object -ExpandProperty DriveLetter

    Add-PartitionAccessPath -DiskNumber $efiPartition.DiskNumber -PartitionNumber $efiPartition.PartitionNumber -AssignDriveLetter
    $efiDrive = Get-Partition -DiskNumber $efiPartition.DiskNumber -PartitionNumber $efiPartition.PartitionNumber | Select-Object -ExpandProperty DriveLetter

    Start-Sleep -Seconds 4

    $output  = (cmd /c "bcdboot `"$WinDrive`:\Windows`" /s $efiDrive`: /f UEFI 2>&1" | Out-String).Trim() + "`r`n`r`n"
    $output += (cmd /c "$WinDrive`:\Windows\System32\reagentc /setosimage /path $recovery\RecoveryImage /target $WinDrive`:\Windows /index $($SyncHash.SelectedOSEdition.ImageIndex) 2>&1" | Out-String).Trim() + "`r`n`r`n"
    $output += (cmd /c "$WinDrive`:\Windows\System32\reagentc /setreimage /path $retools\Recovery\WindowsRE /target $WinDrive`:\Windows 2>&1" | Out-String).Trim() + "`r`n`r`n"

    # Enable Windows RE
    $output += (cmd /c "$winDrive`:\Windows\System32\reagentc /enable /target $WinDrive`:\Windows 2>&1" | Out-String).Trim() + "`r`n`r`n"

    Start-Sleep -Seconds 2

    # Remove-PartitionAccessPath -DiskNumber $windowsPartition.DiskNumber -PartitionNumber $windowsPartition.PartitionNumber -AccessPath "$WinDrive`:\"
    Remove-PartitionAccessPath -DiskNumber $efiPartition.DiskNumber -PartitionNumber $efiPartition.PartitionNumber -AccessPath "$efiDrive`:\"

    if ($DataPartition) {
        Add-PartitionAccessPath -DiskNumber $DataPartition.DiskNumber -PartitionNumber $DataPartition.PartitionNumber -AssignDriveLetter
    }

    # Dismount-DiskImage -ImagePath $File

    $output += "Finished!"
    $SyncHash.WriteOutput.Invoke($output, $Error)
    $Error.Clear()

    # Enable GUI objects after completion
    $SyncHash.Window.Dispatcher.Invoke([action] {
        & $SyncHash.EnableValidObjects
        $SyncHash.OutputTextBox.AppendText("================ End: $((Get-Date).ToString("yyyy-MM-dd HH:mm:ss")) ================`r`n`r`n")
        $SyncHash.OutputTextBox.ScrollToEnd()
    })
}

# Define the background task that will execute in a new runspace.
$Background = {
    param ([Parameter(Mandatory=$true)] [string]$ClickedButton)

    # Create a new PowerShell instance and add particular scriptblock to it.

    if ($ClickedButton -eq "ButtonCheckUpdate" -or $ClickedButton -eq "ButtonUpdate") {
        $psInstance = [PowerShell]::Create().AddScript($ScriptUpdate)
        $psInstance.AddArgument($ClickedButton)
    }
    elseif ($ClickedButton -eq "GetImageHealth") {
        $psInstance = [PowerShell]::Create().AddScript($GetImageHealth)
    }
    elseif ($ClickedButton -eq "GetFileHash") {
        $psInstance = [PowerShell]::Create().AddScript($GetFileHash)
        $psInstance.AddArgument($SyncHash.FileHashComboBox.Text)
    }
    elseif ($ClickedButton -eq "CreateBootableDrive") {
        $psInstance = [PowerShell]::Create().AddScript($CreateBootableDrive)
    }
    elseif ($ClickedButton -eq "InstallWindowsOnDrive") {
        $PartitionSize = @{
            efi = [int64]$SyncHash.PartitionEFI.Text * 1MB
            msr = [int64]$SyncHash.PartitionMSR.Text * 1MB
            retools = [int64]$SyncHash.PartitionReTools.Text * 1MB
            recovery = [int64]$SyncHash.PartitionRecovery.Text * 1MB
            windows = $SyncHash.PartitionWindows.Text
        }

        if ($SyncHash.PartitionWindows.Text -ne "max") {
            $PartitionSize.windows = [int64]$SyncHash.PartitionWindows.Text * 1MB
        }

        $psInstance = [PowerShell]::Create().AddScript($InstallWindowsOnDrive)
        $psInstance.AddArgument($PartitionSize)
    }

    # Configure a new runspace for the PowerShell instance
    $runspace = [RunspaceFactory]::CreateRunspace()
    $runspace.ApartmentState = "STA"
    $runspace.ThreadOptions = "ReuseThread"
    $runspace.Open()

    # Set variables for the runspace
    $runspace.SessionStateProxy.SetVariable("SyncHash", $SyncHash)

    # Assign the runspace to the PowerShell instance and begin execution
    $psInstance.Runspace = $runspace
    $psInstance.BeginInvoke()
}

$HtmlBootableUSB = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Bootable USB Guide</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            font-size: 14px;
            line-height: 1.4;
            margin: 0; /* Remove default margin */
            padding: 5px; /* Add padding for content spacing */
        }
        pre {
            background-color: #f8f9fa;
            padding: 5px;
            border: 1px solid #ddd;
            white-space: pre-wrap; /* Enable text wrapping */
            word-wrap: break-word; /* Prevent horizontal scrolling */
            margin: 1px 0; /* Margin to separate code blocks */
            padding-left: 5px; /* Add left padding to the code block for visibility */
        }
    </style>
</head>
<body>
    <h2>Create a Bootable USB Drive</h2>
    <ul>
        <li>Key Point: FAT32 is required for booting (supports BIOS and UEFI).</li>
    </ul>

    <h3>Prerequisites</h3>
    <ul>
        <li>Administrative permissions are required.</li>
        <li>Run these commands in an elevated Command Prompt (Run CMD as Admin).</li>
    </ul>

    <h3>Step 1: Prepare the USB Drive</h3>
    <ul>
        <li>Open Command Prompt as Administrator.</li>
        <li>Enter these commands. Replace <code>#</code> with your USB drive's number:</li>
    </ul>
    <pre>
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
    </pre>
    <p><strong>Note:</strong> Use FAT32 for compatibility with both BIOS and UEFI. Avoid NTFS.</p>

    <h3>Step 2: Copy Installation Files</h3>
    <p>Assuming:</p>
    <ul>
        <li><code>D:</code> is the source (mounted ISO).</li>
        <li><code>E:</code> is the USB drive.</li>
    </ul>
    <p>Run the following commands:</p>
    <ul>
        <li>Make the USB bootable:</li>
    </ul>
    <pre>D:\boot\bootsect.exe /nt60 E:</pre>
    <ul>
        <li>Copy installation files:</li>
    </ul>
    <pre>robocopy D:\ E:\ /e /max:4294967296</pre>
    <ul>
        <li>Split the large <code>.wim</code> file:</li>
    </ul>
    <pre>Dism /Split-Image /ImageFile:D:\sources\install.wim /SWMFile:E:\sources\install.swm /FileSize:4096</pre>

    <h3>For USB Drives Over 32GB</h3>
    <p>Follow these steps for drives larger than 32GB:</p>
    <ul>
        <li>Open Command Prompt as Administrator.</li>
        <li>Replace <code>#</code> with your USB drive number and adjust the size (e.g., 12GB = 12288 MB):</li>
    </ul>
    <pre>
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
    </pre>
    <ul>
        <li>Then follow same instructions described in <strong>Step 2</strong>.</li>
    </ul>
</body>
</html>
"@

$HtmlInstallWindow = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Install Windows on a Portable USB Drive</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            font-size: 14px;
            line-height: 1.4;
            margin: 0;
            padding: 5px;
        }
        pre {
            background-color: #f8f9fa;
            padding: 5px;
            border: 1px solid #ddd;
            white-space: pre-wrap;
            word-wrap: break-word;
            margin: 1px 0;
            padding-left: 5px;
        }
    </style>
</head>
<body>

    <h2>Install Windows on a Portable USB Drive</h2>

    <p>This guide will help you install Windows on a portable USB drive.</p>

    <h3>Prerequisites:</h3>
    <ul>
        <li>USB drive with at least 32 GB size. HDD or SSD is highly recommended.</li>
        <li>A Windows ISO file. You can download official versions here:</li>
        <ul>
            <li><a href="https://www.microsoft.com/en-us/software-download/windows10" target="_blank">Microsoft Windows 10</a></li>
            <li><a href="https://www.microsoft.com/en-us/software-download/windows11" target="_blank">Microsoft Windows 11</a></li>
        </ul>
        <li>A computer running Windows with Administrative privileges.</li>
    </ul>

    <h3>Step 1: Prepare the USB Drive</h3>
    <p>First, we will format and prepare the USB drive to make it bootable. Follow these commands carefully:</p>
    
    <p>Open Command Prompt as Administrator and run the following commands (replace <strong>X</strong> with the correct disk number for your USB drive):</p>

    <pre>
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
    </pre>

    <h4>Explanation of Step 1:</h4>
    <ul>
        <li><strong>diskpart</strong>: Launches the disk partitioning tool to manage disk partitions.</li>
        <li><strong>list disk</strong>: Displays all available disks. Identify your USB drive by its size.</li>
        <li><strong>select disk X</strong>: Selects the USB drive. Replace <strong>X</strong> with the disk number corresponding to your USB drive.</li>
        <li><strong>clean</strong>: Deletes all existing data and partitions from the USB drive, preparing it for new partitions.</li>
        <li><strong>convert gpt</strong>: Converts the drive to the GPT partition style, which is required for UEFI booting.</li>
        <li><strong>create partition efi size=256</strong>: Creates a 256 MB EFI (Extensible Firmware Interface) partition required for UEFI booting.</li>
        <li><strong>format quick fs=fat32 label="System"</strong>: Formats the EFI partition with the FAT32 file system, which is compatible with UEFI.</li>
        <li><strong>assign letter="S"</strong>: Assigns a letter ("S") to the EFI partition for easier access.</li>
        <li><strong>create partition msr size=512</strong>: Creates a Microsoft Reserved Partition (MSR) of 512 MB. This partition is used for system recovery tools.</li>
        <li><strong>create partition primary size=1024</strong>: Creates a 1 GB partition for Windows Recovery Tools.</li>
        <li><strong>create partition primary size=8192</strong>: Creates an 8 GB partition for the recovery image. This is used for Windows system recovery files.</li>
        <li><strong>create partition primary size=132000</strong>: Creates a 128 GB partition for the Windows operating system installation files. Adjust the size as needed.</li>
        <li><strong>list volume</strong>: Lists all the partitions and ensures that all partitions were created successfully.</li>
        <li><strong>exit</strong>: Exits the diskpart tool and saves the partition setup.</li>
    </ul>

    <h3>Step 2: Deploy Windows Installation</h3>
    <p>Once your USB drive is ready, we will apply the Windows image to it. Follow these steps:</p>
    
    <p>First, mount the ISO file to a virtual drive (e.g., drive <strong>D:</strong>), then open Command Prompt as Administrator and run the following commands:</p>

    <pre>
dism /Get-WimInfo /WimFile:D:\sources\install.wim
md R:\RecoveryImage
copy D:\sources\install.wim R:\RecoveryImage\install.wim

dism /Apply-Image /ImageFile:R:\RecoveryImage\install.wim /Index:5 /ApplyDir:W:\

md T:\Recovery\WindowsRE
copy W:\Windows\System32\Recovery\winre.wim T:\Recovery\WindowsRE\winre.wim

bcdboot W:\Windows /s S: /f UEFI
W:\Windows\System32\reagentc /setosimage /path R:\RecoveryImage /target W:\Windows /index 5
W:\Windows\System32\reagentc /setreimage /path T:\Recovery\WindowsRE /target W:\Windows
    </pre>

    <h4>Explanation of Step 2:</h4>
    <ul>
        <li><strong>dism /Get-WimInfo</strong>: Displays information about the Windows image in the install.wim file. This helps you identify the correct Windows edition (e.g., Pro, Home).</li>
        <li><strong>md R:\RecoveryImage</strong>: Creates a folder on the USB drive where the recovery image will be stored.</li>
        <li><strong>copy D:\sources\install.wim</strong>: Copies the Windows installation image (install.wim) from the mounted ISO to the USB drive.</li>
        <li><strong>dism /Apply-Image</strong>: Applies the selected Windows image to the Windows partition on the USB drive. Index 5 typically corresponds to the Windows Pro edition.</li>
        <li><strong>md T:\Recovery\WindowsRE</strong>: Creates a folder for Windows Recovery Environment (WinRE) on the USB drive.</li>
        <li><strong>copy W:\Windows\System32\Recovery\winre.wim</strong>: Copies the WinRE image from the Windows partition to the recovery partition on the USB drive.</li>
        <li><strong>bcdboot</strong>: Configures the USB drive to boot Windows in UEFI mode by copying the boot files to the EFI partition.</li>
        <li><strong>reagentc /setosimage</strong>: Registers the recovery image location to the USB drive.</li>
        <li><strong>reagentc /setreimage</strong>: Registers the location of the Windows Recovery Environment (WinRE) image.</li>
    </ul>

</body>
</html>
"@

# Define the XAML layout for the WPF window
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Create-BootableUSB | Create bootable USB Drive or install Windows on it." Width="800" Height="600" ResizeMode="NoResize" WindowStartupLocation="CenterScreen" ShowInTaskbar="True">

    <Window.TaskbarItemInfo> 
        <TaskbarItemInfo/>
    </Window.TaskbarItemInfo>

    <Grid>
        <!-- Tab Control -->
        <TabControl VerticalAlignment="Top" Margin="0,0,0,0">
            <!-- First Main Tab -->
            <TabItem Header="General">
                <StackPanel Margin="5" HorizontalAlignment="Left">
                    <!-- Drive Selection -->
                    <TextBlock Text="Select Target Drive" Margin="0,0,0,5"/>
                    <StackPanel Orientation="Horizontal" Margin="0,0,0,10">
                        <ComboBox x:Name="DriveComboBox" Width="660" Height="25"/>
                        <Button x:Name="RefreshButton" Content="Refresh" Width="75" Height="25" Margin="25,0,0,0"/>
                    </StackPanel>

                    <StackPanel Orientation="Horizontal" Margin="0,0,0,0">
                        <TextBlock Text="Select ISO Image" Margin="0,0,0,0"/>
                        <TextBlock Text="Hash Algorithm" Margin="50,0,0,0"/>
                        <TextBlock Margin="80,0,0,0">
                            <Run Text="Select Edition. Applies to '"/> <Run Text="Install Windows on Drive" FontWeight="Bold"/> <Run Text="' only!"/>
                        </TextBlock>
                    </StackPanel>

                    <!-- ISO Selection -->
                    <StackPanel Orientation="Horizontal" HorizontalAlignment="Left" Margin="0,5,0,5">
                        <Button x:Name="BrowseButton" Content="Browse" Width="100" Height="25" Margin="0,0,0,0"/>
                        <ComboBox x:Name="FileHashComboBox" Width="120" Height="25" Margin="40,0,0,0">
                            <ComboBoxItem Content="MD5"/>
                            <ComboBoxItem Content="SHA1"/>
                            <ComboBoxItem Content="SHA256"/>
                            <ComboBoxItem Content="SHA384"/>
                            <ComboBoxItem Content="SHA512"/>
                        </ComboBox>
                        <ComboBox x:Name="OSEditionsComboBox" Width="360" Height="25" Margin="40,0,0,0"/>
                    </StackPanel>

                    <!-- Show File Path -->
                    <StackPanel Orientation="Horizontal">
                        <TextBlock x:Name="IsoPathText" Text="Selected: [None]" Margin="0,0,0,0"/>
                    </StackPanel>

                    <!-- Start Buttons -->
                    <StackPanel Orientation="Horizontal" Margin="0,10,0,0">
                        <Button x:Name="FileHashButton" Content="Get Hash" Width="75" Height="25" Margin="0,0,0,0"/>
                        <Button x:Name="ButtonBootable" Content="Create Bootable Drive" Width="130" Height="25" Margin="50,0,0,0"/>
                        <Button x:Name="ButtonInstall" Content="Install Windows on Drive" Width="160" Height="25" Margin="50,0,0,0"/>
                    </StackPanel>

                    <!-- Big Text Box-->
                    <StackPanel Margin="0, 10, 0, 0" HorizontalAlignment="Left">
                        <TextBox x:Name="OutputTextBox" Width="765" Height="355" Margin="0,0,0,10" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto" AcceptsReturn="True" IsReadOnly="True"/>
                    </StackPanel>
                </StackPanel>
            </TabItem>

            <!-- Second Main Tab -->
            <TabItem Header="Options">
                <StackPanel Margin="10" HorizontalAlignment="Left">
                    <!-- Five TextBoxes with labels above each box -->
                    <TextBlock Text="Values in MB for each partition of Windows Preinstallation Environment" Margin="0,0,0,10"/>
                    <StackPanel Orientation="Horizontal" HorizontalAlignment="Left" Margin="0,0,0,10">
                        <StackPanel>
                            <TextBlock Text="EFI" HorizontalAlignment="Center" Margin="5,0"/>
                            <TextBox x:Name="PartitionEFI" Width="60" Height="20" Margin="5,0"/>
                        </StackPanel>
                        <StackPanel>
                            <TextBlock Text="MSR" HorizontalAlignment="Center" Margin="5,0"/>
                            <TextBox x:Name="PartitionMSR" Width="60" Height="20" Margin="5,0"/>
                        </StackPanel>
                        <StackPanel>
                            <TextBlock Text="RE Tools" HorizontalAlignment="Center" Margin="5,0"/>
                            <TextBox x:Name="PartitionReTools" Width="60" Height="20" Margin="5,0"/>
                        </StackPanel>
                        <StackPanel>
                            <TextBlock Text="Recovery" HorizontalAlignment="Center" Margin="5,0"/>
                            <TextBox x:Name="PartitionRecovery" Width="60" Height="20" Margin="5,0"/>
                        </StackPanel>
                        <StackPanel>
                            <TextBlock Text="Windows" HorizontalAlignment="Center" Margin="5,0"/>
                            <TextBox x:Name="PartitionWindows" Width="60" Height="20" Margin="5,0"/>
                        </StackPanel>
                    </StackPanel>
                </StackPanel>
            </TabItem>

            <TabItem Header="Know-How">
                <Grid>
                    <TabControl>
                        <TabItem Header="Bootable USB">
                            <Grid>
                                <WebBrowser x:Name="HtmlBootableUSB" HorizontalAlignment="Stretch" VerticalAlignment="Stretch"/>
                            </Grid>
                        </TabItem>
                        <TabItem Header="Install Windows">
                            <Grid>
                                <WebBrowser x:Name="HtmlInstallWindow" HorizontalAlignment="Stretch" VerticalAlignment="Stretch"/>
                            </Grid>
                        </TabItem>
                    </TabControl>
                </Grid>
            </TabItem>

            <!-- Fourth Main Tab -->
            <TabItem Header="Support">
                <StackPanel Orientation="Vertical" HorizontalAlignment="Left" Margin="0,0,0,0">
                    <!-- Row with TextBlock and Buttons -->
                    
                        <TextBlock Margin="5,5,0,0">
                            <TextBlock.Inlines>
                                <Run x:Name="ScriptVersion" Text=""/>
                                <LineBreak/>
                                <Run x:Name="ScriptDeveloper" Text=""/>
                                <LineBreak />
                                <Run Text="Repository: "/>
                                <Hyperlink x:Name="ScriptRepo" NavigateUri=""> <Run Text=""/> </Hyperlink>
                            </TextBlock.Inlines>
                        </TextBlock>

                    <StackPanel Orientation="Horizontal" Margin="0,20,0,0">
                        <Button x:Name="ButtonCheckUpdate" Content="Check For Update" Width="130" Height="25" Margin="50,0,10,0"/>
                        <Button x:Name="ButtonUpdate" Content="Update" Width="130" Height="25" Margin="50,0,0,0"/>
                    </StackPanel>

                    <TextBox x:Name="TextBoxUpdate" Width="770" Height="410" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" TextWrapping="Wrap" AcceptsReturn="True" IsReadOnly="True" HorizontalAlignment="Left" Margin="5,20,0,10"/>
                </StackPanel>
            </TabItem>

        </TabControl>
    </Grid>
</Window>
"@

# Set custom icon using base64-encoded data
$IconBase64 = "iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAACXEAAAlxAYZ2/isAAAAZdEVYdFNvZnR3YXJlAHd3dy5pbmtzY2FwZS5vcmeb7jwaAAABh2lUWHRYTUw6Y29tLmFkb2JlLnhtcAAAAAAAPD94cGFj
a2V0IGJlZ2luPSfvu78nIGlkPSdXNU0wTXBDZWhpSHpyZVN6TlRjemtjOWQnPz4NCjx4OnhtcG1ldGEgeG1sbnM6eD0iYWRvYmU6bnM6bWV0YS8iPjxyZGY6UkRGIHhtbG5zOnJkZj0iaHR0cDovL3d3dy53My5vcmcvMTk5OS8wMi8yMi1yZGYtc3ludGF4LW5zIyI+PHJkZjpEZXNjcmlwdGl
vbiByZGY6YWJvdXQ9InV1aWQ6ZmFmNWJkZDUtYmEzZC0xMWRhLWFkMzEtZDMzZDc1MTgyZjFiIiB4bWxuczp0aWZmPSJodHRwOi8vbnMuYWRvYmUuY29tL3RpZmYvMS4wLyI+PHRpZmY6T3JpZW50YXRpb24+MTwvdGlmZjpPcmllbnRhdGlvbj48L3JkZjpEZXNjcmlwdGlvbj48L3JkZjpSRE
Y+PC94OnhtcG1ldGE+DQo8P3hwYWNrZXQgZW5kPSd3Jz8+LJSYCwAABNtJREFUWEedlluIVlUUx39r7++cbxwdR9TEaxfNGKjIQDFDfEpKDF+iAnsQgh6NHooIH8IevFDRQyoh+KJUUPYQmRBdyS4PQUQEmvoQBV6SUcdxZr7L2Wv1sM83frPnm3G+/rDhcPa6/Nd/rb3PgS4QDskePepO6xG/J
d37v3Dpi+lgKudFZEDgpL7n37d3mJfadIuuCDjTT8Mg1xgDydiuuTulB7g3tesG3RHYyaCYfY+HcB2clwfAf6Pvcl9qO1N0RQAAld8wQCHcABFZYYU/cf1t5qemM0HXBAS5jgqogAk6DC6X1X2hcii1nQm6JxBsMQGkXCjYDXA5z+qbfmtqfzt0TUCbsp5mqUC5LAgUAk3Zb99SSX2mQ1cEbG91
JcgGxmLl7ctGQapyv/2cPQ2ge/Inw57K8TRGiq4IaENfchlVLYAwcVkAGmBNXiS2aqOb757S3ZWX0zjtkPRFC7qfPkazV5nT3OteYUTfyB4E+YVA1TS1jnASubgsPGZNd9DlMmBKvRFY07O7cSa1Z1oFbvq1Mt/tYijbCmCFHBOhakUpewBaz+XSAE4Rq/uPnMmAjoJ4qlmwt9LwLUxJIAT/HHU
wlW1hV37MVXhIR8pkTaBq2IIQSZSnAY2tcLDACsDAboLzstV2VTamOZiqBfo6i6yen3MiczGgAtpoMzCwpQXMVuRyBYbcNKWA6wWt8bHfV39m0l76AkBq+fMud3O1GSuyWpvUDaBfYZZBIdi8WHK7CpPWGFDwhL7GHWmuSQR0J1UteIG6jUtq7clna5Q+RCXIwPpDbEtrNhIy1gSX00czfzTNN4
kAWXWT824ldUFCuVSQhsAsw5aEmLgFBeYqUuGWLYIU5XMQCALmQGVtmyd0JBB4HJF4rtsr7zFsRQG+rLyFlgqzDWqC9Sq6qgEVu6WKjp+YVW2e0JmArJnkmBt6V5lcU4cSszTKPT9EsovKNrXiBKApt58BVBZGAi3pBF1RQB5noiMMrGrY8gL6DOqC9Sv0GuPfjUIgSE/q2oEAMs64IXHg+jQqM
RW0bFGragBnkUQRr0cMLJ6HCZhMoOBG/MqVQRaEqEQnWDIP7QqZYHMUpFQuFnW1zQI6EjDOIhKly+KNNyFJC63+piRaUCCzODdFbKUYZ1OzyQQK+Y7yZ8O8RYs0QQCqwCbgkWlIuHjXSojXdzB3qpPJRKg/qWM2hJS9S2HlBb4eWAbcCSwqT0snBMAJWre//dDID+n2JALu2PCgqBwmE2TMxcDt
I9AAVgFLyyvWgOUdFBBiG2sOvCDKQXd8JkMIUPX7rMYFaTgYduDL6FZKf09bxQWwGOhNhtAbMuSQIFjNzklv/4G23XF0JOCO3Lgq2A4KwV+q3LIKQB8wp3ymTDoHWNFGSiJZdynDAk0s7JDDF0fL3QnoSABAPhj5ypQdXMzwV7J4GiBOdeoVgLuBvFQpN/zFHLviA8p292Ht58RjHGmoCXDHh4/
aGNvs9/yiH6ngZxuMlnPQPhdatqAKvsfw1yrYH9k/1MJWd/zmtD+m0xIAcCeGP+N0vs5+7DmsF7JRb4IfBN8H4uLyc8GPgldB/8qH7aeeA5yxde7z0S/SeCmmuOI6QwcWLmHLzc22tNjMBn3YlrEaj8pl+VNOya+cr3zJJ/1fu8uX/019p8J/1/I5z3bW5gMAAAAASUVORK5CYII="

# Create a streaming image by streaming the base64 string to a bitmap streamsource
$bitmap = New-Object System.Windows.Media.Imaging.BitmapImage
$bitmap.BeginInit()
$bitmap.StreamSource = [System.IO.MemoryStream][System.Convert]::FromBase64String(($IconBase64 -replace "\s+"))
$bitmap.EndInit()
$bitmap.Freeze()

# Create synchronized hashtable to share data between different threads or runspaces
$SyncHash = [Hashtable]::Synchronized(@{})

# Load the XAML and bind controls
$XmlReader = New-Object System.Xml.XmlNodeReader $xaml

# Retrieve WPF elements
$SyncHash.Window = [System.Windows.Markup.XamlReader]::Load($XmlReader)

# Set custom icon in the window
$SyncHash.Window.Icon = $bitmap

# Set custom icon in the taskbar
$SyncHash.Window.TaskbarItemInfo = New-Object System.Windows.Shell.TaskbarItemInfo
$SyncHash.Window.TaskbarItemInfo.Overlay = $bitmap
$SyncHash.Window.TaskbarItemInfo.Description = $SyncHash.Window.Title

$SyncHash.DriveComboBox = $SyncHash.Window.FindName("DriveComboBox")
$SyncHash.RefreshButton = $SyncHash.Window.FindName("RefreshButton")
$SyncHash.BrowseButton = $SyncHash.Window.FindName("BrowseButton")
$SyncHash.FileHashComboBox = $SyncHash.Window.FindName("FileHashComboBox")
$SyncHash.FileHashButton = $SyncHash.Window.FindName("FileHashButton")
$SyncHash.IsoPathText = $SyncHash.Window.FindName("IsoPathText")
$SyncHash.ButtonBootable = $SyncHash.Window.FindName("ButtonBootable")
$SyncHash.ButtonInstall = $SyncHash.Window.FindName("ButtonInstall")
$SyncHash.OSEditionsComboBox = $SyncHash.Window.FindName("OSEditionsComboBox")
$SyncHash.PartitionEFI = $SyncHash.Window.FindName("PartitionEFI")
$SyncHash.PartitionMSR = $SyncHash.Window.FindName("PartitionMSR")
$SyncHash.PartitionReTools = $SyncHash.Window.FindName("PartitionReTools")
$SyncHash.PartitionRecovery = $SyncHash.Window.FindName("PartitionRecovery")
$SyncHash.PartitionWindows = $SyncHash.Window.FindName("PartitionWindows")
$SyncHash.OutputTextBox = $SyncHash.Window.FindName("OutputTextBox")
$SyncHash.HtmlBootableUSB = $SyncHash.Window.FindName("HtmlBootableUSB")
$SyncHash.HtmlInstallWindow = $SyncHash.Window.FindName("HtmlInstallWindow")
$SyncHash.ScriptVersion = $SyncHash.Window.FindName("ScriptVersion")
$SyncHash.ScriptDeveloper = $SyncHash.Window.FindName("ScriptDeveloper")
$SyncHash.ScriptRepo = $SyncHash.Window.FindName("ScriptRepo")
$SyncHash.ButtonCheckUpdate = $SyncHash.Window.FindName("ButtonCheckUpdate")
$SyncHash.ButtonUpdate = $SyncHash.Window.FindName("ButtonUpdate")
$SyncHash.TextBoxUpdate = $SyncHash.Window.FindName("TextBoxUpdate")

$SyncHash.FileHashComboBox.SelectedIndex = 2
$SyncHash.PartitionEFI.Text = "256"
$SyncHash.PartitionMSR.Text = "512"
$SyncHash.PartitionReTools.Text = "1024"
$SyncHash.PartitionRecovery.Text = "8192"
$SyncHash.PartitionWindows.Text = "max"

$SyncHash.HtmlBootableUSB.NavigateToString($HtmlBootableUSB)
$SyncHash.HtmlInstallWindow.NavigateToString($HtmlInstallWindow)

# Initialize variables and pbjects to share between threads
$SyncHash.Drives = $null
$SyncHash.OSEditions = $null
$SyncHash.SelectedOSEdition = $null
$SyncHash.SelectedDrive = $null
$SyncHash.IsoPath = $null
$SyncHash.IsoDrive = $null

$SyncHash.ScriptInfo = @{
    LocalPath = $MyInvocation.MyCommand.Path
    Name = "Create-BootableUSB"
    Version= "1.03"
    Website = "https://github.com/ourshell/"
    Json = "https://raw.githubusercontent.com/ourshell/Create-BootableUSB/refs/heads/main/info.json"
    Content = "https://raw.githubusercontent.com/ourshell/Create-BootableUSB/refs/heads/main/Create-BootableUSB.ps1"
    Repository = "https://github.com/ourshell/Create-BootableUSB"
    Developer = "Boris Andonov"
}

$SyncHash.ScriptVersion.Text = "Version: " + $SyncHash.ScriptInfo.Version
$SyncHash.ScriptDeveloper.Text = "Developer: " + $SyncHash.ScriptInfo.Developer

# Dynamically set the Hyperlink properties using the synced hashtable
$SyncHash.ScriptRepo.NavigateUri = [Uri]$SyncHash.ScriptInfo.Repository
$SyncHash.ScriptRepo.Inlines.Clear()
$SyncHash.ScriptRepo.Inlines.Add([Windows.Documents.Run]::new($SyncHash.ScriptInfo.Repository))

$SyncHash.DisableObjects = {
    # Disable GUI objects
    $SyncHash.DriveComboBox.IsEnabled = $false
    $SyncHash.RefreshButton.IsEnabled = $false
    $SyncHash.BrowseButton.IsEnabled = $false
    $SyncHash.FileHashComboBox.IsEnabled = $false
    $SyncHash.FileHashButton.IsEnabled = $false
    $SyncHash.OSEditionsComboBox.IsEnabled = $false
    $SyncHash.ButtonBootable.IsEnabled = $false
    $SyncHash.ButtonInstall.IsEnabled = $false
    $SyncHash.PartitionEFI.IsEnabled = $false
    $SyncHash.PartitionMSR.IsEnabled = $false
    $SyncHash.PartitionReTools.IsEnabled = $false
    $SyncHash.PartitionRecovery.IsEnabled = $false
    $SyncHash.PartitionWindows.IsEnabled = $false
    $SyncHash.ButtonCheckUpdate.IsEnabled = $false
    $SyncHash.ButtonUpdate.IsEnabled = $false
}

$SyncHash.EnableValidObjects = {
    # Enable GUI objects
    $SyncHash.DriveComboBox.IsEnabled = $true
    $SyncHash.RefreshButton.IsEnabled = $true
    $SyncHash.BrowseButton.IsEnabled = $true
    
    $SyncHash.PartitionEFI.IsEnabled = $true
    $SyncHash.PartitionMSR.IsEnabled = $true
    $SyncHash.PartitionReTools.IsEnabled = $true
    $SyncHash.PartitionRecovery.IsEnabled = $true
    $SyncHash.PartitionWindows.IsEnabled = $true

    $SyncHash.ButtonCheckUpdate.IsEnabled = $true
    $SyncHash.ButtonUpdate.IsEnabled = $true

    if ($SyncHash.IsoPath) {
        $SyncHash.FileHashComboBox.IsEnabled = $true
        $SyncHash.FileHashButton.IsEnabled = $true
    }
    else {
        $SyncHash.FileHashComboBox.IsEnabled = $false
        $SyncHash.FileHashButton.IsEnabled = $false
    }

    if ($SyncHash.OSEditionsComboBox.Items) {
        $SyncHash.OSEditionsComboBox.IsEnabled = $true
    }
    else {
        $SyncHash.OSEditionsComboBox.IsEnabled = $false
    }

    if ($SyncHash.IsoDrive -and ($SyncHash.DriveComboBox.SelectedIndex -ne -1)) {
        $SyncHash.ButtonBootable.IsEnabled = $true

        if ($SyncHash.OSEditionsComboBox.SelectedIndex -ne -1) {
            $SyncHash.ButtonInstall.IsEnabled = $true
        }
        else {
            $SyncHash.ButtonInstall.IsEnabled = $false
        }
    }
    else {
        $SyncHash.ButtonBootable.IsEnabled = $false
        $SyncHash.ButtonInstall.IsEnabled = $false
    }
}


# When $SyncHash.WriteOutput.Invoke($object) is called, PowerShell interpret $object as multiple arguments instead of a single array.
# Method Invoke() does not inherently preserve the array structure.
# Force the array to be passed as a single argument, include $null to match the expected parameter structure: $SyncHash.WriteOutput.Invoke(@($object, $null))

$SyncHash.WriteOutput = {
    param ($Object, $ErrorMessage)

    $Output = ($Object | Out-String).Trim() + "`r`n`r`n" + ($ErrorMessage.Exception.Message | Out-String).Trim()
    $Output = $Output.Trim() + "`r`n`r`n"

    if (-not [string]::IsNullOrWhiteSpace($Output)) {
        $SyncHash.Window.Dispatcher.Invoke([action] {
            $SyncHash.OutputTextBox.AppendText($Output)
            $SyncHash.OutputTextBox.ScrollToEnd()
        })
    }
}

$SyncHash.UpdateLog = {
    param ($Output, $ErrorMessage)

    $Output = ($Output | Out-String).Trim() + "`r`n`r`n" + ($ErrorMessage.Exception.Message | Out-String).Trim()
    $Output = $Output.Trim() + "`r`n`r`n"

    if (-not [string]::IsNullOrWhiteSpace($Output)) {
        $SyncHash.Window.Dispatcher.Invoke([action] {
            $SyncHash.TextBoxUpdate.AppendText($Output)
            $SyncHash.TextBoxUpdate.ScrollToEnd()
        })
    }
}

# Text Changed Events for Each TextBox
Function HandleTextChanged {
    param ($sender)

    # Replace non-digit characters in the TextBox
    if ($sender.Text -notmatch '^([0-9]+)$') {
        $sender.Text = $sender.Text -replace "\D", ""
    }
}

# Function to populate the USB ComboBox with available USB devices
Function RefreshUsbDevices {
    & $SyncHash.DisableObjects

    $SyncHash.DriveComboBox.Items.Clear()

    $SyncHash.Drives = Get-CimInstance -Class Win32_DiskDrive -Property Index, Size, Model, Caption, MediaType, InterfaceType | Where-Object { $_.Index -ne $Script:BootDiskIndex }

    if ($SyncHash.Drives) {
        foreach ($drive in $SyncHash.Drives) {
            # Create a new ComboBoxItem
            $ComboBoxItem = New-Object System.Windows.Controls.ComboBoxItem
            $ComboBoxItem.Content = "[$(($drive.Size / 1GB).ToString("F2")) GB]  $($drive.Model)"
        
            # Add a tooltip to the ComboBoxItem
            $ComboBoxItem.ToolTip = "$($drive.Caption) | $($drive.MediaType) | $($drive.InterfaceType)"

            # Add the ComboBoxItem to the ComboBox
            $SyncHash.DriveComboBox.Items.Add($ComboBoxItem) | Out-Null

            #$SyncHash.DriveComboBox.Items.Add("[$([int]($_.Size / 1GB)) GB]  $($_.Model)  [$($_.MediaType)]") | Out-Null
        }
    }

    if ($SyncHash.DriveComboBox.Items) {
        $SyncHash.DriveComboBox.SelectedIndex = 0
        $SyncHash.SelectedDrive = $SyncHash.Drives | Select-Object -Index $SyncHash.DriveComboBox.SelectedIndex
    }
    else {
        $SyncHash.SelectedDrive = $null
    }

    & $SyncHash.EnableValidObjects
}

# Find the boot disk to exclude it from the list of drives.
$BootPartition = Get-CimInstance -Class Win32_OperatingSystem | Select-Object -ExpandProperty SystemDrive
$BootDiskIndex = Get-Partition -DriveLetter $BootPartition.Split(":")[0] | Select-Object -ExpandProperty DiskNumber

# Initial load of USB devices
RefreshUsbDevices

# Event handler for refreshing the USB list
$SyncHash.RefreshButton.Add_Click({ RefreshUsbDevices })

# Update the selected disk based on dropdown selection
$SyncHash.DriveComboBox.Add_SelectionChanged({
    if ($SyncHash.DriveComboBox.SelectedIndex -ne -1) {
        # Fetch the exact disk object based on the selected index
        $SyncHash.SelectedDrive = $SyncHash.Drives | Select-Object -Index $SyncHash.DriveComboBox.SelectedIndex
    }
    else {
        $SyncHash.SelectedDrive = $null
    }

    & $SyncHash.EnableValidObjects
})

# Browse button click event to select an ISO file
$SyncHash.BrowseButton.Add_Click({
    $fileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $fileDialog.Filter = "ISO files (*.iso)|*.iso"
    
    # Show the dialog and check if the user selected a file
    if ($fileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        & $SyncHash.DisableObjects

        $SyncHash.IsoDrive = $null
        $SyncHash.OSEditions = $null
        $SyncHash.SelectedOSEdition = $null
        $SyncHash.OSEditionsComboBox.Items.Clear()

        $SyncHash.IsoPath = $fileDialog.FileName
        if ($SyncHash.IsoPath) {
            $SyncHash.IsoPathText.Text = "Selected: " + $SyncHash.IsoPath.Split("\")[-1]
        }

        $Background.Invoke("GetImageHealth")
    }
})

# Update the selected OS Edition based on dropdown selection
$SyncHash.OSEditionsComboBox.Add_SelectionChanged({
    if ($SyncHash.OSEditionsComboBox.SelectedIndex -ne -1) {
        $SyncHash.SelectedOSEdition = $SyncHash.OSEditions | Select-Object -Index $SyncHash.OSEditionsComboBox.SelectedIndex
    }
})

$SyncHash.FileHashButton.Add_Click({
    & $SyncHash.DisableObjects
    $Background.Invoke("GetFileHash")
})

$SyncHash.ButtonBootable.Add_Click({
    & $SyncHash.DisableObjects
    $Background.Invoke("CreateBootableDrive")
})

$SyncHash.ButtonInstall.Add_Click({
    & $SyncHash.DisableObjects
    $SyncHash.SelectedOSEdition = $SyncHash.OSEditions | Select-Object -Index $SyncHash.OSEditionsComboBox.SelectedIndex
    $Background.Invoke("InstallWindowsOnDrive")
})

# Attach TextChanged event handler for each TextBox
$SyncHash.PartitionEFI.Add_TextChanged({ HandleTextChanged $SyncHash.PartitionEFI })
$SyncHash.PartitionMSR.Add_TextChanged({ HandleTextChanged $SyncHash.PartitionMSR })
$SyncHash.PartitionReTools.Add_TextChanged({ HandleTextChanged $SyncHash.PartitionReTools })
$SyncHash.PartitionRecovery.Add_TextChanged({ HandleTextChanged $SyncHash.PartitionRecovery })

$SyncHash.PartitionWindows.Add_TextChanged({
    if ($SyncHash.PartitionWindows.Text -notmatch '^(m|ma|max|[0-9]+)$') {
        $SyncHash.PartitionWindows.Text = $PartitionWindows.Text -replace "\D", ""
    }
})

$SyncHash.PartitionEFI.Add_LostFocus({
    if (-not $SyncHash.PartitionEFI.Text) {
        $SyncHash.PartitionEFI.Text = "256"
    }
})

$SyncHash.PartitionMSR.Add_LostFocus({
    if (-not $SyncHash.PartitionMSR.Text) {
        $SyncHash.PartitionMSR.Text = "512"
    }
})

$SyncHash.PartitionReTools.Add_LostFocus({
    if (-not $SyncHash.PartitionReTools.Text) {
        $SyncHash.PartitionReTools.Text = "1024"
    }
})

$SyncHash.PartitionRecovery.Add_LostFocus({
    if (-not $SyncHash.PartitionRecovery.Text) {
        $SyncHash.PartitionRecovery.Text = "8192"
    }
})

$SyncHash.PartitionWindows.Add_LostFocus({
    if (-not $SyncHash.PartitionWindows.Text) {
        $SyncHash.PartitionWindows.Text = "max"
    }
    if ($SyncHash.PartitionWindows.Text -match '^(m|ma+)$') {
        $SyncHash.PartitionWindows.Text = "max"
    }
})

$SyncHash.ScriptRepo.Add_Click({ Start-Process $SyncHash.ScriptInfo.Repository })

$SyncHash.ButtonCheckUpdate.Add_Click({
    & $SyncHash.DisableObjects
    $Background.Invoke("ButtonCheckUpdate")
})

$SyncHash.ButtonUpdate.Add_Click({
    & $SyncHash.DisableObjects
    $Background.Invoke("ButtonUpdate")
})

if ($host.Name -eq "ConsoleHost") {
    Add-Type -MemberDefinition '[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow); [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();' -Name Win32 -Namespace Native
    $consoleHandle = [Native.Win32]::GetConsoleWindow()

    # Hide console window
    [Native.Win32]::ShowWindow($consoleHandle, 0) | Out-Null
}

# Show GUI window
$SyncHash.Window.ShowDialog() | Out-Null

# Unhide console window
if ($host.Name -eq "ConsoleHost") {
    [Native.Win32]::ShowWindow($consoleHandle, 5) | Out-Null
}
