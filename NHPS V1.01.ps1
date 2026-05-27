<#
.SYNOPSIS
    Installs all EXE installers from a specified folder.

.DESCRIPTION
    This script searches the installation folder for .exe files and runs them one at a time.
    It checks that PowerShell is running as Administrator, applies installer-specific silent
    switches when configured, logs results to a PC-specific log file, and continues to the
    next installer when an install is skipped or fails.

.NOTES
    Log file format:
        COMPUTERNAME_InstallLog.txt

    Important:
        Silent install switches are different depending on the installer.
        Update the $InstallerArguments table as needed.
#>

# =========================================================
# Configuration
# =========================================================

$InstallerFolder = "C:\Users\WDAGUtilityAccount\Desktop\Instalation"
$PCName = $env:COMPUTERNAME
$LogFile = Join-Path -Path $InstallerFolder -ChildPath "$PCName`_InstallLog.txt"

# Default silent arguments used when the installer is not listed below
$DefaultArguments = "/silent /norestart"

# Installer-specific silent switches
# Edit these values as needed after confirming the correct silent switch for each installer.
$InstallerArguments = @{
    "ChromeSetup.exe"                 = "/silent /install"
    "GlassTraxUpdate1.35.2214.exe"    = "/silent /norestart"
    "zsu-1191297.exe"                 = "/silent /norestart"
    "AnyDesk.exe"                    = "--silent"
    "Notion Setup 2.0.29.exe"         = "/S"
}

# Tracks whether any installer reported that a reboot is needed
$RebootRequired = $false

# =========================================================
# Function: Write to screen and log file
# =========================================================

function Write-Log {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [string]$Color = "White"
    )

    Write-Host $Message -ForegroundColor $Color
    $Message | Out-File -FilePath $LogFile -Append
}

# =========================================================
# Admin Rights Check
# =========================================================

$IsAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $IsAdmin) {
    Write-Host "ERROR: PowerShell is not running as Administrator." -ForegroundColor Red
    Write-Host "Right-click PowerShell and choose 'Run as administrator'." -ForegroundColor Yellow
    exit 1
}

# =========================================================
# Folder Check
# =========================================================

if (-not (Test-Path -Path $InstallerFolder)) {
    Write-Host "ERROR: Installer folder was not found: $InstallerFolder" -ForegroundColor Red
    exit 1
}

# =========================================================
# Get EXE Files
# =========================================================

$Executables = Get-ChildItem -Path $InstallerFolder -Filter *.exe -File -ErrorAction Stop

if ($Executables.Count -eq 0) {
    Write-Host "No EXE files found in $InstallerFolder" -ForegroundColor Yellow
    exit 0
}

# =========================================================
# Start Log
# =========================================================

"===== Install Log Started: $(Get-Date) =====" | Out-File -FilePath $LogFile -Append
"Computer Name: $PCName" | Out-File -FilePath $LogFile -Append
"Running As: $env:USERDOMAIN\$env:USERNAME" | Out-File -FilePath $LogFile -Append
"Installer Folder: $InstallerFolder" | Out-File -FilePath $LogFile -Append
"" | Out-File -FilePath $LogFile -Append

# =========================================================
# Install Each EXE
# =========================================================

foreach ($Exe in $Executables) {

    Write-Host ""
    Write-Log -Message "Installing: $($Exe.Name)" -Color "Cyan"

    # Use installer-specific arguments when available; otherwise use default arguments.
    if ($InstallerArguments.ContainsKey($Exe.Name)) {
        $Arguments = $InstallerArguments[$Exe.Name]
    }
    else {
        $Arguments = $DefaultArguments
    }

    Write-Log -Message "$(Get-Date) STARTED - $($Exe.Name) - Arguments: $Arguments" -Color "DarkGray"

    try {
        $Process = Start-Process `
            -FilePath $Exe.FullName `
            -ArgumentList $Arguments `
            -Wait `
            -PassThru `
            -ErrorAction Stop

        $ExitCode = $Process.ExitCode

        switch ($ExitCode) {

            0 {
                Write-Log -Message "$(Get-Date) SUCCESS - $($Exe.Name) - ExitCode: $ExitCode" -Color "Green"
            }

            3010 {
                $RebootRequired = $true
                Write-Log -Message "$(Get-Date) SUCCESS-REBOOT REQUIRED - $($Exe.Name) - ExitCode: $ExitCode" -Color "Yellow"
            }

            1641 {
                $RebootRequired = $true
                Write-Log -Message "$(Get-Date) SUCCESS-REBOOT INITIATED/REQUIRED - $($Exe.Name) - ExitCode: $ExitCode" -Color "Yellow"
            }

            default {
                Write-Log -Message "$(Get-Date) FAILED - $($Exe.Name) - ExitCode: $ExitCode" -Color "Red"

                Write-Host ""
                Write-Host "[S] Skip  [R] Retry  [Q] Quit" -ForegroundColor Yellow
                $Choice = Read-Host "Choose option"

                switch ($Choice.ToUpper()) {

                    "R" {
                        Write-Log -Message "$(Get-Date) RETRYING - $($Exe.Name)" -Color "Yellow"

                        $RetryProcess = Start-Process `
                            -FilePath $Exe.FullName `
                            -ArgumentList $Arguments `
                            -Wait `
                            -PassThru `
                            -ErrorAction Stop

                        $RetryExitCode = $RetryProcess.ExitCode
                        Write-Log -Message "$(Get-Date) RETRY RESULT - $($Exe.Name) - ExitCode: $RetryExitCode" -Color "Yellow"

                        if ($RetryExitCode -eq 3010 -or $RetryExitCode -eq 1641) {
                            $RebootRequired = $true
                        }
                    }

                    "Q" {
                        Write-Log -Message "$(Get-Date) USER QUIT INSTALLATION" -Color "Red"
                        exit 1
                    }

                    default {
                        Write-Log -Message "$(Get-Date) SKIPPED - $($Exe.Name)" -Color "Yellow"
                        continue
                    }
                }
            }
        }
    }
    catch {
        Write-Log -Message "$(Get-Date) ERROR - $($Exe.Name) - $($_.Exception.Message)" -Color "Red"

        Write-Host ""
        Write-Host "[S] Skip  [Q] Quit" -ForegroundColor Yellow
        $Choice = Read-Host "Choose option"

        if ($Choice.ToUpper() -eq "Q") {
            Write-Log -Message "$(Get-Date) USER QUIT INSTALLATION" -Color "Red"
            exit 1
        }
        else {
            Write-Log -Message "$(Get-Date) SKIPPED - $($Exe.Name)" -Color "Yellow"
            continue
        }
    }
}

# =========================================================
# Finish Log
# =========================================================

"" | Out-File -FilePath $LogFile -Append

if ($RebootRequired) {
    Write-Log -Message "REBOOT REQUIRED: Yes" -Color "Yellow"
    Write-Host ""
    Write-Host "WARNING: One or more installations require a reboot." -ForegroundColor Yellow
}
else {
    Write-Log -Message "REBOOT REQUIRED: No" -Color "Green"
}

"===== Install Log Finished: $(Get-Date) =====" | Out-File -FilePath $LogFile -Append

Write-Host ""
Write-Host "All installations complete." -ForegroundColor Green
Write-Host "Log File: $LogFile" -ForegroundColor Cyan
