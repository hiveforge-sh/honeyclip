#Requires -Version 5.1
<#
.SYNOPSIS
    Bootstrap script for honeyclip on Windows
.DESCRIPTION
    Installs Nim and system dependencies for building honeyclip on Windows.
    Automatically installs missing tools via Chocolatey when run as administrator.
    
    IMPORTANT: Run this in PowerShell, NOT Git Bash!
    
.EXAMPLE
    .\bootstrap.ps1
    Run as regular user (manual install prompts for missing tools)
    
.EXAMPLE
    Start-Process powershell -Verb RunAs -ArgumentList "-File $PWD\bootstrap.ps1"
    Run as administrator (automatic installation of missing tools)
    
.EXAMPLE
    # From Git Bash, launch PowerShell to run this script:
    powershell.exe -ExecutionPolicy Bypass -File ./bootstrap.ps1
    
.NOTES
    If you see "syntax error near unexpected token", you're in Git Bash.
    Open PowerShell and run this script there instead.
#>

$ErrorActionPreference = "Stop"

# Colors for output
function Write-Info { param($Message) Write-Host "[INFO] $Message" -ForegroundColor Green }
function Write-Warn { param($Message) Write-Host "[WARN] $Message" -ForegroundColor Yellow }
function Write-Err { param($Message) Write-Host "[ERROR] $Message" -ForegroundColor Red; exit 1 }

# Check if a command exists
function Test-Command {
    param($Command)
    $null -ne (Get-Command $Command -ErrorAction SilentlyContinue)
}

# Install Nim via choosenim
function Install-Nim {
    if (Test-Command "nim") {
        $version = & nim --version | Select-Object -First 1
        Write-Info "Nim already installed: $version"
        return
    }

    Write-Info "Installing Nim via choosenim..."

    if (Test-Command "choosenim") {
        & choosenim stable
    } else {
        # Download and run choosenim installer
        $installerUrl = "https://nim-lang.org/choosenim/init.ps1"
        $installerPath = "$env:TEMP\choosenim_init.ps1"

        try {
            Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing
            & powershell -ExecutionPolicy Bypass -File $installerPath -ChooseNimVersion stable
        } catch {
            Write-Err "Failed to download choosenim. Please install Nim manually from https://nim-lang.org/install.html"
        }
    }

    # Refresh PATH
    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "User") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "Machine")

    if (Test-Command "nim") {
        $version = & nim --version | Select-Object -First 1
        Write-Info "Nim installed successfully: $version"
    } else {
        Write-Host ""
        Write-Host "==========================================" -ForegroundColor Yellow
        Write-Host "  ACTION REQUIRED: Add Nim to your PATH" -ForegroundColor Yellow
        Write-Host "==========================================" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  Run this command in PowerShell:" -ForegroundColor Cyan
        Write-Host '  $env:PATH += ";$env:USERPROFILE\.nimble\bin"' -ForegroundColor Green
        Write-Host ""
        Write-Host "  To make it permanent, add to your PowerShell profile:" -ForegroundColor Cyan
        Write-Host '  [System.Environment]::SetEnvironmentVariable("PATH", $env:PATH + ";$env:USERPROFILE\.nimble\bin", "User")' -ForegroundColor Green
        Write-Host ""
        Write-Host "  Or restart your terminal to pick up the new PATH." -ForegroundColor Cyan
        Write-Host ""
    }
}

