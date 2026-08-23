# Ensure Script is being run with admin priviliges
$currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)

if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    if ($PSCommandPath) {
        Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    }
    exit
}

function Remove-OldFiles {
    param(
        [string]$Path,
        [int]$AgeDays = 30
    )

    if (-not (Test-Path $Path)) { return }

    $cutoff = (Get-Date).AddDays(-$AgeDays)

    Get-ChildItem -Path $Path -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $cutoff } |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

# Calculate free disk space
function Get-DiskFreeGB {
    param([string]$Drive = "C")
    
    try {
        $disk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='${Drive}:'" -ErrorAction Stop
        return [Math]::Round($disk.FreeSpace / 1GB, 2)
    } catch {
        return 0
    }
}

# Get initial disk usage
$freeBefore = Get-DiskFreeGB -Drive "C"

# Run Windows disk cleanup
$volumeCaches = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches"
if (Test-Path $volumeCaches) {
    Get-ChildItem $volumeCaches | ForEach-Object {
        New-ItemProperty -Path $_.PSPath -Name "StateFlags0064" -Value 2 -PropertyType DWORD -Force | Out-Null
    }
    Start-Process "cleanmgr.exe" -ArgumentList "/sagerun:64" -NoNewWindow -Wait
}

# clean up system caches
if (Get-Command Clear-BCCache -ErrorAction SilentlyContinue) {
    Clear-BCCache -Force -ErrorAction SilentlyContinue
}

if (Get-Command Delete-DeliveryOptimizationCache -ErrorAction SilentlyContinue) {
    try {
        Delete-DeliveryOptimizationCache -Force -ErrorAction Stop
    } catch { }
}

# Clean up crash dumps and shader caches
$extraCleanPaths = @(
    "C:\Windows\MEMORY.DMP",
    "C:\Windows\Minidump",
    "$env:LOCALAPPDATA\CrashDumps",
    "$env:LOCALAPPDATA\D3DSCache"
)

foreach ($targetPath in $extraCleanPaths) {
    if (Test-Path $targetPath) {
        if ((Get-Item $targetPath).PSIsContainer) {
            Remove-Item -Path "$targetPath\*" -Recurse -Force -ErrorAction SilentlyContinue
        } else {
            Remove-Item -Path $targetPath -Force -ErrorAction SilentlyContinue
        }
    }
}

# Clean up DISM component store
try {
    Start-Process "dism.exe" -ArgumentList "/Online /Cleanup-Image /StartComponentCleanup /ResetBase" -NoNewWindow -Wait -RedirectStandardOutput $null -RedirectStandardError $null
} catch { }

# Clean up log files
$logPaths = @(
    @{ Path = "C:\inetpub\logs\LogFiles"; AgeDays = 30 },
    @{ Path = "C:\Logs\Application";      AgeDays = 60 },
    @{ Path = "C:\Logs\Archived";         AgeDays = 90 }
)

foreach ($entry in $logPaths) {
    Remove-OldFiles -Path $entry.Path -AgeDays $entry.AgeDays
}

# Update Winget and Chocolatey packages
if (Get-Command winget.exe -ErrorAction SilentlyContinue) {
    winget upgrade --all --accept-source-agreements --accept-package-agreements --disable-interactivity --silent | Out-Null
}

if (Get-Command choco.exe -ErrorAction SilentlyContinue) {
    choco upgrade all -y --no-progress | Out-Null
}

# Disk space changes output
$freeAfter = Get-DiskFreeGB -Drive "C"
$gained = [Math]::Round($freeAfter - $freeBefore, 2)

Write-Host "Cleanup Completed."
Write-Host "Before: $freeBefore GB free"
Write-Host "After:  $freeAfter GB free"
Write-Host "Gained: $gained GB"

Write-Host ""
Read-Host "Press Enter to exit"
