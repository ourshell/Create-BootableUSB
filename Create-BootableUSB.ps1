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

# Logic to verify the image
$GetImageHealth = {
    $output = "================ Begin: $((Get-Date).ToString("yyyy-MM-dd HH:mm:ss")) ================`r`n`r`n"
    $output += "Operation: Get Image Health Hash" + "`r`n"
    $output += "Selected File: $($SyncHash.IsoPath)"

    $SyncHash.WriteOutput.Invoke($output, $Error)
    $Error.Clear()

    $Image = Get-DiskImage -ImagePath $SyncHash.IsoPath -ErrorVariable ImageError -ErrorAction SilentlyContinue

    if ($ImageError) {
        $output = "Corrupted Image: " + $SyncHash.IsoPath
        $SyncHash.WriteOutput.Invoke($output, $Error)
        $Error.Clear()
    }
    else {
        if ($Image.Attached) {
            $SyncHash.IsoDrive = $Image | Get-Volume | Select-Object -ExpandProperty DriveLetter
        }
        else {
            $Image = Mount-DiskImage $SyncHash.IsoPath
            $SyncHash.IsoDrive = $Image | Get-Volume | Select-Object -ExpandProperty DriveLetter
        }

        if (Test-Path -Path "$($SyncHash.IsoDrive)`:\sources\install.wim") {
            $SyncHash.OSEditions = Get-WindowsImage -ImagePath "$($SyncHash.IsoDrive)`:\sources\install.wim"
        }

        if ($SyncHash.OSEditions) {
            $SyncHash.Window.Dispatcher.Invoke([action] {
                foreach ($edition in $SyncHash.OSEditions) {
                    # Create a new ComboBoxItem
                    $ComboBoxItem = New-Object System.Windows.Controls.ComboBoxItem
                    $ComboBoxItem.Content = $edition.ImageName
        
                    # Add a tooltip to the ComboBoxItem
                    $ComboBoxItem.ToolTip = $edition.ImageDescription

                    # Add the ComboBoxItem to the ComboBox
                    $SyncHash.OSEditionsComboBox.Items.Add($ComboBoxItem) | Out-Null
                }
            })
        }
        else {
            $SyncHash.WriteOutput.Invoke("No Windows Editions found!`r`nIf it's Linux, VMware or other bootable ISO you can still burn it on a USB drive.", $Error)
            $Error.Clear()
        }
    }

    $SyncHash.WriteOutput.Invoke("Finished!", $Error)
    $Error.Clear()

    # Enable GUI objects after completion
    $SyncHash.Window.Dispatcher.Invoke([action] {
        if ($SyncHash.OSEditionsComboBox.Items) {
            $SyncHash.OSEditionsComboBox.SelectedIndex = 0
        }

        & $SyncHash.UpdateObjects
        $SyncHash.OutputTextBox.AppendText("================ End: $((Get-Date).ToString("yyyy-MM-dd HH:mm:ss")) ================`r`n`r`n")
        $SyncHash.OutputTextBox.ScrollToEnd()
    })
}

# Logic to get File Hash
$GetFileHash = {
    param ([string]$algorithm)

    $output = "================ Begin: $((Get-Date).ToString("yyyy-MM-dd HH:mm:ss")) ================`r`n`r`n"
    $output += "Operation: Get File Hash" + "`r`n"
    $output += "Selected File: $($SyncHash.IsoPath)" + "`r`n" + "Calculating Hash: $algorithm"
    $SyncHash.WriteOutput.Invoke($output, $Error)
    $Error.Clear()

    $hash = Get-FileHash -Path $SyncHash.IsoPath -Algorithm $algorithm

    $SyncHash.WriteOutput.Invoke($hash.Hash, $Error)
    $Error.Clear()

    # Enable GUI objects after completion
    $SyncHash.Window.Dispatcher.Invoke([action] {
        & $SyncHash.UpdateObjects
        $SyncHash.OutputTextBox.AppendText("================ End: $((Get-Date).ToString("yyyy-MM-dd HH:mm:ss")) ================`r`n`r`n")
        $SyncHash.OutputTextBox.ScrollToEnd()
    })
}

