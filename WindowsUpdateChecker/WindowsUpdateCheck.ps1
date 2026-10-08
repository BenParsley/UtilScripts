$computerName =$env:COMPUTERNAME
$inputKB =$null

while ($true) {
    Clear-Host

    # If $inputKB wasn't pre-populated by previous loop iteration, prompt the user
    if ([string]::IsNullOrWhiteSpace($inputKB)) {
        $inputKB = Read-Host "Enter KB number"
    }

    # Exit check
    if ($inputKB.Trim().ToLower() -eq 'c') {
        break
    }

    # Extract digits only
    $digits = $inputKB -replace '\D', ''

    if (-not $digits) {
        Write-Warning "Invalid input. A numeric KB number is required."
        Start-Sleep -Seconds 2
        $inputKB = $null
        continue
    }

    $kbFull = "KB$digits"
    $kbRegex = "(?i)\bKB$digits\b"

    Write-Host "`nAuditing installation status for $kbFull on $computerName...`n" -ForegroundColor Cyan

    $results = [ordered]@{
        "Get-HotFix"       = $false
        "CIM Instance"     = $false
        "DISM (Package)"   = $false
        "COM Update Agent" = $false
        "Setup Event Log"  = $false
    }

    # 1. Get-HotFix
    if (Get-HotFix -Id $kbFull -ErrorAction SilentlyContinue) {
        $results["Get-HotFix"] = $true
    }

    # 2. CIM / WMI
    if (Get-CimInstance -ClassName Win32_QuickFixEngineering -Filter "HotFixID = '$kbFull'" -ErrorAction SilentlyContinue) {
        $results["CIM Instance"] = $true
    }

    # 3. DISM / Get-WindowsPackage (Requires Elevation)
    try {
        $pkg = Get-WindowsPackage -Online -ErrorAction Stop | 
            Where-Object { $_.PackageName -match $kbRegex -and $_.PackageState -eq "Installed" }
        if ($pkg) { $results["DISM (Package)"] = $true }
    } catch {
        $results["DISM (Package)"] = "Requires Elevation (Run as Admin)"
    }

    # 4. Windows Update Agent (COM Object)
    try {
        $session = New-Object -ComObject Microsoft.Update.Session
        $searcher = $session.CreateUpdateSearcher()
        $total = $searcher.GetTotalHistoryCount()
        if ($total -gt 0) {
            $found = $searcher.QueryHistory(0, $total) | 
                Where-Object { $_.Title -match $kbRegex -and $_.ResultCode -eq 2 }
            if ($found) { $results["COM Update Agent"] = $true }
        }
    } catch {
        $results["COM Update Agent"] = "COM Query Error"
    }

    # 5. Windows Event Log
    $eventFound = Get-WinEvent -LogName "Setup" -FilterXPath "*[System[EventID=2]]" -ErrorAction SilentlyContinue |
        Where-Object { $_.Message -match $kbRegex }
    if ($eventFound) {
        $results["Setup Event Log"] = $true
    }

    # Render formatted table
    Write-Host ("{0,-25} {1}" -f "Method / Provider", "Status")
    Write-Host ("-" * 35)

    foreach ($key in $results.Keys) {
        $val = $results[$key]
        Write-Host ("{0,-25} " -f $key) -NoNewline

        if ($val -eq $true) {
            Write-Host "True" -ForegroundColor Green
        } elseif ($val -eq $false) {
            Write-Host "False" -ForegroundColor DarkGray
        } else {
            Write-Host $val -ForegroundColor Yellow
        }
    }
    # Explicit verdict banner
    $isInstalledAnywhere = $results.Values -contains $true

    Write-Host ""
    if ($isInstalledAnywhere) {
        Write-Host "INSTALLED: YES ($kbFull is present on $computerName)" -ForegroundColor Green
    } else {
        Write-Host "INSTALLED: NO ($kbFull is not installed on $computerName)" -ForegroundColor Red
    }
    Write-Host ""

    # Navigation prompts on distinct lines
    $nextAction = Read-Host "`nEnter KB number or 'C'"

    if ($nextAction.Trim().ToLower() -eq 'c') {         break     } elseif ($nextAction -match '\d') {
        $inputKB =$nextAction
    } else {
        $inputKB =$null
    }
}