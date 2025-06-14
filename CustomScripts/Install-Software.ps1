<#
.SYNOPSIS
    Installs various software packages silently.
.DESCRIPTION
    This script handles the silent installation of software like Google Chrome and MI.exe.
    It's designed to be called from the main Invoke-Customizations.ps1 script.
.PARAMETER ChromeInstallerPath
    The full path to the Google Chrome MSI installer file.
.PARAMETER MIInstallerPath
    The full path to the MI.exe installer file.
.PARAMETER LogPath
    The path to the directory where log files should be stored.
.NOTES
    Version: 1.0
    Author: Jules (AI Assistant)
    Date: $(Get-Date -Format 'yyyy-MM-dd')

    Run this script with Administrator privileges.
    Ensure installer files are accessible during task sequence execution.
    IMPORTANT: Review and confirm the silent installation switches for MI.exe.
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]$ChromeInstallerPath,

    [Parameter(Mandatory = $true)]
    [string]$MIInstallerPath,

    [Parameter(Mandatory = $true)]
    [string]$LogPath
)

# --- Script Configuration ---
BEGIN {
    $ErrorActionPreference = 'Stop'
    $ScriptLogFile = Join-Path -Path $LogPath -ChildPath "Install-Software_$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

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

    Function Invoke-Installer {
        param(
            [string]$InstallerPath,
            [string]$InstallArguments,
            [string]$LogName
        )
        Write-SubLog "Attempting to install $LogName from $InstallerPath with arguments: $InstallArguments"
        if (-not (Test-Path -Path $InstallerPath -PathType Leaf)) {
            Write-SubLog "$LogName installer not found at '$InstallerPath'. Skipping installation." -Level WARN
            return $false
        }

        try {
            $Process = Start-Process -FilePath $InstallerPath -ArgumentList $InstallArguments -Wait -PassThru -ErrorAction Stop
            if ($Process.ExitCode -eq 0) {
                Write-SubLog "$LogName installed successfully. Exit Code: $($Process.ExitCode)."
                return $true
            } elseif ($Process.ExitCode -eq 3010) { # 3010 often means success, reboot required
                Write-SubLog "$LogName installation completed with Exit Code: $($Process.ExitCode) (Success, reboot required)."
                return $true # Still consider it a success for now
            } else {
                Write-SubLog "$LogName installation failed. Exit Code: $($Process.ExitCode)." -Level ERROR
                return $false
            }
        } catch {
            Write-SubLog "Exception during $LogName installation: $($_.Exception.Message)" -Level ERROR
            return $false
        }
    }
}

# --- Main Processing Block ---
PROCESS {
    Write-SubLog "Starting Software Installation script..."
    Write-SubLog "Log file: $ScriptLogFile"

    # --- 1. Install Google Chrome ---
    Write-SubLog "Task: Installing Google Chrome."
    Write-SubLog "Chrome Installer Path: $ChromeInstallerPath"
    # Standard silent install switches for MSI
    $ChromeArgs = "/i ""$ChromeInstallerPath"" /qn /norestart /L*v ""$LogPath\Chrome_Install_$(Get-Date -Format 'yyyyMMdd-HHmmss').log"""
    Invoke-Installer -InstallerPath "msiexec.exe" -InstallArguments $ChromeArgs -LogName "Google Chrome"

    # --- 2. Install MI.exe ---
    Write-SubLog "Task: Installing MI.exe."
    Write-SubLog "MI.exe Installer Path: $MIInstallerPath"
    # IMPORTANT: The silent switch for MI.exe needs to be confirmed by the user.
    # Common switches are /S, /s, /q, /qn, /quiet, /silent, /VERYSILENT, /SUPPRESSMSGBOXES
    # Using '/S' as a placeholder. This MIGHT need to be changed.
    # Some installers also support creating a log file, e.g., /LOG="path	o\log.txt"
    $MIArgs = "/S" # <<< USER: PLEASE VERIFY THIS SILENT SWITCH FOR MI.exe
    # Example if it needs a log: $MIArgs = "/S /LOG=""$LogPath\MI_Install_$(Get-Date -Format 'yyyyMMdd-HHmmss').log"""

    Write-SubLog "Attempting to install MI.exe. USER ACTION REQUIRED: Verify silent switch '$MIArgs' is correct for '$MIInstallerPath'." -Level WARN
    Invoke-Installer -InstallerPath $MIInstallerPath -InstallArguments $MIArgs -LogName "MI.exe"

    Write-SubLog "Software Installation script finished."
}

END {
    Write-SubLog "Install-Software.ps1 completed."
}
