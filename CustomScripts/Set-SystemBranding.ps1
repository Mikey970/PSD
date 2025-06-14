<#
.SYNOPSIS
    Sets system branding elements like default wallpaper and touch keyboard icon visibility.
.DESCRIPTION
    This script configures the default wallpaper for new users and ensures the
    touch keyboard icon is visible on the taskbar.
    It's designed to be called from the main Invoke-Customizations.ps1 script.
.PARAMETER WallpaperPath
    The full path to the wallpaper image file (e.g., login-bg.jpg) on the deployment share
    or a path accessible during the task sequence.
.PARAMETER LogPath
    The path to the directory where log files should be stored.
.NOTES
    Version: 1.0
    Author: Jules (AI Assistant)
    Date: $(Get-Date -Format 'yyyy-MM-dd')

    Run this script with Administrator privileges.
    The script handles copying the wallpaper to a local directory.
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]$WallpaperPath,

    [Parameter(Mandatory = $true)]
    [string]$LogPath
)

# --- Script Configuration ---
BEGIN {
    $ErrorActionPreference = 'Stop'
    $ScriptLogFile = Join-Path -Path $LogPath -ChildPath "Set-SystemBranding_$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

    Function Write-SubLog {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            [string]$Message,
            [ValidateSet("INFO", "WARN", "ERROR")]
            [string]$Level = "INFO"
        )
        $LogEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] - $Message"
        Add-Content -Path $ScriptLogFile -Value $LogEntry
        Write-Host $LogEntry
    }

    # Function to set registry values in a loaded hive
    Function Set-LoadedHiveRegistryValue {
        param (
            [string]$HivePath,
            [string]$Key,
            [string]$Name,
            $Value,
            [Microsoft.Win32.RegistryValueKind]$Type = [Microsoft.Win32.RegistryValueKind]::String
        )
        try {
            Write-SubLog "Attempting to set registry: Hive '$HivePath', Key '$Key', Name '$Name', Value '$Value'"
            $RegKey = "Registry::$HivePath\$Key"
            if (-not (Test-Path $RegKey)) {
                New-Item -Path $RegKey -Force -ErrorAction Stop | Out-Null
                Write-SubLog "Created registry key: $RegKey"
            }
            New-ItemProperty -Path $RegKey -Name $Name -Value $Value -PropertyType $Type -Force -ErrorAction Stop | Out-Null
            Write-SubLog "Successfully set registry value '$Name' to '$Value' in '$RegKey'."
        } catch {
            Write-SubLog "Failed to set registry value '$Name' in '$Key'. Error: $($_.Exception.Message)" -Level ERROR
            # Re-throw to allow higher level catch
            throw $_
        }
    }
}

