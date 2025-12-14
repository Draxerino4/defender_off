#Date: 13/12/2025
#Author: Draxerino
#Based on: https://www.youtube.com/watch?v=ZwIoOR6Psk4

<# 
    WARNING:
    - Requires elevated PowerShell.
    - Modifies Windows Defender policy registry keys.
#>

# Bypass Powershell security policies that block the script
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

# Self-elevation to Admin if not already elevated (closes and reopens as Administrator)
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Re-launching as Administrator..."
    Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

$wdBase = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender'

function Ensure-Key {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        Write-Host "[INFO] Creating key: $Path"
        New-Item -Path $Path -Force | Out-Null
    } else {
        Write-Host "[INFO] Key already exists: $Path"
    }
}

function Set-Dword {
    param(
        [string]$Path,
        [string]$Name,
        [int]$Value
    )

    Ensure-Key -Path $Path
    Write-Host "[INFO] Setting DWORD '$Name' = $Value in '$Path'"
    New-ItemProperty -Path $Path -Name $Name -PropertyType DWord -Value $Value -Force | Out-Null
}

function Disable-Defender {
    Write-Host "=== DISABLE DEFENDER: START ==="

    # ----- Main Windows Defender key -----
    Write-Host "[STEP] Ensuring main Windows Defender policy key exists..."
    Ensure-Key -Path $wdBase

    Write-Host "[STEP] Creating main DWORDs under $wdBase"
    Set-Dword -Path $wdBase -Name 'DisableAntiSpyware'           -Value 1
    Set-Dword -Path $wdBase -Name 'DisableRealtimeMonitoring'    -Value 1
    Set-Dword -Path $wdBase -Name 'DisableAntiVirus'             -Value 1
    Set-Dword -Path $wdBase -Name 'DisableSpecialRunningModes'   -Value 1
    Set-Dword -Path $wdBase -Name 'DisableRoutinelyTakingAction' -Value 1
    Set-Dword -Path $wdBase -Name 'ServiceKeepAlive'             -Value 0

    # ----- Real-Time Protection subkey -----
    $rtKey = Join-Path $wdBase 'Real-Time Protection'
    Write-Host "[STEP] Ensuring Real-Time Protection key exists: $rtKey"
    Ensure-Key -Path $rtKey

    Write-Host "[STEP] Creating Real-Time Protection DWORDs under $rtKey"
    Set-Dword -Path $rtKey -Name 'DisableBehaviorMonitoring'   -Value 1
    Set-Dword -Path $rtKey -Name 'DisableOnAccessProtection'   -Value 1
    Set-Dword -Path $rtKey -Name 'DisableScanOnRealtimeEnable' -Value 1
    Set-Dword -Path $rtKey -Name 'DisableRealtimeMonitoring'   -Value 1

    # ----- Signature Updates subkey -----
    $sigKey = Join-Path $wdBase 'Signature Updates'
    Write-Host "[STEP] Ensuring Signature Updates key exists: $sigKey"
    Ensure-Key -Path $sigKey

    Write-Host "[STEP] Creating Signature Updates DWORDs under $sigKey"
    Set-Dword -Path $sigKey -Name 'ForceUpdateFromMU' -Value 1

    # ----- Spynet subkey -----
    $spKey = Join-Path $wdBase 'Spynet'
    Write-Host "[STEP] Ensuring Spynet key exists: $spKey"
    Ensure-Key -Path $spKey

    Write-Host "[STEP] Creating Spynet DWORDs under $spKey"
    Set-Dword -Path $spKey -Name 'DisableBlockAtFirstSeen' -Value 1

    Write-Host "=== DISABLE DEFENDER: DONE ==="
    Write-Host "[ACTION] Restart the computer to apply changes."
}

function Enable-Defender {
    Write-Host "=== ENABLE DEFENDER (UNDO): START ==="

    if (Test-Path $wdBase) {
        # Remove subkeys
        @('Real-Time Protection','Signature Updates','Spynet') | ForEach-Object {
            $sub = Join-Path $wdBase $_
            if (Test-Path $sub) {
                Write-Host "[STEP] Deleting subkey: $sub"
                Remove-Item -Path $sub -Recurse -Force -ErrorAction SilentlyContinue
            } else {
                Write-Host "[INFO] Subkey not present (skipped): $sub"
            }
        }

        # Remove top-level DWORDs
        $mainValues = @(
            'DisableAntiSpyware',
            'DisableRealtimeMonitoring',
            'DisableAntiVirus',
            'DisableSpecialRunningModes',
            'DisableRoutinelyTakingAction',
            'ServiceKeepAlive'
        )

        foreach ($name in $mainValues) {
            try {
                $prop = Get-ItemProperty -Path $wdBase -Name $name -ErrorAction Stop
                Write-Host "[STEP] Removing DWORD '$name' from $wdBase"
                Remove-ItemProperty -Path $wdBase -Name $name -Force -ErrorAction SilentlyContinue
            } catch {
                Write-Host "[INFO] DWORD '$name' not found under $wdBase (skipped)"
            }
        }
    } else {
        Write-Host "[INFO] Base key $wdBase does not exist; nothing to undo."
    }

    Write-Host "=== ENABLE DEFENDER (UNDO): DONE ==="
    Write-Host "[ACTION] Restart the computer and verify Defender is active in Windows Security."
}

Write-Host "Microsoft Defender policy helper"
Write-Host "[D] Disable Defender (policy registry method)"
Write-Host "[E] Enable Defender (undo policy keys)"
Write-Host "[X] Exit"
$choice = Read-Host "Select option"

switch ($choice.ToUpper()) {
    'D' { Disable-Defender }
    'E' { Enable-Defender }
    Default { Write-Host "Exiting." }
}
