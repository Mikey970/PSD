<#
.SYNOPSIS
    Master script to orchestrate all Windows customizations during deployment.
.DESCRIPTION
    This script calls various helper scripts and functions to apply system branding,
    install software, configure settings, and copy necessary files.
    It should be placed in the 'CustomScripts' folder of the deployment share.
.NOTES
    Version: 1.0
    Author: Jules (AI Assistant)
    Date: $(Get-Date -Format 'yyyy-MM-dd')

    Ensure helper scripts (Set-SystemBranding.ps1, Install-Software.ps1,
    Configure-SystemSettings.ps1, Copy-DOTempFolder.ps1) are in the same directory
    as this master script or their paths are correctly defined.
#>

#Requires -RunAsAdministrator

[CmdletBinding()]
param ()

# --- Script Configuration ---
BEGIN {
    # Set Error Action Preference
    $ErrorActionPreference = 'Stop'
    #$ProgressPreference = 'SilentlyContinue' # Uncomment for less verbose output in production

    # --- Paths ---
    # Script root is the directory where this script itself is located
    $ScriptRoot = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition

    # Log file setup
    $LogDir = Join-Path -Path $ScriptRoot -ChildPath "Logs"
    If (-not (Test-Path -Path $LogDir)) {
        New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    }
    $LogFile = Join-Path -Path $LogDir -ChildPath "Customizations_$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

    # Paths to helper scripts (assuming they are in the same directory as this script)
    $SetSystemBrandingScript = Join-Path -Path $ScriptRoot -ChildPath "Set-SystemBranding.ps1"
    $InstallSoftwareScript = Join-Path -Path $ScriptRoot -ChildPath "Install-Software.ps1"
    $ConfigureSystemSettingsScript = Join-Path -Path $ScriptRoot -ChildPath "Configure-SystemSettings.ps1"
    $CopyFilesScript = Join-Path -Path $ScriptRoot -ChildPath "Copy-DOTempFolder.ps1"

    # Resource Paths (relative to $ScriptRoot for items within CustomScripts)
    # These paths would typically point to locations on the deployment share, accessible during deployment.
    # For items copied from the deployment share to the client, these might be updated to local client paths.
    $WallpaperFile = Join-Path -Path $ScriptRoot -ChildPath "Media\login-bg.jpg" # Source on deployment share
    $ChromeInstaller = Join-Path -Path $ScriptRoot -ChildPath "Installers\Chrome\GoogleChromeStandaloneEnterprise64.msi" # Source on deployment share
    $MIInstaller = Join-Path -Path $ScriptRoot -ChildPath "Installers\MI\MI.exe" # Source on deployment share
    $AppAssocXml = Join-Path -Path $ScriptRoot -ChildPath "AppAssoc.xml" # Source on deployment share, will be copied locally by helper script

    # Source for DO_temp on the deployment server (this needs to be accessible from the client during TS)
    # Example: $SourceDOTempFolder = "\\YourDeploymentServer\DeploymentShare\DO_temp"
    # For now, we'll assume it's passed as a parameter or defined in the Copy-DOTempFolder.ps1 script or task sequence
    # This script will primarily focus on *calling* the copy script.

    # Destination for DO_temp on the client
    $DestinationDOTempFolder = "C:\DO_temp" # Example destination

    # --- Logging Function ---
    Function Write-Log {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
            [string]$Message,
            [ValidateSet("INFO", "WARN", "ERROR")]
            [string]$Level = "INFO"
        )
        $LogEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] - $Message"
        Add-Content -Path $LogFile -Value $LogEntry
        Write-Host $LogEntry # Also output to console for real-time feedback during TS
    }
}

# --- Main Processing Block ---
PROCESS {
    Write-Log -Message "Starting Windows Customizations..."
    Write-Log -Message "Script Root: $ScriptRoot"
    Write-Log -Message "Log File: $LogFile"

    # Sequence of operations:
    # 1. Copy DO_temp folder (often done early if other steps depend on its content)
    # 2. Set System Branding (Wallpaper, Touch Keyboard)
    # 3. Install Software (Chrome, MI.exe)
    # 4. Configure System Settings (Default Browser, Copilot, OneDrive)

    # --- 1. Copy DO_temp Folder ---
    Write-Log -Message "Task: Copying DO_temp folder."
    if (Test-Path -Path $CopyFilesScript) {
        try {
            # Note: The $SourceDOTempFolder needs to be correctly defined.
            # It might be passed via Task Sequence variable or hardcoded if static.
            # For now, assuming Copy-DOTempFolder.ps1 handles its source path or gets it.
            # Example: & $CopyFilesScript -SourcePath "\\YourDeploymentServer\DeploymentShare\DO_temp" -DestinationPath $DestinationDOTempFolder -LogPath $LogDir
            # We will refine this call when Copy-DOTempFolder.ps1 is created.
            # For now, a simple call:
            & $CopyFilesScript -DestinationPath $DestinationDOTempFolder -LogPath $LogDir
            Write-Log -Message "Copy DO_temp folder task initiated."
        } catch {
            Write-Log -Message "Error executing Copy-DOTempFolder.ps1: $($_.Exception.Message)" -Level ERROR
        }
    } else {
        Write-Log -Message "Copy-DOTempFolder.ps1 not found. Skipping." -Level WARN
    }

    # --- 2. Set System Branding ---
    Write-Log -Message "Task: Setting System Branding."
    if (Test-Path -Path $SetSystemBrandingScript) {
        try {
            & $SetSystemBrandingScript -WallpaperPath $WallpaperFile -LogPath $LogDir
            Write-Log -Message "Set System Branding task initiated."
        } catch {
            Write-Log -Message "Error executing Set-SystemBranding.ps1: $($_.Exception.Message)" -Level ERROR
        }
    } else {
        Write-Log -Message "Set-SystemBranding.ps1 not found. Skipping." -Level WARN
    }

    # --- 3. Install Software ---
    Write-Log -Message "Task: Installing Software."
    if (Test-Path -Path $InstallSoftwareScript) {
        try {
            & $InstallSoftwareScript -ChromeInstallerPath $ChromeInstaller -MIInstallerPath $MIInstaller -LogPath $LogDir
            Write-Log -Message "Install Software task initiated."
        } catch {
            Write-Log -Message "Error executing Install-Software.ps1: $($_.Exception.Message)" -Level ERROR
        }
    } else {
        Write-Log -Message "Install-Software.ps1 not found. Skipping." -Level WARN
    }

    # --- 4. Configure System Settings ---
    Write-Log -Message "Task: Configuring System Settings."
    if (Test-Path -Path $ConfigureSystemSettingsScript) {
        try {
            & $ConfigureSystemSettingsScript -AppAssocFilePath $AppAssocXml -LogPath $LogDir
            Write-Log -Message "Configure System Settings task initiated."
        } catch {
            Write-Log -Message "Error executing Configure-SystemSettings.ps1: $($_.Exception.Message)" -Level ERROR
        }
    } else {
        Write-Log -Message "Configure-SystemSettings.ps1 not found. Skipping." -Level WARN
    }

    Write-Log -Message "Windows Customizations script finished."
}

# --- End Block ---
END {
    Write-Log -Message "Invoke-Customizations.ps1 completed."
    # Additional cleanup if any
}
