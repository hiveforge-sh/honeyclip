# PowerShell script for Windows prerequisite installation
# Run: .\scripts\prerequisites.ps1

$ErrorActionPreference = "Stop"

Write-Host "======================================" -ForegroundColor Cyan
Write-Host "  honeyclip Prerequisites Setup" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Platform: Windows" -ForegroundColor Yellow
Write-Host ""

$VenvDir = ".venv"
$VenvPython = "$VenvDir\Scripts\python.exe"
$VenvPip = "$VenvDir\Scripts\pip.exe"

# Step 1: Check Python
Write-Host "[1/4] Checking Python..." -ForegroundColor Cyan
$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) {
    Write-Host "ERROR: Python not found. Install from https://www.python.org/downloads/" -ForegroundColor Red
    exit 1
}
python --version

# Step 2: Create virtual environment
Write-Host ""
Write-Host "[2/4] Setting up virtual environment..." -ForegroundColor Cyan
if (-not (Test-Path $VenvDir)) {
    Write-Host "Creating virtual environment at $VenvDir..." -ForegroundColor Yellow
    python -m venv $VenvDir
    Write-Host "Virtual environment created!" -ForegroundColor Green
} else {
    Write-Host "Virtual environment already exists" -ForegroundColor Green
}

# Step 3: Install Python dependencies
Write-Host ""
Write-Host "[3/4] Installing Python dependencies..." -ForegroundColor Cyan
& $VenvPip install --upgrade pip
& $VenvPip install av pytest

# Step 4: Install pyannote.audio
Write-Host ""
Write-Host "[4/4] Installing pyannote.audio (speaker diarization)..." -ForegroundColor Cyan
Write-Host "Note: This downloads ~2GB (PyTorch + models)" -ForegroundColor Yellow

# Check for CUDA
$hasCuda = Get-Command nvidia-smi -ErrorAction SilentlyContinue
if ($hasCuda) {
    Write-Host "CUDA detected, installing GPU-enabled PyTorch" -ForegroundColor Green
    & $VenvPip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121
} else {
    Write-Host "No CUDA detected, installing CPU-only PyTorch" -ForegroundColor Yellow
    & $VenvPip install torch torchvision torchaudio
}
& $VenvPip install pyannote.audio

# Step 5: Install Nim dependencies
Write-Host ""
Write-Host "[5/5] Installing Nim dependencies..." -ForegroundColor Cyan
$nimble = Get-Command nimble -ErrorAction SilentlyContinue
if ($nimble) {
    nimble install -y nimpy checksums
    Write-Host "Nim dependencies installed!" -ForegroundColor Green
} else {
    Write-Host "Skipping: nimble not found (install Nim from https://nim-lang.org)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "======================================" -ForegroundColor Green
Write-Host "  Prerequisites installed!" -ForegroundColor Green
Write-Host "======================================" -ForegroundColor Green
Write-Host ""
Write-Host "To activate the virtual environment:" -ForegroundColor Yellow
Write-Host "  .venv\Scripts\Activate.ps1" -ForegroundColor Cyan
Write-Host ""
Write-Host "Remaining manual steps:" -ForegroundColor Yellow
Write-Host "  1. Get HuggingFace token:" -ForegroundColor White
Write-Host "     https://huggingface.co/settings/tokens" -ForegroundColor Cyan
Write-Host ""
Write-Host "  2. Accept pyannote model license:" -ForegroundColor White
Write-Host "     https://huggingface.co/pyannote/speaker-diarization-3.1" -ForegroundColor Cyan
Write-Host ""
Write-Host "  3. Set environment variable:" -ForegroundColor White
Write-Host '     $env:HF_TOKEN="your_token_here"' -ForegroundColor Cyan
Write-Host ""
Write-Host "  4. Verify setup:" -ForegroundColor White
Write-Host "     python -c `"from pyannote.audio import Pipeline; print('OK')`"" -ForegroundColor Cyan
Write-Host ""
