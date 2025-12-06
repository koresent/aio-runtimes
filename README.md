# AIO Runtimes Installer

A simple PowerShell script designed to quickly download and silently install common runtime libraries required for games and software.

It automates the entire process: downloading the repository, extracting files, installing packages silently, enabling .NET Framework 3.5, and cleaning up temporary files.

### Included Components

  * **Visual C++ Redistributables** (2005 – 2022, x86/x64)
  * **.NET Desktop Runtimes** (4.8, 6.0, 8.0, 10.0)
  * **DirectX End-User Runtimes** (June 2010)
  * **Java Runtime Environment** (8, 17, 21)
  * **Legacy components:** OpenAL, PhysX (Legacy), XNA Framework 4.0

### How to Run

Open **PowerShell as Administrator** and paste the following command:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; irm https://r.koresent.ru/aio-runtimes | iex
```

### Notes

  * **Admin Rights:** The script requires Administrator privileges to install packages and modify Windows features.
  * **Registry Check:** It creates a key at `HKLM:\SOFTWARE\aio-runtimes` to prevent accidental re-installation.
  * **Non-Interactive:** You can run it with `-NonInteractive` switch if calling from another script.