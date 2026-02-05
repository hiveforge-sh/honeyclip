#Requires -Version 5.1
<#
.SYNOPSIS
    Bootstrap script for honeyclip on Windows
.DESCRIPTION
    Installs Nim and system dependencies for building honeyclip on Windows.
    Run this in PowerShell (not Git Bash).
.EXAMPLE
    .\bootstrap.ps1
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
        Write-Warn "Nim installed but not in PATH. You may need to restart your terminal."
        Write-Warn "Add %USERPROFILE%\.nimble\bin to your PATH"
    }
}

# Install Python packages (meson, ninja)
function Install-PythonDeps {
    Write-Info "Checking Python dependencies..."

    $pip = $null
    if (Test-Command "pip3") { $pip = "pip3" }
    elseif (Test-Command "pip") { $pip = "pip" }
    else {
        Write-Err "pip not found. Please install Python 3.14+ from https://python.org"
    }

    $needInstall = @()
    if (-not (Test-Command "meson")) { $needInstall += "meson" }
    if (-not (Test-Command "ninja")) { $needInstall += "ninja" }

    if ($needInstall.Count -gt 0) {
        Write-Info "Installing via pip: $($needInstall -join ', ')"
        & $pip install $needInstall
    } else {
        Write-Info "meson and ninja already installed"
    }
}

# Check for required tools
function Test-RequiredTools {
    Write-Info "Checking required tools..."

    $missing = @()

    if (-not (Test-Command "python") -and -not (Test-Command "python3")) {
        $missing += "Python (https://python.org)"
    }

    if (-not (Test-Command "git")) {
        $missing += "Git (https://git-scm.com)"
    }

    if (-not (Test-Command "cmake")) {
        $missing += "CMake (https://cmake.org/download/)"
    }

    if (-not (Test-Command "nasm")) {
        $missing += "NASM (https://nasm.us/)"
    }

    if ($missing.Count -gt 0) {
        Write-Warn "The following tools are missing or not in PATH:"
        foreach ($tool in $missing) {
            Write-Host "  - $tool" -ForegroundColor Yellow
        }
        Write-Host ""
        Write-Warn "Please install them before running 'nimble makeff'"
    } else {
        Write-Info "All required tools found"
    }
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

    Test-RequiredTools
    Install-PythonDeps
    Install-Nim
    Install-WhisperModel
    Write-Instructions
}

Main