# Install Python packages (meson, ninja)
function Install-PythonDeps {
    Write-Info "Checking Python dependencies..."

    if (-not (Test-Python)) {
        Write-Warn "Skipping Python dependencies (Python not found)"
        return
    }

    $pip = $null
    if (Test-Command "pip3") { $pip = "pip3" }
    elseif (Test-Command "pip") { $pip = "pip" }
    else {
        Write-Warn "pip not found. Please ensure Python is installed correctly."
        return
    }

    $needInstall = @()
    if (-not (Test-Command "meson")) { $needInstall += "meson" }
    if (-not (Test-Command "ninja")) { $needInstall += "ninja" }

    if ($needInstall.Count -gt 0) {
        Write-Info "Installing via pip: $($needInstall -join ', ')"
        try {
            & $pip install --user $needInstall
            
            # Add Python Scripts to PATH if not already there
            $pythonScripts = "$env:APPDATA\Python\Python314\Scripts"
            if ((Test-Path $pythonScripts) -and ($env:PATH -notlike "*$pythonScripts*")) {
                $env:PATH += ";$pythonScripts"
            }
        } catch {
            Write-Warn "Failed to install Python packages: $_"
        }
    } else {
        Write-Info "meson and ninja already installed"
    }
}

# Install Chocolatey if not present
function Install-Chocolatey {
    if (Test-Command "choco") {
        Write-Info "Chocolatey already installed"
        return
    }

    Write-Info "Chocolatey not found. Installing Chocolatey..."
    Write-Host "  This requires administrator privileges." -ForegroundColor Yellow
    Write-Host ""

    try {
        # Check if running as administrator
        $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        
        if (-not $isAdmin) {
            Write-Warn "Not running as administrator. Chocolatey installation requires admin rights."
            Write-Host ""
            Write-Host "  Please re-run this script as administrator, or install Chocolatey manually:" -ForegroundColor Cyan
            Write-Host "  https://chocolatey.org/install" -ForegroundColor Green
            Write-Host ""
            return
        }

        # Install Chocolatey
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

        # Refresh environment variables
        $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "User") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "Machine")
        
        if (Test-Command "choco") {
            Write-Info "Chocolatey installed successfully"
        } else {
            Write-Warn "Chocolatey installation completed but not in PATH. Please restart your terminal."
        }
    } catch {
        Write-Warn "Failed to install Chocolatey automatically: $_"
        Write-Host "  Please install manually from: https://chocolatey.org/install" -ForegroundColor Cyan
    }
}

# Install system dependencies via Chocolatey
function Install-SystemDeps {
    Write-Info "Checking system dependencies..."

    # Map of command -> chocolatey package name
    $deps = @{
        "cmake" = "cmake"
        "nasm" = "nasm"
        "pkg-config" = "pkgconfiglite"
        "git" = "git"
    }

    $missing = @()
    foreach ($cmd in $deps.Keys) {
        if (-not (Test-Command $cmd)) {
            $missing += $deps[$cmd]
        }
    }

    if ($missing.Count -eq 0) {
        Write-Info "All system dependencies already installed"
        return
    }

    # Try to install via Chocolatey
    if (-not (Test-Command "choco")) {
        Write-Warn "Chocolatey not available. Missing tools: $($missing -join ', ')"
        Write-Host ""
        Write-Host "  Please install Chocolatey (https://chocolatey.org/install) or install manually:" -ForegroundColor Cyan
        foreach ($pkg in $missing) {
            Write-Host "    - $pkg" -ForegroundColor Yellow
        }
        Write-Host ""
        return
    }

    # Check if running as administrator
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    if (-not $isAdmin) {
        Write-Warn "Not running as administrator. Cannot install packages via Chocolatey."
        Write-Host ""
        Write-Host "  Please re-run this script as administrator, or install manually:" -ForegroundColor Cyan
        Write-Host "  choco install $($missing -join ' ') -y" -ForegroundColor Green
        Write-Host ""
        return
    }

    # Install missing packages
    Write-Info "Installing via Chocolatey: $($missing -join ', ')"
    try {
        & choco install $missing -y
        
        # Refresh PATH
        $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "User") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "Machine")
        
        Write-Info "System dependencies installed successfully"
    } catch {
        Write-Warn "Failed to install some packages: $_"
        Write-Host "  You may need to install them manually." -ForegroundColor Yellow
    }
}

