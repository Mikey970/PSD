<#
.SYNOPSIS
    Copies a folder from a source to a destination using Robocopy.
.DESCRIPTION
    This script is designed to copy a folder, typically from a deployment share
    to the local client machine during a task sequence. It utilizes Robocopy
    for its robustness and logging capabilities.
.PARAMETER SourcePath
    The full path to the source folder (e.g., "\\Server\Share\DO_temp").
    This parameter is mandatory.
.PARAMETER DestinationPath
    The full path to the destination folder on the client (e.g., "C:\DO_temp").
    This parameter is mandatory.
.PARAMETER LogPath
    The path to the directory where Robocopy log files should be stored.
    This parameter is mandatory.
.NOTES
    Version: 1.0
    Author: Jules (AI Assistant)
    Date: $(Get-Date -Format 'yyyy-MM-dd')

    Run this script with privileges that allow access to the source path
    and write permissions to the destination path (typically SYSTEM context in TS).
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]$SourcePath,

    [Parameter(Mandatory = $true)]
    [string]$DestinationPath,

    [Parameter(Mandatory = $true)]
    [string]$LogPath
)

# --- Script Configuration ---
BEGIN {
    $ErrorActionPreference = 'Stop'
    # The main Invoke-Customizations.ps1 script already creates a Logs folder.
    # This script will place its specific Robocopy log inside that.
    $RoboLogFile = Join-Path -Path $LogPath -ChildPath "Robocopy_DOTemp_$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

    Function Write-SubLog { # Using a different name to avoid conflict if sourced directly
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            [string]$Message,
            [ValidateSet("INFO", "WARN", "ERROR")]
            [string]$Level = "INFO"
        )
        # This script's own log (minimal, as Robocopy does the heavy lifting)
        $OwnScriptLogFile = Join-Path -Path $LogPath -ChildPath "Copy-DOTempFolder_$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
        $LogEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] - $Message"
        Add-Content -Path $OwnScriptLogFile -Value $LogEntry -ErrorAction SilentlyContinue
        Write-Host $LogEntry
    }
}

# --- Main Processing Block ---
PROCESS {
    Write-SubLog "Starting folder copy process..."
    Write-SubLog "Source: $SourcePath"
    Write-SubLog "Destination: $DestinationPath"
    Write-SubLog "Robocopy Log File: $RoboLogFile"

    if (-not (Test-Path -Path $SourcePath)) {
        Write-SubLog "Source path '$SourcePath' not found or not accessible. Skipping copy." -Level ERROR
        # Optionally, throw an error to stop the main script if this is critical
        # throw "Source path '$SourcePath' not found."
        return # Exit this script
    }

    # Ensure destination parent directory exists, Robocopy might not create the root of $DestinationPath if it's multiple levels deep
    $ParentDestination = Split-Path -Path $DestinationPath
    if ($ParentDestination -and (-not (Test-Path -Path $ParentDestination))) {
        try {
            Write-SubLog "Parent destination directory '$ParentDestination' does not exist. Attempting to create."
            New-Item -ItemType Directory -Path $ParentDestination -Force -ErrorAction Stop | Out-Null
            Write-SubLog "Successfully created parent destination directory '$ParentDestination'."
        } catch {
            Write-SubLog "Failed to create parent destination directory '$ParentDestination'. Error: $($_.Exception.Message)" -Level ERROR
            throw "Failed to create parent destination directory '$ParentDestination'."
        }
    }

    # Robocopy switches:
    # /E :: copy subdirectories, including Empty ones.
    # /COPYALL :: COPY ALL file info (equivalent to /COPY:DATSOU). Consider /COPY:DATS for standard needs to avoid potential permission issues with Owner/Audit info.
    # /R:3 :: Retry 3 times on failed copies.
    # /W:5 :: Wait 5 seconds between retries.
    # /NJH :: No Job Header.
    # /NJS :: No Job Summary.
    # /NDL :: No Directory List - don't log directory names.
    # /NP :: No Progress - don't display percentage copied.
    # /LOG:$RoboLogFile :: Log output to file (overwrite). Use /LOG+ for append.
    # /TEE :: output to console window, as well as the log file.
    # Add /CREATE if you want to copy directory structure and zero-byte files only.
    # Add /PURGE or /MIR if you want to delete files/dirs in destination that no longer exist in source. Use with caution.
    $RobocopyArguments = @(
        "$SourcePath",
        "$DestinationPath",
        "/E",          # Copy subdirectories, including empty ones
        "/COPY:DATS",  # Copy Data, Attributes, Timestamps, Security (ACLs). Excludes Owner (O) and Auditing info (U) which can sometimes cause issues.
        "/R:2",        # Retry 2 times on errors
        "/W:5",        # Wait 5 seconds between retries
        "/NP",         # No progress
        "/NFL",        # No file list
        "/NDL",        # No directory list
        "/NJH",        # No job header
        "/NJS",        # No job summary (optional, but makes log cleaner for just errors)
        "/LOG:$RoboLogFile" # Log file
        # "/TEE"       # Uncomment to also see Robocopy output in console (can be verbose)
    )

    Write-SubLog "Executing Robocopy: robocopy $($RobocopyArguments -join ' ')"

    try {
        $Process = Start-Process -FilePath "robocopy.exe" -ArgumentList $RobocopyArguments -Wait -PassThru -ErrorAction Stop

        # Robocopy Exit Codes:
        # 0  = No Change. No files copied.
        # 1  = Files copied successfully.
        # 2  = Extra files or directories detected.
        # 3  = (2+1) Files copied successfully, some extra files detected.
        # Higher bits (4, 8, 16) indicate issues:
        # 4  = Mismatched files/directories detected.
        # 5  = (4+1) Files copied, some mismatches.
        # 6  = (4+2) Extra files and mismatches.
        # 7  = (4+2+1) Files copied, extra files, and mismatches.
        # 8  = Some files or directories could not be copied (copy errors occurred and the retry limit was exceeded).
        # 16 = Serious error. Robocopy did not copy any files.

        Write-SubLog "Robocopy finished with Exit Code: $($Process.ExitCode)."
        if ($Process.ExitCode -ge 8) {
            Write-SubLog "Robocopy indicated errors (Exit Code >= 8). Check log: $RoboLogFile" -Level ERROR
            # You might want to throw an error here if any failure is critical
            # throw "Robocopy failed with exit code $($Process.ExitCode). Check log $RoboLogFile for details."
        } elseif ($Process.ExitCode -ge 4) {
            Write-SubLog "Robocopy indicated some mismatches or extra files (Exit Code 4-7). Check log: $RoboLogFile" -Level WARN
        } else {
            Write-SubLog "Robocopy completed successfully (Exit Code 0-3)."
        }
    } catch {
        Write-SubLog "Exception during Robocopy execution: $($_.Exception.Message)" -Level ERROR
        # throw "Failed to execute Robocopy. $($_.Exception.Message)"
    }

    Write-SubLog "Folder copy process finished."
}

END {
    Write-SubLog "Copy-DOTempFolder.ps1 script completed."
}
