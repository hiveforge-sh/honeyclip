# Makefile for honeyclip dependency installation
# Supports: WSL, Linux, macOS, Windows (Git Bash/MSYS2)

.PHONY: help install-deps install-python-deps install-nim-deps install-pyannote check-deps clean-python

# Detect platform
UNAME_S := $(shell uname -s 2>/dev/null || echo Windows)
IS_WSL := $(shell grep -qi microsoft /proc/version 2>/dev/null && echo 1 || echo 0)

# Python command detection
PYTHON := $(shell command -v python3 2>/dev/null || command -v python 2>/dev/null)
PIP := $(shell command -v pip3 2>/dev/null || command -v pip 2>/dev/null)

# Colors for output
CYAN := \033[36m
GREEN := \033[32m
YELLOW := \033[33m
RED := \033[31m
RESET := \033[0m

help:
	@echo "$(CYAN)honeyclip Dependency Installation$(RESET)"
	@echo ""
	@echo "$(GREEN)Available targets:$(RESET)"
	@echo "  make install-deps       - Install all dependencies (Python + Nim)"
	@echo "  make install-python-deps - Install Python dependencies only"
	@echo "  make install-nim-deps   - Install Nim dependencies only"
	@echo "  make install-pyannote   - Install pyannote.audio for speaker diarization"
	@echo "  make check-deps         - Check if dependencies are installed"
	@echo "  make clean-python       - Remove Python virtual environment"
	@echo ""
	@echo "$(YELLOW)Platform detected: $(UNAME_S)$(RESET)"
ifeq ($(IS_WSL),1)
	@echo "$(YELLOW)Running in WSL$(RESET)"
endif

# Install all dependencies
install-deps: install-python-deps install-nim-deps
	@echo "$(GREEN)All dependencies installed!$(RESET)"

# Install Python dependencies
install-python-deps: check-python
	@echo "$(CYAN)Installing Python dependencies...$(RESET)"
ifeq ($(UNAME_S),Darwin)
	@echo "$(YELLOW)macOS detected$(RESET)"
	$(PIP) install --upgrade pip
	$(PIP) install av pytest
else ifeq ($(UNAME_S),Linux)
ifeq ($(IS_WSL),1)
	@echo "$(YELLOW)WSL detected$(RESET)"
else
	@echo "$(YELLOW)Linux detected$(RESET)"
endif
	$(PIP) install --upgrade pip
	$(PIP) install av pytest
else
	@echo "$(YELLOW)Windows detected$(RESET)"
	$(PIP) install --upgrade pip
	$(PIP) install av pytest
endif
	@echo "$(GREEN)Python dependencies installed!$(RESET)"

# Install pyannote.audio for speaker diarization (heavyweight, optional)
install-pyannote: check-python
	@echo "$(CYAN)Installing pyannote.audio for speaker diarization...$(RESET)"
	@echo "$(YELLOW)Note: This requires ~2GB of downloads (PyTorch + models)$(RESET)"
	@echo ""
ifeq ($(UNAME_S),Darwin)
	@# macOS - use MPS backend for Apple Silicon
	$(PIP) install torch torchvision torchaudio
	$(PIP) install pyannote.audio
else ifeq ($(UNAME_S),Linux)
	@# Linux/WSL - check for CUDA
	@if command -v nvidia-smi >/dev/null 2>&1; then \
		echo "$(GREEN)CUDA detected, installing GPU-enabled PyTorch$(RESET)"; \
		$(PIP) install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121; \
	else \
		echo "$(YELLOW)No CUDA detected, installing CPU-only PyTorch$(RESET)"; \
		$(PIP) install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu; \
	fi
	$(PIP) install pyannote.audio
else
	@# Windows
	@if command -v nvidia-smi >/dev/null 2>&1; then \
		echo "$(GREEN)CUDA detected, installing GPU-enabled PyTorch$(RESET)"; \
		$(PIP) install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121; \
	else \
		echo "$(YELLOW)No CUDA detected, installing CPU-only PyTorch$(RESET)"; \
		$(PIP) install torch torchvision torchaudio; \
	fi
	$(PIP) install pyannote.audio
endif
	@echo ""
	@echo "$(GREEN)pyannote.audio installed!$(RESET)"
	@echo ""
	@echo "$(YELLOW)Next steps:$(RESET)"
	@echo "  1. Get HuggingFace token: https://huggingface.co/settings/tokens"
	@echo "  2. Accept model license: https://huggingface.co/pyannote/speaker-diarization-3.1"
	@echo "  3. Set environment variable: export HF_TOKEN=your_token_here"

# Install Nim dependencies
install-nim-deps:
	@echo "$(CYAN)Installing Nim dependencies...$(RESET)"
	@if command -v nimble >/dev/null 2>&1; then \
		nimble install -y nimpy; \
		echo "$(GREEN)Nim dependencies installed!$(RESET)"; \
	else \
		echo "$(RED)Error: nimble not found. Install Nim first: https://nim-lang.org/install.html$(RESET)"; \
		exit 1; \
	fi

# Check if dependencies are installed
check-deps: check-python
	@echo "$(CYAN)Checking dependencies...$(RESET)"
	@echo ""
	@echo "$(GREEN)Python:$(RESET)"
	@$(PYTHON) --version
	@echo ""
	@echo "$(GREEN)pip packages:$(RESET)"
	@$(PIP) list 2>/dev/null | grep -E "^(av|pytest|torch|pyannote)" || echo "  (core packages not installed)"
	@echo ""
	@echo "$(GREEN)Nim:$(RESET)"
	@if command -v nim >/dev/null 2>&1; then \
		nim --version | head -1; \
	else \
		echo "  $(RED)Not installed$(RESET)"; \
	fi
	@echo ""
	@echo "$(GREEN)nimpy:$(RESET)"
	@if command -v nimble >/dev/null 2>&1; then \
		nimble list -i 2>/dev/null | grep nimpy || echo "  $(YELLOW)Not installed$(RESET)"; \
	else \
		echo "  $(YELLOW)nimble not available$(RESET)"; \
	fi
	@echo ""
	@echo "$(GREEN)pyannote.audio:$(RESET)"
	@$(PYTHON) -c "from pyannote.audio import Pipeline; print('  Installed')" 2>/dev/null || echo "  $(YELLOW)Not installed (optional - run: make install-pyannote)$(RESET)"
	@echo ""
	@echo "$(GREEN)HF_TOKEN:$(RESET)"
	@if [ -n "$$HF_TOKEN" ]; then \
		echo "  Set ($(shell echo $$HF_TOKEN | head -c 8)...)"; \
	else \
		echo "  $(YELLOW)Not set$(RESET)"; \
	fi

# Verify Python is available
check-python:
	@if [ -z "$(PYTHON)" ]; then \
		echo "$(RED)Error: Python not found$(RESET)"; \
		echo ""; \
		echo "Install Python:"; \
		echo "  macOS:   brew install python3"; \
		echo "  Ubuntu:  sudo apt install python3 python3-pip"; \
		echo "  Fedora:  sudo dnf install python3 python3-pip"; \
		echo "  Windows: https://www.python.org/downloads/"; \
		exit 1; \
	fi

# Clean Python virtual environment
clean-python:
	@echo "$(CYAN)Cleaning Python cache...$(RESET)"
	rm -rf __pycache__ .pytest_cache
	find . -name "*.pyc" -delete 2>/dev/null || true
	@echo "$(GREEN)Cleaned!$(RESET)"

# Platform-specific system dependencies
install-system-deps:
	@echo "$(CYAN)Installing system dependencies...$(RESET)"
ifeq ($(UNAME_S),Darwin)
	@echo "$(YELLOW)macOS: Installing via Homebrew$(RESET)"
	brew install cmake nasm pkg-config python3
else ifeq ($(UNAME_S),Linux)
	@if [ -f /etc/debian_version ]; then \
		echo "$(YELLOW)Debian/Ubuntu detected$(RESET)"; \
		sudo apt update && sudo apt install -y cmake nasm pkg-config python3 python3-pip build-essential; \
	elif [ -f /etc/fedora-release ]; then \
		echo "$(YELLOW)Fedora detected$(RESET)"; \
		sudo dnf install -y cmake nasm pkg-config python3 python3-pip gcc gcc-c++; \
	elif [ -f /etc/arch-release ]; then \
		echo "$(YELLOW)Arch Linux detected$(RESET)"; \
		sudo pacman -S --noconfirm cmake nasm pkg-config python python-pip base-devel; \
	else \
		echo "$(RED)Unknown Linux distribution. Please install manually: cmake nasm pkg-config python3 python3-pip$(RESET)"; \
	fi
else
	@echo "$(YELLOW)Windows: Please install dependencies manually:$(RESET)"
	@echo "  - Python: https://www.python.org/downloads/"
	@echo "  - CMake: https://cmake.org/download/"
	@echo "  - NASM: https://www.nasm.us/"
	@echo "  Or use a package manager like Chocolatey/Scoop"
endif
	@echo "$(GREEN)System dependencies installed!$(RESET)"