# Check for Python (can't install via Chocolatey as it needs to be in PATH before other deps)
function Test-Python {
    if (Test-Command "python") {
        return $true
    }
    if (Test-Command "python3") {
        return $true
    }

    Write-Warn "Python not found. Python 3.14+ is required."
    Write-Host ""
    Write-Host "  Install manually from: https://python.org" -ForegroundColor Cyan
    Write-Host "  Or via Chocolatey (as administrator):" -ForegroundColor Cyan
    Write-Host "    choco install python -y" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Make sure to check 'Add Python to PATH' during installation!" -ForegroundColor Yellow
    Write-Host ""
    return $false
}

# Download Whisper model for speech analysis
function Install-WhisperModel {
    $modelDir = "$env:USERPROFILE\.cache\whisper"
    $modelFile = "$modelDir\ggml-base.en.bin"
    $modelUrl = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin"

    if (Test-Path $modelFile) {
        Write-Info "Whisper model already downloaded"
        return
    }

    Write-Host ""
    Write-Host "Optional: Download Whisper model for speech analysis" -ForegroundColor Yellow
    Write-Host "  Model: ggml-base.en.bin (~142MB)"
    Write-Host "  For better accuracy, manually download ggml-small.en.bin (~466MB)"
    Write-Host "  or ggml-medium.en.bin (~1.5GB) from:"
    Write-Host "  https://huggingface.co/ggerganov/whisper.cpp"
    Write-Host ""

    $response = Read-Host "Download base model now? [y/N]"
    Write-Host ""  # Add blank line for cleaner output
    if ($response -eq 'y' -or $response -eq 'Y') {
        Write-Info "Downloading Whisper model..."
        try {
            New-Item -ItemType Directory -Force -Path $modelDir | Out-Null
            Invoke-WebRequest -Uri $modelUrl -OutFile $modelFile -UseBasicParsing
            Write-Info "Whisper model downloaded to $modelFile"
        } catch {
            Write-Warn "Failed to download Whisper model. You can download it manually later."
        }
    } else {
        Write-Info "Skipping Whisper model download"
    }
}

# Print post-install instructions
function Write-Instructions {
    Write-Host ""
    Write-Info "Bootstrap complete!"
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  1. Build FFmpeg and dependencies (run in Git Bash, takes 1-2 hours):"
    Write-Host "     nimble makeff" -ForegroundColor Green
    Write-Host ""
    Write-Host "  2. Build honeyclip:"
    Write-Host "     nimble make" -ForegroundColor Green
    Write-Host "     (ML features are stubbed on Windows)"
    Write-Host ""
    Write-Host "  3. Download Whisper model (if not already done):"
    Write-Host "     mkdir -p ~/.cache/whisper" -ForegroundColor Green
    Write-Host "     curl -L -o ~/.cache/whisper/ggml-base.en.bin ``" -ForegroundColor Green
    Write-Host "       https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin" -ForegroundColor Green
    Write-Host ""
    Write-Host "  4. Run tests:"
    Write-Host "     nimble test" -ForegroundColor Green
    Write-Host ""
    Write-Host "Note: 'nimble makeff' must be run in Git Bash, not PowerShell." -ForegroundColor Yellow
    Write-Host ""
}

# Main
function Main {
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "  honeyclip bootstrap script (Windows)" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "NOTE: This is a PowerShell script (.ps1)" -ForegroundColor Yellow
    Write-Host "      If you're in Git Bash, run: powershell.exe -File ./bootstrap.ps1" -ForegroundColor Yellow
    Write-Host ""

    # Check if running as administrator
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    if ($isAdmin) {
        Write-Host "Running with administrator privileges" -ForegroundColor Green
        Write-Host ""
    } else {
        Write-Host "Note: Running without administrator privileges" -ForegroundColor Yellow
        Write-Host "  Some automatic installations may be skipped." -ForegroundColor Yellow
        Write-Host "  Re-run as administrator for full automation." -ForegroundColor Yellow
        Write-Host ""
    }

    Install-Chocolatey
    Install-SystemDeps
    Install-PythonDeps
    Install-Nim
    Install-WhisperModel
    Write-Instructions
}

Main
