# Install All EXEs Script - README

## Overview

This PowerShell script automatically installs all `.exe` files located in a specified folder. It includes:

* Administrator privilege validation
* Per-installer silent install arguments
* Detailed logging
* Error handling
* Retry, Skip, and Quit options
* Reboot detection and warning
* PC-name-based log files

---

# Features

## Automatic EXE Detection

The script scans the configured installation directory for all `.exe` files.

Example:

```powershell
$Executables = Get-ChildItem -Path $InstallerFolder -Filter *.exe -File
```

---

## Administrator Rights Validation

The script checks whether PowerShell is running as Administrator before continuing.

If PowerShell is not elevated, the script exits safely.

---

## Per-Installer Silent Switch Support

Different installers require different silent install switches.

The script allows custom arguments per installer:

```powershell
$InstallerArguments = @{
    "ChromeSetup.exe"              = "/silent /install"
    "GlassTraxUpdate1.35.2214.exe" = "/silent /norestart"
    "zsu-1191297.exe"              = "/silent /norestart"
}
```

Any installer not listed uses the default arguments:

```powershell
$DefaultArguments = "/silent /norestart"
```

---

## Logging

A detailed log file is created automatically.

Log file format:

```text
COMPUTERNAME_InstallLog.txt
```

Example:

```text
DESKTOP-01_InstallLog.txt
```

The log includes:

* Start time
* End time
* Computer name
* User account running the script
* Installer name
* Silent arguments used
* Exit codes
* Errors
* Retry attempts
* Skipped installations
* Reboot requirements

---

## Error Handling

If an installer fails, the script provides options:

```text
[S] Skip
[R] Retry
[Q] Quit
```

This prevents one failed installer from stopping the entire deployment.

---

## Reboot Detection

The script detects common reboot-required exit codes:

| Exit Code | Meaning                   |
| --------- | ------------------------- |
| 3010      | Reboot required           |
| 1641      | Reboot initiated/required |

At the end of execution, the script warns the user if a reboot is needed.

---

# Installation Folder Configuration

Current example:

```powershell
$InstallerFolder = "C:\Users\WDAGUtilityAccount\Desktop\Instalation"
```

For production environments, UNC paths are recommended.

Recommended:

```powershell
$InstallerFolder = "\\FileServer01\Software\Installers"
```

Avoid mapped drives when running elevated PowerShell sessions.

---

# Recommended Silent Switch Testing

Before adding an installer to production deployment, test supported silent switches manually.

Common tests:

```powershell
Installer.exe /?
Installer.exe -?
Installer.exe /help
```

Common silent switches:

| Installer Type          | Common Switch |
| ----------------------- | ------------- |
| NSIS                    | /S            |
| MSI Wrapper             | /quiet        |
| InstallShield           | /s            |
| Custom Vendor Installer | /silent       |

---

# Best Practices

## Recommended

* Run PowerShell as Administrator
* Use local admin or deployment accounts instead of Domain Admin when possible
* Store installers in a secured folder
* Keep logs for troubleshooting
* Test installers individually before deployment
* Use UNC paths instead of mapped drives
* Verify installer hashes for production deployments

## Avoid

* Hardcoding passwords
* Running unknown EXE files
* Mixing production and test installers in the same folder
* Using inconsistent installer naming

---

# Common Troubleshooting

## Mapped Drive Not Found

Problem:

```text
Path not found
```

Cause:
Elevated PowerShell sessions cannot always see mapped drives.

Solution:
Use a UNC path.

Example:

```powershell
\\Server\Share\Installers
```

---

## Installer Does Not Install Silently

Problem:
Installer opens normal GUI.

Cause:
Incorrect silent switch.

Solution:
Check vendor documentation or test:

```powershell
Installer.exe /?
```

---

## Access Denied

Problem:

```text
Access is denied
```

Cause:
PowerShell not running elevated.

Solution:
Run PowerShell as Administrator.

---

# Example Workflow

1. Copy installers into the installation folder
2. Update installer silent switches if needed
3. Open PowerShell as Administrator
4. Run the script
5. Review the generated log file
6. Reboot if required

---

# Future Enhancement Suggestions

Potential future upgrades:

* Automatic software detection
* Installed application verification
* Installer hash verification
* HTML reporting
* Email notification support
* Parallel installations
* MSI support
* SCCM/Intune integration
* Scheduled deployment mode
* Centralized logging

---

# Exit Code Reference

| Exit Code | Meaning                   |
| --------- | ------------------------- |
| 0         | Success                   |
| 3010      | Success, reboot required  |
| 1641      | Success, reboot initiated |
| Other     | Installer-specific error  |

---

# Notes

This script is intended for internal administrative deployment use.

Always test installers in a non-production environment before large-scale deployment.
