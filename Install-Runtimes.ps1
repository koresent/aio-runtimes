#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Installs runtime packages from a remote GitHub ZIP archive.
.PARAMETER NonInteractive
    Run without user interaction.
#>
param(
    [switch]$NonInteractive
)

# Configuration
$regPath = "HKLM:\SOFTWARE\aio-runtimes"
$repoZipUrl = "https://github.com/koresent/aio-runtimes/releases/download/latest/aio-runtimes.zip"
$tempDir = Join-Path $env:TEMP "aio-runtimes-$(Get-Random)"
$global:rebootRequired = $false
$ProgressPreference = 'SilentlyContinue'

# Functions
function Write-ProgressLine {
    param(
        [int]$Index,
        [int]$Total,
        [string]$Name,
        [string]$Status = "RUNNING",
        [string]$ExtraInfo = ""
    )
    
    $progressStr = "[{0:D2}/{1:D2}]" -f $Index, $Total
    
    switch ($Status) {
        "RUNNING" { 
            $Icon = ".." 
            $Color = "Cyan"
            $NoNewline = $true
        }
        "DONE" { 
            $Icon = "OK" 
            $Color = "Green"
            $NoNewline = $false
        }
        "REBOOT" { 
            $Icon = "RB" 
            $Color = "Yellow"
            $NoNewline = $false
        }
        "FAIL" { 
            $Icon = "ER" 
            $Color = "Red"
            $NoNewline = $false
        }
    }

    if ($Status -ne "RUNNING") {
        Write-Host "`r" -NoNewline
    }

    $message = "[$Icon] $progressStr $Name $ExtraInfo" 
    $pad = " " * ([Math]::Max(0, 80 - $message.Length)) 
    
    Write-Host "$message$pad" -ForegroundColor $Color -NoNewline:$NoNewline
    
    if (!($NoNewline)) { Write-Host "" }
}

function Invoke-Installer {
    param (
        [string]$FilePath,
        [string[]]$Arguments,
        [string]$WorkDir = $null
    )

    $startParams = @{
        FilePath     = $FilePath
        ArgumentList = $Arguments
        Wait         = $true
        PassThru     = $true
        NoNewWindow  = $true
        ErrorAction  = "Stop"
    }
    
    if ($WorkDir) { $startParams.WorkingDirectory = $WorkDir }

    $process = Start-Process @startParams
    return $process.ExitCode
}

