param(
    [string]$GameWin64 = "",
    [switch]$NoPrompt
)

$ErrorActionPreference = "Stop"

$PackageRoot = Split-Path -Parent $PSScriptRoot
$PayloadWin64 = Join-Path $PackageRoot "COPY_TO_GAME_WIN64"
$BackupsRoot = Join-Path $PackageRoot "backups"
$MarkerFileName = ".tp_quickstack_marker"

function Resolve-GameWin64 {
    if ($GameWin64) {
        if (Test-Path -LiteralPath $GameWin64) {
            return (Resolve-Path -LiteralPath $GameWin64).Path
        }
        throw "Game Win64 folder does not exist: $GameWin64"
    }

    if ($NoPrompt) {
        throw "Game Win64 folder was not found. Re-run with -GameWin64 ""<path>"" or copy COPY_TO_GAME_WIN64 manually."
    }

    while ($true) {
        $entered = Read-Host "Enter The Parasites Win64 folder path"
        if ($entered -and (Test-Path -LiteralPath $entered)) {
            return (Resolve-Path -LiteralPath $entered).Path
        }
        Write-Host "Folder does not exist. Please enter the folder that contains TheParasites-Win64-Shipping.exe."
    }
}

function Assert-Game-Closed {
    $processes = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like "TheParasites*" }
    if ($processes) {
        throw "The Parasites is still running. Close the game before installing QuickStack."
    }
}

function Copy-Directory($Source, $Target) {
    New-Item -ItemType Directory -Force -Path $Target | Out-Null
    Copy-Item -Path (Join-Path $Source "*") -Destination $Target -Recurse -Force
}

if (-not (Test-Path -LiteralPath $PayloadWin64)) {
    throw "Payload folder is missing: $PayloadWin64"
}

Assert-Game-Closed
$GameWin64 = Resolve-GameWin64

$gameExe = Join-Path $GameWin64 "TheParasites-Win64-Shipping.exe"
if (-not (Test-Path -LiteralPath $gameExe)) {
    throw "This does not look like The Parasites Win64 folder: $GameWin64"
}

New-Item -ItemType Directory -Force -Path $BackupsRoot | Out-Null

$targetDwmapi = Join-Path $GameWin64 "dwmapi.dll"
$targetUe4ss = Join-Path $GameWin64 "ue4ss"
$marker = Join-Path $targetUe4ss $MarkerFileName
$hasMarker = Test-Path -LiteralPath $marker

$existingTargets = @($targetDwmapi, $targetUe4ss) | Where-Object { Test-Path -LiteralPath $_ }

if ($existingTargets.Count -gt 0 -and -not $hasMarker) {
    Write-Host "Existing UE4SS/dwmapi files were found:"
    $existingTargets | ForEach-Object { Write-Host "  $_" }
    if (-not $NoPrompt) {
        $answer = Read-Host "Back them up and replace with QuickStack? [y/N]"
        if ($answer.ToLowerInvariant() -notin @("y", "yes")) {
            throw "Cancelled."
        }
    }
}

if ($existingTargets.Count -gt 0) {
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backup = Join-Path $BackupsRoot "pre_quickstack_$stamp"
    New-Item -ItemType Directory -Force -Path $backup | Out-Null
    foreach ($target in $existingTargets) {
        Move-Item -LiteralPath $target -Destination (Join-Path $backup (Split-Path -Leaf $target)) -Force
    }
    Set-Content -LiteralPath (Join-Path $PackageRoot "last_backup.txt") -Value $backup -Encoding ASCII
    Write-Host "Backed up previous files to: $backup"
}

Copy-Directory $PayloadWin64 $GameWin64

$installedMarker = Join-Path $GameWin64 "ue4ss\$MarkerFileName"
Set-Content -LiteralPath $installedMarker -Value @(
    "The Parasites QuickStack"
    "Version: 1.0.0"
    "Installed at: $(Get-Date -Format s)"
) -Encoding ASCII

Write-Host ""
Write-Host "QuickStack installed."
Write-Host "Game Win64 folder: $GameWin64"
Write-Host "Use in game: open a container, then press Ctrl+F9."
