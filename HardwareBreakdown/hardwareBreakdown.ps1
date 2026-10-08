<#
.SYNOPSIS
    Hardware System Breakdown & Inventory Utility (Console & PS2EXE Compatible).

.DESCRIPTION
    Queries system information using CIM/WMI and native cmdlets to generate a clean,
    formatted breakdown of CPU, RAM, Motherboard, GPU, Storage Volumes, and connected Peripherals.
    Includes safe clipboard copy support and standalone key-press exit handling.

.EXAMPLE
    .\hardwareBreakdown.ps1 - Runs the hardware inventory interactive console report.

.OUTPUTS
    Renders formatted hardware report text directly to standard console output.

.NOTES
    Author      : Ben Parsley
    Platform    : Windows 10 / Windows 11 / Windows Server
    Requires    : PowerShell 5.1+ (Run as Administrator for full drive/bus details)
    PS2EXE      : Compatible with PS2EXE compilation for standalone executable distribution.

.LINK
    https://learn.microsoft.com/powershell/module/cimcmdlets/get-ciminstance
#>

# Initial feedback before WMI queries initialize
[Console]::Clear()
[Console]::ForegroundColor = [ConsoleColor]::Cyan
[Console]::WriteLine("Please wait... Loading System information`n")
[Console]::ResetColor()
[Console]::Out.Flush()

# System Hardware Queries
$cs = Get-CimInstance Win32_ComputerSystem
$bios = Get-CimInstance Win32_BIOS
$bb = Get-CimInstance Win32_Baseboard
$cpu = @(Get-CimInstance Win32_Processor)[0]
$ram = @(Get-CimInstance Win32_PhysicalMemory)
$gpu = @(Get-CimInstance Win32_VideoController)
$disk = @(Get-CimInstance Win32_DiskDrive)
$part = @(Get-Partition)
$vol = @(Get-Volume)
$phys = @(Get-PhysicalDisk)

# System Peripherals
$periph = @(Get-CimInstance Win32_PnPEntity | 
    Where-Object {
        $_.Present -and 
        $_.PNPClass -in 'Keyboard', 'Mouse', 'AudioEndpoint', 'Camera', 'Image', 'Bluetooth' -and 
        $_.Name -notmatch 'Standard|Virtual|Root|Composite|Controller|Hub'
    } | Select-Object -ExpandProperty Name -Unique)

# Clear placeholder and render report header
[Console]::Clear()
[Console]::ForegroundColor = [ConsoleColor]::Cyan
[Console]::WriteLine("========================= SYSTEM SPECIFICATIONS =========================")
[Console]::WriteLine("")
[Console]::ResetColor()

# Device details
$serial = $bios.SerialNumber
if ($serial -match 'Default string' -or [string]::IsNullOrWhiteSpace($serial)) {
    $serial = 'No serial number assigned'
}

[Console]::WriteLine("  Device        : $($cs.Name)")
[Console]::WriteLine("  Serial Number : $serial")
[Console]::WriteLine("  Motherboard   : $($bb.Manufacturer) $($bb.Product)")
[Console]::WriteLine("  Processor     : $($cpu.Name) [$($cpu.NumberOfCores)C/$($cpu.NumberOfLogicalProcessors)T @ $($cpu.MaxClockSpeed)MHz]")

# Memory
$totalRamGB = [Math]::Round(($ram | Measure-Object Capacity -Sum).Sum / 1GB, 1)
[Console]::WriteLine("  Memory        : $totalRamGB GB Total ($($ram.Count) stick(s))")
$ram | ForEach-Object {
    $partNum = if ($_.PartNumber) { $_.PartNumber.Trim() } else { "N/A" }
    [Console]::WriteLine("                  - $($_.DeviceLocator): $($_.Speed)MHz ($partNum)")
}

# Graphics
[Console]::WriteLine("  Graphics      :")
$gpu | ForEach-Object {
    $res = if ($_.CurrentHorizontalResolution) { "$($_.CurrentHorizontalResolution)x$($_.CurrentVerticalResolution)" } else { "Inactive/External" }
    [Console]::WriteLine("                  - $($_.Name) (Driver: $($_.DriverVersion), $res)")
}

# Storage
[Console]::WriteLine("  Storage       :")
$disk | ForEach-Object {
    $d = $_
    $letters = @($part | Where-Object { $_.DiskNumber -eq $d.Index -and $_.DriveLetter } | Select-Object -ExpandProperty DriveLetter)
    $vols = @($vol | Where-Object { $_.DriveLetter -in $letters } | ForEach-Object {
            $used = [Math]::Round(($_.Size - $_.SizeRemaining) / 1GB, 1)
            $total = [Math]::Round($_.Size / 1GB, 1)
            "$($_.DriveLetter): $used/$total GB used"
        })
    $volStr = if ($vols.Count -gt 0) { "[" + ($vols -join ', ') + "]" } else { "[No Letter]" }

    $pDisk = $phys | Where-Object { $_.DeviceId -eq $d.Index } | Select-Object -First 1
    $media = if ($pDisk -and $pDisk.MediaType -and $pDisk.MediaType -ne 'Unspecified') { $pDisk.MediaType } else { "Disk" }
    $bus = if ($pDisk -and $pDisk.BusType -and $pDisk.BusType -ne 'Unspecified') { $pDisk.BusType } else { $d.InterfaceType }

    [Console]::WriteLine("                  - $volStr $($d.Model) ($media via $bus)")
}

# Peripherals
[Console]::WriteLine("")
[Console]::ForegroundColor = [ConsoleColor]::Cyan
[Console]::WriteLine("=========================  CONNECTED PERIPHERALS ========================= ")
[Console]::WriteLine("")
[Console]::ResetColor()

if ($periph.Count -gt 0) {
    $periph | ForEach-Object { [Console]::WriteLine("  * $_") }
}
else {
    [Console]::WriteLine("  * (No external peripheral devices detected)")
}

# Footer
[Console]::ForegroundColor = [ConsoleColor]::Cyan
[Console]::WriteLine("")
[Console]::WriteLine("=========================================================================`n")
[Console]::ResetColor()

[Console]::ForegroundColor = [ConsoleColor]::White
[Console]::WriteLine("Press 'C' to exit (Text can be copy and pasted)...")
[Console]::ResetColor()
[Console]::Out.Flush()

# Wait loop: Only closes on standalone 'C' or 'c', ignoring mouse selections and Ctrl+C copy shortcuts
while ($true) {
    $keyInfo = [Console]::ReadKey($true)
    
    # Check for 'C' or 'c' without the Ctrl or Alt modifiers
    $isPlainC = ($keyInfo.Key -eq [ConsoleKey]::C) -and 
    (-not ($keyInfo.Modifiers -band [ConsoleModifiers]::Control)) -and 
    (-not ($keyInfo.Modifiers -band [ConsoleModifiers]::Alt))

    if ($isPlainC) {
        break
    }
}