# --- Main Processing Block ---
PROCESS {
    Write-SubLog "Starting System Branding script..."
    Write-SubLog "Log file: $ScriptLogFile"
    Write-SubLog "Wallpaper source path: $WallpaperPath"

    # --- 1. Set Default Wallpaper ---
    Write-SubLog "Task: Setting Default Wallpaper."
    try {
        if (-not (Test-Path -Path $WallpaperPath -PathType Leaf)) {
            Write-SubLog "Wallpaper file '$WallpaperPath' not found. Skipping wallpaper setup." -Level WARN
        } else {
            $WallpaperFileName = Split-Path -Path $WallpaperPath -Leaf
            $LocalWallpaperDir = "C:\Windows\System32\oobe\info\backgrounds" # Standard path for login background
            $LocalWallpaperPath = Join-Path -Path $LocalWallpaperDir -ChildPath $WallpaperFileName

            # Ensure the target directory exists
            if (-not (Test-Path -Path $LocalWallpaperDir -PathType Container)) {
                Write-SubLog "Creating directory: $LocalWallpaperDir"
                New-Item -ItemType Directory -Path $LocalWallpaperDir -Force | Out-Null
            }

            Write-SubLog "Copying wallpaper from '$WallpaperPath' to '$LocalWallpaperPath'."
            Copy-Item -Path $WallpaperPath -Destination $LocalWallpaperPath -Force -ErrorAction Stop

            # Set for OOBE/Login screen (OEMBackground)
            $OEMBackgroundRegPath = "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI\Background"
            if (-not (Test-Path "Registry::$OEMBackgroundRegPath")) {
                New-Item -Path "Registry::$OEMBackgroundRegPath" -Force | Out-Null
            }
            New-ItemProperty -Path "Registry::$OEMBackgroundRegPath" -Name "OEMBackground" -Value 1 -PropertyType DWord -Force -ErrorAction Stop
            Write-SubLog "Enabled OEMBackground for login screen."
            # Some systems might require this one instead or in addition for the lock screen before login
            New-ItemProperty -Path "Registry::$OEMBackgroundRegPath" -Name "UseOEMBackground" -Value 1 -PropertyType DWord -Force -ErrorAction Stop | Out-Null
            Write-SubLog "Enabled UseOEMBackground for login screen."


            # Set for new users by modifying the Default User hive
            Write-SubLog "Modifying Default User hive for wallpaper..."
            $DefaultUserHive = "C:\Users\Default\NTUSER.DAT"
            $HiveLoadPath = "HKU\DefaultUser_Temp"

            if (Test-Path $DefaultUserHive) {
                Write-SubLog "Loading Default User hive from '$DefaultUserHive' to '$HiveLoadPath'."
                reg load $HiveLoadPath $DefaultUserHive

                Set-LoadedHiveRegistryValue -HivePath $HiveLoadPath -Key "Control Panel\Desktop" -Name "Wallpaper" -Value $LocalWallpaperPath
                Set-LoadedHiveRegistryValue -HivePath $HiveLoadPath -Key "Control Panel\Desktop" -Name "TileWallpaper" -Value "0" # 0 for stretch/fill, 1 for tile
                Set-LoadedHiveRegistryValue -HivePath $HiveLoadPath -Key "Control Panel\Desktop" -Name "WallpaperStyle" -Value "2" # 2 for Stretch, 6 for Fit, 10 for Fill

                Write-SubLog "Unloading Default User hive."
                reg unload $HiveLoadPath
                Write-SubLog "Default wallpaper for new users configured to '$LocalWallpaperPath'."
            } else {
                Write-SubLog "Default User hive ($DefaultUserHive) not found. Skipping wallpaper for new users." -Level WARN
            }
        }
    } catch {
        Write-SubLog "Error setting default wallpaper: $($_.Exception.Message)" -Level ERROR
    }

    # --- 2. Enable Touch Keyboard Icon ---
    Write-SubLog "Task: Enabling Touch Keyboard Icon for new users."
    try {
        Write-SubLog "Modifying Default User hive for Touch Keyboard Icon..."
        $DefaultUserHive = "C:\Users\Default\NTUSER.DAT"
        $HiveLoadPath = "HKU\DefaultUser_Temp_Keyboard" # Use a different temp name

        if (Test-Path $DefaultUserHive) {
            # Ensure no previous instance is stuck
            $ExistingLoadedHive = Get-ChildItem HKU: | Where-Object {$_.Name -like "*$($HiveLoadPath.Split('\')[-1])"}
            if ($ExistingLoadedHive) {
                Write-SubLog "Attempting to unload potentially stuck hive at $HiveLoadPath" -Level WARN
                try { reg unload $HiveLoadPath } catch { Write-SubLog "Failed to unload existing temp hive, might not be loaded by this script. Error: $($_.Exception.Message)" -Level WARN }
            }

            Write-SubLog "Loading Default User hive from '$DefaultUserHive' to '$HiveLoadPath'."
            reg load $HiveLoadPath $DefaultUserHive

            # Path: HKCU\Software\Microsoft\TabletTip.7
            # Value: TipbandDesiredVisibility (DWORD) = 1
            Set-LoadedHiveRegistryValue -HivePath $HiveLoadPath -Key "Software\Microsoft\TabletTip\1.7" -Name "TipbandDesiredVisibility" -Value 1 -Type DWord

            Write-SubLog "Unloading Default User hive for Touch Keyboard."
            reg unload $HiveLoadPath
            Write-SubLog "Touch Keyboard icon enabled for new users."

            # Also set for HKLM to influence default behavior if possible (might not always work for this specific setting)
            # This is more of a "best effort" for system-wide defaults.
             $LMKey = "HKLM\SOFTWARE\Microsoft\TabletTip\1.7"
             if (-not (Test-Path "Registry::$LMKey")) { New-Item -Path "Registry::$LMKey" -Force | Out-Null }
             New-ItemProperty -Path "Registry::$LMKey" -Name "TipbandDesiredVisibility" -Value 1 -PropertyType DWord -Force -ErrorAction Stop | Out-Null
             Write-SubLog "Set TipbandDesiredVisibility in HKLM as well."

        } else {
            Write-SubLog "Default User hive ($DefaultUserHive) not found. Skipping Touch Keyboard icon for new users." -Level WARN
        }
    } catch {
        Write-SubLog "Error enabling Touch Keyboard icon: $($_.Exception.Message)" -Level ERROR
    }

    Write-SubLog "System Branding script finished."
}
END {
    Write-SubLog "Set-SystemBranding.ps1 completed."
}
