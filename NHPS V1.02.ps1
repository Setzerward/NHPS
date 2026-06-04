<#
.SYNOPSIS
    NHPS v1.02 - Installs approved EXE installers from the configured deployment folder.

.DESCRIPTION
    Scans the installer folder for .exe files, applies known silent-install arguments,
    runs each installer one at a time, logs results, and performs configured post-install
    actions for specific applications.

.NOTES
    Log file format:
        COMPUTERNAME_InstallLog.txt

    Update $InstallerFolder and $InstallerArguments as installers or paths change.
#>

# =========================================================
# Configuration
# =========================================================

$InstallerFolder = "\\10.10.200.241\apps\2021 Gt live update\IT Managment Folder_Non GT Information\Application Installs\NHPS Default Programs"
$PCName = $env:COMPUTERNAME
$LogFile = Join-Path -Path $InstallerFolder -ChildPath "$PCName`_InstallLog.txt"

# Used when an installer is not listed in $InstallerArguments.
$DefaultArguments = "/silent /norestart"

# Installer-specific silent switches. Confirm each switch before production use.
$InstallerArguments = @{
    "ChromeSetup.exe"                  = "/silent /install"
    "GlassTraxUpdate1.35.2214.exe"     = "/silent /norestart"
    "zsu-1191297.exe"                  = "/silent /norestart"
    "AnyDesk.exe"                      = "--silent"
    "Notion Setup 2.0.29.exe"          = "/S"
}

# Tracks whether any installer reports a reboot-required exit code.
$RebootRequired = $false

# =========================================================
# Logging
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
# Post-install action dispatcher
# =========================================================

function Invoke-PostInstallActions {
    param (
        [string]$InstallerName
    )

    # Add future installer-specific post-install tasks here.
    if ($InstallerName -eq "GlassTraxUpdate1.35.2214.exe") {
        Copy-GlassTraxDataPath
    }

    if ($InstallerName -eq "OfficeSetup.exe") {
        Set-OfficeProtectionPolicy
    }
}

# =========================================================
# GlassTrax post-install configuration
# =========================================================

function Copy-GlassTraxDataPath {

    $SourceFile = Join-Path $InstallerFolder "datapath.ini"
    $DestinationFolder = "C:\GTFiles"
    $DestinationFile = Join-Path $DestinationFolder "datapath.ini"

    try {
        # Create C:\GTFiles if it does not already exist.
        if (-not (Test-Path $DestinationFolder)) {
            New-Item -Path $DestinationFolder -ItemType Directory -Force | Out-Null
        }

        if (Test-Path $SourceFile) {
            Copy-Item -Path $SourceFile -Destination $DestinationFile -Force
            Write-Log -Message "$(Get-Date) POST-INSTALL COPY SUCCESS - datapath.ini copied to C:\GTFiles" -Color "Green"
        }
        else {
            Write-Log -Message "$(Get-Date) POST-INSTALL COPY FAILED - datapath.ini not found in installation folder" -Color "Red"
        }
    }
    catch {
        Write-Log -Message "$(Get-Date) POST-INSTALL COPY FAILED - $($_.Exception.Message)" -Color "Red"
    }
}

# =========================================================
# Office post-install configuration
# =========================================================

function Set-OfficeProtectionPolicy {

    $RegPath = "HKLM:\SOFTWARE\Microsoft\Cryptography\Protect\Providers\df9d8cd0-1501-11d1-8c7a-00c04fc297eb"
    $RegName = "ProtectionPolicy"
    $RegValue = 1

    try {
        # This Windows cryptography provider key is expected to already exist.
        if (-not (Test-Path $RegPath)) {
            Write-Log -Message "$(Get-Date) REGISTRY FAILED - Registry path not found: $RegPath" -Color "Red"
            return
        }

        New-ItemProperty -Path $RegPath -Name $RegName -Value $RegValue -PropertyType DWord -Force | Out-Null
        Write-Log -Message "$(Get-Date) REGISTRY SUCCESS - $RegName set to $RegValue" -Color "Green"
    }
    catch {
        Write-Log -Message "$(Get-Date) REGISTRY FAILED - $($_.Exception.Message)" -Color "Red"
    }
}

# =========================================================
# Self-elevation
# =========================================================

$IsAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $IsAdmin) {
    Write-Host "PowerShell is not running as Administrator. Relaunching elevated..." -ForegroundColor Yellow

    Start-Process powershell.exe `
        -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" `
        -Verb RunAs

    exit
}

# =========================================================
# Validate installer folder and collect EXEs
# =========================================================

if (-not (Test-Path -Path $InstallerFolder)) {
    Write-Host "ERROR: Installer folder was not found: $InstallerFolder" -ForegroundColor Red
    exit 1
}

$Executables = Get-ChildItem -Path $InstallerFolder -Filter *.exe -File -ErrorAction Stop

if ($Executables.Count -eq 0) {
    Write-Host "No EXE files found in $InstallerFolder" -ForegroundColor Yellow
    exit 0
}

# =========================================================
# Start log
# =========================================================

"===== Install Log Started: $(Get-Date) =====" | Out-File -FilePath $LogFile -Append
"Computer Name: $PCName" | Out-File -FilePath $LogFile -Append
"Running As: $env:USERDOMAIN\$env:USERNAME" | Out-File -FilePath $LogFile -Append
"Installer Folder: $InstallerFolder" | Out-File -FilePath $LogFile -Append
"" | Out-File -FilePath $LogFile -Append

# =========================================================
# Main install loop
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
                Invoke-PostInstallActions -InstallerName $Exe.Name
            }

            3010 {
                $RebootRequired = $true
                Write-Log -Message "$(Get-Date) SUCCESS-REBOOT REQUIRED - $($Exe.Name) - ExitCode: $ExitCode" -Color "Yellow"
                Invoke-PostInstallActions -InstallerName $Exe.Name
            }

            1641 {
                $RebootRequired = $true
                Write-Log -Message "$(Get-Date) SUCCESS-REBOOT INITIATED/REQUIRED - $($Exe.Name) - ExitCode: $ExitCode" -Color "Yellow"
                Invoke-PostInstallActions -InstallerName $Exe.Name
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

                        # Run post-install actions when retry succeeds or succeeds with reboot required.
                        if ($RetryExitCode -eq 0 -or $RetryExitCode -eq 3010 -or $RetryExitCode -eq 1641) {
                            Invoke-PostInstallActions -InstallerName $Exe.Name
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
# Finish log
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
