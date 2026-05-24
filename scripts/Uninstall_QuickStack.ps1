param(
    [string]$GameWin64 = "",
    [switch]$NoPrompt
)

$ErrorActionPreference = "Stop"

$PackageRoot = Split-Path -Parent $PSScriptRoot
$MarkerFileName = ".tp_quickstack_marker"

function Resolve-GameWin64 {
    if ($GameWin64) {
        if (Test-Path -LiteralPath $GameWin64) {
            return (Resolve-Path -LiteralPath $GameWin64).Path
        }
        throw "Game Win64 folder does not exist: $GameWin64"
    }

    if ($NoPrompt) {
        throw "Game Win64 folder was not found. Re-run with -GameWin64 ""<path>""."
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
        throw "The Parasites is still running. Close the game before uninstalling QuickStack."
    }
}

Assert-Game-Closed
$GameWin64 = Resolve-GameWin64

$targetDwmapi = Join-Path $GameWin64 "dwmapi.dll"
$targetUe4ss = Join-Path $GameWin64 "ue4ss"
$marker = Join-Path $targetUe4ss $MarkerFileName
$hasMarker = Test-Path -LiteralPath $marker

if ((Test-Path -LiteralPath $targetDwmapi) -or (Test-Path -LiteralPath $targetUe4ss)) {
    if (-not $hasMarker) {
        Write-Host "The current UE4SS install does not contain the QuickStack marker."
        if (-not $NoPrompt) {
            $answer = Read-Host "Remove it anyway? [y/N]"
            if ($answer.ToLowerInvariant() -notin @("y", "yes")) {
                throw "Cancelled."
            }
        }
    }

    if (Test-Path -LiteralPath $targetDwmapi) {
        Remove-Item -LiteralPath $targetDwmapi -Force
    }
    if (Test-Path -LiteralPath $targetUe4ss) {
        Remove-Item -LiteralPath $targetUe4ss -Recurse -Force
    }

    Write-Host "QuickStack UE4SS files removed."
} else {
    Write-Host "No QuickStack UE4SS files found."
}

$backupFile = Join-Path $PackageRoot "last_backup.txt"
if (Test-Path -LiteralPath $backupFile) {
    $backup = (Get-Content -LiteralPath $backupFile -Raw).Trim()
    if ($backup -and (Test-Path -LiteralPath $backup)) {
        Write-Host ""
        Write-Host "A previous backup exists:"
        Write-Host "  $backup"
        $restore = $NoPrompt
        if (-not $NoPrompt) {
            $answer = Read-Host "Restore it now? [y/N]"
            $restore = $answer.ToLowerInvariant() -in @("y", "yes")
        }
        if ($restore) {
            foreach ($item in Get-ChildItem -LiteralPath $backup -Force) {
                Copy-Item -LiteralPath $item.FullName -Destination (Join-Path $GameWin64 $item.Name) -Recurse -Force
            }
            Remove-Item -LiteralPath $backupFile -Force
            Write-Host "Backup restored."
        }
    }
}