function Install-Package {
    param (
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo]$File,

        [int]$Index,
        [int]$Total
    )

    $pkgName = $File.Name
    $dirName = $File.Directory.Name
    $displayName = "$dirName - $pkgName"
    
    if ($displayName.Length -gt 50) { $displayName = $displayName.Substring(0, 47) + "..." }

    Write-ProgressLine -Index $Index -Total $Total -Name $displayName -Status "RUNNING"

    $argsList = @()
    $exePath = $File.FullName
    $workDir = $File.DirectoryName
    $isDirectX = ($dirName -match "DirectX" -and $File.Name -match "Jun2010")

    try {
        if ($File.Extension -eq ".msi") {
            $exePath = "msiexec.exe"
            $argsList = "/i", "`"$($File.FullName)`"", "/qn", "/norestart"
        }
        elseif ($isDirectX) {
            $dxTemp = Join-Path $env:TEMP "dx-extract-$(Get-Random)"
            New-Item -ItemType Directory -Path $dxTemp -Force | Out-Null
            
            $extractArgs = "/Q", "/T:$dxTemp"
            Invoke-Installer -FilePath $File.FullName -Arguments $extractArgs | Out-Null
            
            $exePath = Join-Path $dxTemp "DXSETUP.exe"
            if (!(Test-Path $exePath)) {
                Write-Warning "⚠️ DXSETUP.exe not found after extraction."
            }
            $argsList = "/Silent"
        }
        else {
            switch -Wildcard ($dirName) {
                "*Visual C++*" {
                    if ($File.Name -match "2005|2008|2010|2012|2013") {
                        $argsList = "/q", "/norestart"
                    }
                    else {
                        $argsList = "/quiet", "/norestart"
                    }
                }
                "*.NET Framework*" { $argsList = "/quiet", "/norestart" }
                "*OpenAL*" { $argsList = "/silent" }
                default { $argsList = "/quiet", "/norestart" }
            }
        }

        $exitCode = Invoke-Installer -FilePath $exePath -Arguments $argsList -WorkDir $workDir

        switch ($exitCode) {
            0 { 
                Write-ProgressLine -Index $Index -Total $Total -Name $displayName -Status "DONE" 
            }
            3010 { 
                Write-ProgressLine -Index $Index -Total $Total -Name $displayName -Status "REBOOT" 
                $global:rebootRequired = $true
            }
            1638 {
                Write-ProgressLine -Index $Index -Total $Total -Name $displayName -Status "DONE" -ExtraInfo "(Already installed)"
            }
            default { 
                Write-ProgressLine -Index $Index -Total $Total -Name $displayName -Status "FAIL" -ExtraInfo "(Exit: $exitCode)"
            }
        }
    }
    catch {
        Write-ProgressLine -Index $Index -Total $Total -Name $displayName -Status "FAIL" -ExtraInfo "($($_.Exception.Message))"
    }
    finally {
        if ($isDirectX -and $dxTemp -and (Test-Path $dxTemp)) {
            Remove-Item -Path $dxTemp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

if (Test-Path $regPath) {
    if ($NonInteractive) { exit 0 }
    else {
        Write-Host "Previous installation detected." -ForegroundColor Yellow
        $response = Read-Host "Do you want to reinstall all components? (Y/N)"
        if ($response -notin "Y", "y", "Yes", "yes") {
            Write-Host "Installation cancelled." -ForegroundColor Gray
            exit 0
        }
    }
}

try {
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    $zipPath = Join-Path $tempDir "main.zip"

    Write-Host "⬇️ Downloading archive..." -ForegroundColor Cyan
    Invoke-RestMethod -Uri $repoZipUrl -OutFile $zipPath
        
    Write-Host "📤 Extracting archive..." -ForegroundColor Cyan
    Expand-Archive -Path $zipPath -DestinationPath $tempDir -Force
        
    $extractedRoot = (Get-ChildItem -Path $tempDir -Directory)[0]
    $baseDir = $extractedRoot.FullName
    $redistFolder = Join-Path $baseDir "Redist"
    
    if (!(Test-Path $redistFolder)) {
        throw "⛔ Critical Error: 'Redist' folder not found inside downloaded package."
    }

    $files = Get-ChildItem -Path $redistFolder -Include *.exe, *.msi -Recurse -File | Sort-Object DirectoryName, Name

    if (!($files)) { throw "⛔ No installer files found." }
    
    $totalFiles = $files.Count
    $counter = 0
    
    Write-Host "📦 Starting installation ($totalFiles packages)..." -ForegroundColor Cyan
    Write-Host "----------------------------------------------------" -ForegroundColor Gray

    foreach ($file in $files) {
        $counter++
        Install-Package -File $file -Index $counter -Total $totalFiles
    }
    
    Write-Host "----------------------------------------------------" -ForegroundColor Gray
    
    Write-Host "📦 Ensuring .NET Framework 3.5 is enabled..."
    $net35 = Get-WindowsOptionalFeature -Online -FeatureName "NetFx3"
    if ($net35.State -ne "Enabled") {
        Enable-WindowsOptionalFeature -Online -FeatureName "NetFx3" -NoRestart | Out-Null
        Write-Host "   Done." -ForegroundColor Green
    }
    else {
        Write-Host "   Already enabled." -ForegroundColor Green
    }
    
    if (!(Test-Path $regPath)) {
        New-Item -Path $regPath -Force | Out-Null
    }

    if ($global:rebootRequired) {
        Write-Host "⚠️  A reboot requires to complete installation of some components." -ForegroundColor Yellow
        if (!$NonInteractive) {
            $rb = Read-Host "Reboot now? (Y/N)"
            if ($rb -in "Y", "y") { Restart-Computer }
        }
    }
    else {
        Write-Host "✅ Installation completed successfully." -ForegroundColor Green
    }

} 
catch {
    Write-Error "⛔ Fatal Error: $_"
    exit 1
}
finally {
    if (Test-Path $tempDir) {
        Write-Host "🧹 Cleaning up..." -ForegroundColor Gray
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}