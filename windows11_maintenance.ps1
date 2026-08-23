# Relaunch script as Administrator if not already elevated
$currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)

if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Administrator privileges required. Requesting elevation..."

    Start-Process powershell.exe `
        -Verb RunAs `
        -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""

    exit
}

function Remove-OldFiles {
    param(
        [string]$Path,
        [int]$AgeDays = 30,
        [switch]$WhatIf
    )

    $cutoff = (Get-Date).AddDays(-$AgeDays)

    $files = Get-ChildItem -Path $Path -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object LastWriteTime -lt $cutoff

    $totalSize = ($files | Measure-Object -Property Length -Sum).Sum

    # Prevent null/empty results from causing calculation issues
    if ($null -eq $totalSize) {
        $totalSize = 0
    }

    if ($WhatIf) {
        Write-Host "Would delete $($files.Count) files ($([Math]::Round($totalSize / 1MB, 1)) MB) from $Path"
        return 0
    }

    $files | Remove-Item -Force -ErrorAction SilentlyContinue

    Write-Host "Deleted $($files.Count) files from $Path ($([Math]::Round($totalSize / 1MB, 1)) MB freed)"
    return $totalSize
}

function Get-DiskFreeGB {
    param(
        [string]$Drive = "C"
    )

    $disk = Get-PSDrive -Name $Drive -ErrorAction SilentlyContinue

    if ($disk) {
        [Math]::Round($disk.Free / 1GB, 2)
    }
    else {
        $diskInfo = Get-CimInstance -ClassName Win32_LogicalDisk `
            -Filter "DeviceID='${Drive}:'" `
            -ErrorAction SilentlyContinue

        if ($diskInfo) {
            [Math]::Round($diskInfo.FreeSpace / 1GB, 2)
        }
        else {
            0
        }
    }
}

# Get initial disk usage
$freeBefore = Get-DiskFreeGB -Drive "C"

Write-Host "Starting cleanup..."
Write-Host "Initial free space: $freeBefore GB"
Write-Host ""

# Places where temporary files might be stored
$tempPaths = @(
    $env:TEMP,
    $env:TMP,
    "C:\Windows\Temp",
    "C:\Windows\SoftwareDistribution\Download"
)

$totalFreed = 0

foreach ($path in $tempPaths) {
    if (Test-Path $path) {
        $freed = Remove-OldFiles -Path $path -AgeDays 7
        $totalFreed += $freed
    }
}

Write-Host ""
Write-Host "Total from temp folders: $([Math]::Round($totalFreed / 1MB, 1)) MB"
Write-Host ""

# Clear BITS cache if Clear-BCCache is available
if (Get-Command Clear-BCCache -ErrorAction SilentlyContinue) {
    Write-Host "Clearing BITS cache..."
    Clear-BCCache -Force -ErrorAction SilentlyContinue
    Write-Host "BITS cache cleanup completed."
}
else {
    Write-Host "Clear-BCCache not available - skipping."
}

Write-Host ""

# Get recycle bin size before clearing
$shell = New-Object -ComObject Shell.Application
$recycleBin = $shell.Namespace(0xA)

if ($recycleBin) {
    $binSize = ($recycleBin.Items() | Measure-Object -Property Size -Sum).Sum

    if ($null -eq $binSize) {
        $binSize = 0
    }
}
else {
    $binSize = 0
}

# Clear the recycle bin if the command is available
if (Get-Command Clear-RecycleBin -ErrorAction SilentlyContinue) {
    Clear-RecycleBin -Force -ErrorAction SilentlyContinue

    Write-Host "Recycle bin cleared: $([Math]::Round($binSize / 1MB, 1)) MB freed"
}
else {
    Write-Host "Clear-RecycleBin not available - skipping."
}

Write-Host ""

# Log directories and retention periods
$logPaths = @(
    @{ Path = "C:\inetpub\logs\LogFiles"; AgeDays = 30 },
    @{ Path = "C:\Logs\Application";      AgeDays = 60 },
    @{ Path = "C:\Logs\Archived";         AgeDays = 90 }
)

$totalFreed = 0

foreach ($entry in $logPaths) {
    if (Test-Path $entry.Path) {
        $freed = Remove-OldFiles `
            -Path $entry.Path `
            -AgeDays $entry.AgeDays

        $totalFreed += $freed
    }
}

Write-Host "Total from log directories: $([Math]::Round($totalFreed / 1MB, 1)) MB"
Write-Host ""

# Update WinGet packages if Winget is installed
if (Get-Command winget.exe -ErrorAction SilentlyContinue) {
    Write-Host "Updating WinGet packages..."
    winget upgrade --all --accept-source-agreements --accept-package-agreements
}

# Update Chocolatey packages if Chocolatey is installed
if (Get-Command choco.exe -ErrorAction SilentlyContinue) {
    Write-Host "Updating Chocolatey packages..."
    choco upgrade all -y
}

# Output final disk usage
$freeAfter = Get-DiskFreeGB -Drive "C"

$gained = [Math]::Round($freeAfter - $freeBefore, 2)

$report = @"
Cleanup $(Get-Date):
Before: $freeBefore GB free
After:  $freeAfter GB free
Gained: $gained GB
"@

Write-Host $report

Write-Host ""
Read-Host "Press Enter to exit"