# Logic for Bootable USB
$CreateBootableDrive = {
    $output = "================ Begin: $((Get-Date).ToString("yyyy-MM-dd HH:mm:ss")) ================`r`n`r`n"
    $output += "Operation: Create Bootable (USB) Drive" + "`r`n"
    $output += "Selected Disk: $($SyncHash.SelectedDrive.Caption)`n"
    $output += "Selected Image: $($SyncHash.IsoPath)`n"
    $output += "Repartitioning the drive . . . "

    $SyncHash.WriteOutput.Invoke($output, $Error)
    $Error.Clear()

    if ($SyncHash.SelectedDrive.Size -le (32 * 1GB)) {
        $DrivePartition2 = $false

        $diskpart = (@"
select disk $($SyncHash.SelectedDrive.Index)
clean
create partition primary
select partition 1
active
format fs=fat32 quick
exit
"@ | diskpart.exe 2>&1)
    }
    else {
        $DrivePartition2 = $true

        $PartitionSize = $SyncHash.SelectedDrive.Size / 2
        if ($PartitionSize -le (32 * 1GB)) {
            $PartitionSize = [System.Math]::Floor($PartitionSize / 1MB)
        }
        else {
            $PartitionSize = 32 * 1024 # 32GB expressed in MB
        }

        $diskpart = (@"
select disk $($SyncHash.SelectedDrive.Index)
clean

create partition primary size=$PartitionSize
select partition 1
active
format fs=fat32 quick label="BOOT-FAT32"

create partition primary
select partition 2
format fs=ntfs quick label="DATA-NTFS"

exit
"@ | diskpart.exe 2>&1)

    }
    $output = "Done!" + "`r`n`r`n" + ($diskpart | Out-String).Trim() + "`r`n`r`n" + "Burning ISO Image . . ."

    $SyncHash.WriteOutput.Invoke($output, $Error)
    $Error.Clear()

    Start-Sleep -Seconds 2

    $FlashDrive = Get-Partition -DiskNumber $SyncHash.SelectedDrive.Index -PartitionNumber 1 | Select-Object -ExpandProperty DriveLetter

    if (-not $FlashDrive) {
        Add-PartitionAccessPath -DiskNumber $SyncHash.SelectedDrive.Index -PartitionNumber 1 -AssignDriveLetter
        $FlashDrive = Get-Partition -DiskNumber $SyncHash.SelectedDrive.Index -PartitionNumber 1 | Select-Object -ExpandProperty DriveLetter
    }

    if ($DrivePartition2) {
        $FlashDrive2 = Get-Partition -DiskNumber $SyncHash.SelectedDrive.Index -PartitionNumber 2 | Select-Object -ExpandProperty DriveLetter

        if (-not $FlashDrive2) {
            Add-PartitionAccessPath -DiskNumber $SyncHash.SelectedDrive.Index -PartitionNumber 2 -AssignDriveLetter
        }
    }

    if (Test-Path -Path "$($SyncHash.IsoDrive)`:\boot\bootsect.exe") {
        $output = "Updating the boot code from $FlashDrive`: to $($SyncHash.IsoDrive)`:"
        $SyncHash.WriteOutput.Invoke($output, $Error)
        $Error.Clear()

        $output = ((cmd /c "$($SyncHash.IsoDrive)`:\boot\bootsect.exe /nt60 $FlashDrive`: 2>&1") | Out-String).Trim()

        $SyncHash.WriteOutput.Invoke($output, $Error)
        $Error.Clear()
    }

    $source = "$($SyncHash.IsoDrive)`:\"
    $destination = "$FlashDrive`:\"
    $MaxSize = 4294967296  # 4 GB in bytes

    $output = "Copying files from $source to $destination"
    $SyncHash.WriteOutput.Invoke($output, $Error)
    $Error.Clear()

    $output = ""

    # Use Get-ChildItem to list files and directories, including subdirectories
    Get-ChildItem -Path $source -Recurse | ForEach-Object {
        # Construct the destination path
        $DestPath = Join-Path -Path $destination -ChildPath ($_.FullName -replace [regex]::Escape($source), "")

        if ($_.PSIsContainer) {
            # Write-Host "Create directory '$($_.FullName)'"
            New-Item -ItemType Directory -Path $DestPath | Out-Null
        }
        elseif ($_.Length -le $MaxSize) {
            # Write-Host "Copy file '$($_.FullName)' with size $($_.Length) bytes"
            Copy-Item -Path $_.FullName -Destination $DestPath | Out-Null
        }
        else {
            $output += "Skip file '$($_.FullName)' with size $($_.Length) bytes. The size is over 4GB for FAT32`r`n"
        }
    }

    $SyncHash.WriteOutput.Invoke($output, $Error)
    $Error.Clear()

    if ((Test-Path -Path "$($source)sources\install.wim") -and ((Get-Item -Path "$($source)sources\install.wim").Length -gt 4GB)) {
        $output = "DISM: Split file '$($source)sources\install.wim' to '$($destination)sources\install.swm'"
        $SyncHash.WriteOutput.Invoke($output, $Error)
        $Error.Clear()

        $dism = cmd /c "dism /Split-Image /ImageFile:$($source)sources\install.wim /SWMFile:$($destination)sources\install.swm /FileSize:4096 2>&1"
        $output = ($dism | Out-String).Trim()
        $SyncHash.WriteOutput.Invoke($output, $Error)
        $Error.Clear()
    }

    $SyncHash.WriteOutput.Invoke("Finished!", $Error)
    $Error.Clear()

    #### HEAVY CODE ENDS HERE ####

    # Enable GUI objects after completion
    $SyncHash.Window.Dispatcher.Invoke([action] {
        & $SyncHash.UpdateObjects
        $SyncHash.OutputTextBox.AppendText("================ End: $((Get-Date).ToString("yyyy-MM-dd HH:mm:ss")) ================`r`n`r`n")
        $SyncHash.OutputTextBox.ScrollToEnd()
    })

    #$DriveEject = New-Object -comObject Shell.Application
    #$DriveEject.Namespace(17).ParseName($destination).InvokeVerb("Eject")
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

    #### HEAVY CODE STARTS HERE ####

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

    #### HEAVY CODE ENDS HERE ####

    # Enable GUI objects after completion
    $SyncHash.Window.Dispatcher.Invoke([action] {
        & $SyncHash.UpdateObjects
        $SyncHash.OutputTextBox.AppendText("================ End: $((Get-Date).ToString("yyyy-MM-dd HH:mm:ss")) ================`r`n`r`n")
        $SyncHash.OutputTextBox.ScrollToEnd()
    })
}

# Define the background task that will execute in a new runspace.
$Background = {
    param ([Parameter(Mandatory=$true)] [string]$ClickedButton)

    # Create a new PowerShell instance and add particular scriptblock to it.

    if ($ClickedButton -eq "GetImageHealth") {
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
                        <TextBlock x:Name="IsoPathText" Text="Path: [EMPTY]" Margin="0,0,0,0"/>
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

            <!-- Third Main Tab -->
            <TabItem Header="Know-How">
                <StackPanel>
                    <TabControl>
                        <TabItem Header="Bootable USB">
                            <TextBox x:Name="KnowHowBootableUSB" Width="765" Height="505" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" TextWrapping="Wrap" AcceptsReturn="True" IsReadOnly="True" Margin="0,0,0,0"/>
                        </TabItem>
                        <TabItem Header="Install Windows">
                            <TextBox x:Name="KnowHowInstallWindows" Width="765" Height="505" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" TextWrapping="Wrap" AcceptsReturn="True" IsReadOnly="True" Margin="0,0,0,0"/>
                        </TabItem>
                    </TabControl>
                </StackPanel>
            </TabItem>

            <!-- Fourth Main Tab -->
            <TabItem Header="Support">
                <StackPanel Orientation="Vertical" HorizontalAlignment="Left" Margin="0,0,0,0">
                    <!-- Row with TextBlock and Buttons -->
                    
                        <TextBlock Margin="5,5,0,0">
                            <TextBlock.Inlines>
                                <Run Text="Version: 1.00 alpha" />
                                <LineBreak/>
                                <Run Text="Developer: Boris Andonov" />
                                <LineBreak />
                                <Run Text="Website: " />
                                <Hyperlink x:Name="WebsiteLink" NavigateUri="https://github.com/ourshell/">
                                    <Run Text="https://github.com/ourshell/" />
                                </Hyperlink>
                            </TextBlock.Inlines>
                        </TextBlock>

                    <StackPanel Orientation="Horizontal" Margin="0,20,0,0">
                        <Button x:Name="ButtonCheckUpdate" Content="Check For Update" Width="130" Height="25" Margin="50,0,10,0" />
                        <Button x:Name="ButtonUpdate" Content="Update" Width="130" Height="25" Margin="50,0,0,0" />
                    </StackPanel>

                    <TextBox x:Name="TextBoxUpdate" Width="770" Height="410" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" TextWrapping="Wrap" AcceptsReturn="True" IsReadOnly="True" HorizontalAlignment="Left" Margin="5,20,0,10"/>
                </StackPanel>
            </TabItem>




        </TabControl>
    </Grid>
</Window>
"@

# Create synchronized hashtable to share data between different threads or runspaces
$SyncHash = [Hashtable]::Synchronized(@{})

# Load the XAML and bind controls
$XmlReader = New-Object System.Xml.XmlNodeReader $xaml

# Retrieve WPF elements
$SyncHash.Window = [System.Windows.Markup.XamlReader]::Load($XmlReader)

# Set custom icon using base64-encoded data
$Base64 = "iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAACXEAAAlxAYZ2/isAAAAZdEVYdFNvZnR3YXJlAHd3dy5pbmtzY2FwZS5vcmeb7jwaAAABh2lUWHRYTUw6Y29tLmFkb2JlLnhtcAAAAAAAPD94cGFj
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

# Decode the Base64 string into binary data
$iconData = [Convert]::FromBase64String(($Base64 -replace "\s+"))

# Create a streaming image by streaming the base64 string to a bitmap streamsource
$bitmap = New-Object System.Windows.Media.Imaging.BitmapImage
$bitmap.BeginInit()
$bitmap.StreamSource = [System.IO.MemoryStream][System.Convert]::FromBase64String($Base64)
$bitmap.EndInit()
$bitmap.Freeze()

# Set custom icon in the window
$SyncHash.Window.Icon = $bitmap

# Set custom icon in the taskbar
$SyncHash.Window.TaskbarItemInfo = New-Object System.Windows.Shell.TaskbarItemInfo
$SyncHash.Window.TaskbarItemInfo.Overlay = $bitmap
$SyncHash.Window.TaskbarItemInfo.Description = $SyncHash.Window.Title

$SyncHash.DriveComboBox = $SyncHash.Window.FindName("DriveComboBox")
$SyncHash.BrowseButton = $SyncHash.Window.FindName("BrowseButton")
$SyncHash.RefreshButton = $SyncHash.Window.FindName("RefreshButton")
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
$SyncHash.KnowHowBootableUSB = $SyncHash.Window.FindName("KnowHowBootableUSB")
$SyncHash.KnowHowInstallWindows = $SyncHash.Window.FindName("KnowHowInstallWindows")
$SyncHash.TextBoxUpdate = $SyncHash.Window.FindName("TextBoxUpdate")

$SyncHash.FileHashComboBox.SelectedIndex = 2

$SyncHash.PartitionEFI.Text = "256"
$SyncHash.PartitionMSR.Text = "512"
$SyncHash.PartitionReTools.Text = "1024"
$SyncHash.PartitionRecovery.Text = "8192"
$SyncHash.PartitionWindows.Text = "max"

$SyncHash.KnowHowBootableUSB.Text = @"
ATTENTION: All data on the USB drive will be lost. Make sure you have transferred all your files.

Manually create bootable USB drive. Administrative permissions are required.

Run CMD as Administrator and proceed with these commands. Character # is the number of USB flash drive.

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

FAT32 supports BIOS and UEFI. Do not format the USB flash drive with NTFS!

Below commands assume that D: is source (mounted ISO image) and E: is destination (USB flash drive).

D:\boot\bootsect.exe /nt60 E:
robocopy D:\ E:\ /e /max:4294967296
Dism /Split-Image /ImageFile:D:\sources\install.wim /SWMFile:E:\sources\install.swm /FileSize:4096


Create partition with specific size and name. Applies for drives with over 32GB. Windows can not format and recognize FAT32 partitions over 32GB. In below example character # is USB drive number, 12288 is partition size in MB or exactly 12GB.

diskpart
list disk
select disk #
clean

create partition primary size=8192
select partition 1
active
format fs=fat32 quick label="BOOT-FAT32"
assign

create partition primary
select partition 2
format fs=ntfs quick label="DATA-NTFS"
assign

exit

"@

$SyncHash.KnowHowInstallWindows.Text = @"
######## Install Windows on a portable USB Drive. ########

ATTENTION: All data on the USB drive will be lost. Make sure you have transferred all your files.

Manually Install Windows on a portable USB Drive. SSD or HDD is recommended. Administrative permissions are required.

Run CMD as Administrator and proceed with these commands. Character # is the number of USB flash drive.


### References:
### https://decryptingtechnology.blogspot.com/
### https://www.tenforums.com/tutorials/84331-apply-windows-image-using-dism-instead-clean-install.html
### https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/capture-and-apply-windows-using-a-single-wim

### Windows Official Windows. Topic:
### https://tinyapps.org/blog/202301020700_microsoft-iso-hashes.html

### My Visual Studio Hash Dumps. Get latest hash info.
### https://awuctl.github.io/mvs/

### According to above these are the hashes for July 2023.

### Find the latest ISO with a quick google search, by a hash is highly recommended.
### Verify if it is a genuine image with a PowerShell command. Compare the hashes.
Get-FileHash C:\MyImage.iso -Algorithm SHA256

### Mount the ISO. 2nd part assumes that it is mounted as drive 'D'.

======== Part 1 - Prepare Portable USB Drive ========

### Open CMD as administrator.

diskpart
list disk
### Replace X with the correct number of your portable disk
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
### NOTE: This command will create roughly 128GB Windows partition. The rest will be unallocated for spare partitions. Adjust as per your needs.
format quick fs=ntfs label="Windows"
assign letter="W"

list volume
exit

======== Part 2 - Deploy Windows Installation ========

### Open CMD as administrator. My ISO is already mounted as drive 'D'. Adjust the drive letter in below commands if it is different.

### Find the index of the edition you want. In my case index 5 is Windows Pro. Replace 5 with the correct number according to the required edition.
dism /Get-WimInfo /WimFile:D:\sources\install.wim

md R:\RecoveryImage
copy D:\sources\install.wim R:\RecoveryImage\install.wim

dism /Apply-Image /ImageFile:R:\RecoveryImage\install.wim /Index:5 /ApplyDir:W:\

md T:\Recovery\WindowsRE
copy W:\Windows\System32\Recovery\winre.wim T:\Recovery\WindowsRE\winre.wim

bcdboot W:\Windows /s S: /f UEFI

W:\Windows\System32\reagentc /setosimage /path R:\RecoveryImage /target W:\Windows /index 5
W:\Windows\System32\reagentc /setreimage /path T:\Recovery\WindowsRE /target W:\Windows

"@

# Initialize variables and pbjects to share between threads
$SyncHash.Drives = $null

$SyncHash.OSEditions = $null
$SyncHash.SelectedOSEdition = $null

$SyncHash.SelectedDrive = $null
$SyncHash.IsoPath = $null
$SyncHash.IsoDrive = $null

$SyncHash.UpdateObjects = {
    # Enable GUI objects
    $SyncHash.DriveComboBox.IsEnabled = $true
    $SyncHash.RefreshButton.IsEnabled = $true
    $SyncHash.BrowseButton.IsEnabled = $true
    
    $SyncHash.PartitionEFI.IsEnabled = $true
    $SyncHash.PartitionMSR.IsEnabled = $true
    $SyncHash.PartitionReTools.IsEnabled = $true
    $SyncHash.PartitionRecovery.IsEnabled = $true
    $SyncHash.PartitionWindows.IsEnabled = $true

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
}

$BootPartition = Get-CimInstance -Class Win32_OperatingSystem | Select-Object -ExpandProperty SystemDrive
$BootDiskIndex = Get-Partition -DriveLetter $BootPartition.Split(":")[0] | Select-Object -ExpandProperty DiskNumber

$SyncHash.WriteOutput = {
    param ($Output, $ErrorMessage)

    $Output = ($Output | Out-String).Trim() + "`r`n`r`n" + ($ErrorMessage.Exception.Message | Out-String).Trim()
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
function HandleTextChanged {
    param ($sender)

    # Replace non-digit characters in the TextBox
    if ($sender.Text -notmatch '^([0-9]+)$') {
        $sender.Text = $sender.Text -replace "\D", ""
    }
}

# Function to populate the USB ComboBox with available USB devices
function RefreshUsbDevices {
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

    & $SyncHash.UpdateObjects
}

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

    & $SyncHash.UpdateObjects
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
            $SyncHash.IsoPathText.Text = "Path: " + $SyncHash.IsoPath
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

$SyncHash.Window.FindName("WebsiteLink").Add_Click({
    Start-Process "https://github.com/ourshell/"
})

$SyncHash.Window.FindName("ButtonCheckUpdate").Add_Click({
    $Error.Clear()
    $SyncHash.UpdateLog.Invoke("Feature Not implemented", $Error)
})


$SyncHash.Window.FindName("ButtonUpdate").Add_Click({
    $Error.Clear()
    $SyncHash.UpdateLog.Invoke("Feature Not implemented", $Error)
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
