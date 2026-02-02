# Makefile for honeyclip dependency installation
# Supports: WSL, Linux, macOS, Windows (Git Bash/MSYS2)

.PHONY: help prerequisites install-deps install-python-deps install-nim-deps install-pyannote check-deps clean-python venv

# Detect platform
UNAME_S := $(shell uname -s 2>/dev/null || echo Windows)
IS_WSL := $(shell grep -qi microsoft /proc/version 2>/dev/null && echo 1 || echo 0)

# Virtual environment settings
VENV_DIR := .venv
VENV_PYTHON := $(VENV_DIR)/bin/python
VENV_PIP := $(VENV_DIR)/bin/pip

# System Python (for creating venv)
SYS_PYTHON := $(shell command -v python3 2>/dev/null || command -v python 2>/dev/null)

# Use venv if it exists, otherwise system python
ifeq ($(wildcard $(VENV_DIR)/bin/python),)
    PYTHON := $(SYS_PYTHON)
    PIP := $(shell command -v pip3 2>/dev/null || command -v pip 2>/dev/null)
else
    PYTHON := $(VENV_PYTHON)
    PIP := $(VENV_PIP)
endif

# Colors for output
CYAN := \033[36m
GREEN := \033[32m
YELLOW := \033[33m
RED := \033[31m
RESET := \033[0m

help:
	@echo "$(CYAN)honeyclip Dependency Installation$(RESET)"
	@echo ""
	@echo "$(GREEN)Quick start:$(RESET)"
	@echo "  make prerequisites      - $(YELLOW)One command to install everything$(RESET)"
	@echo ""
	@echo "$(GREEN)Individual targets:$(RESET)"
	@echo "  make install-deps       - Install Python + Nim dependencies"
	@echo "  make install-python-deps - Install Python dependencies only"
	@echo "  make install-nim-deps   - Install Nim dependencies only"
	@echo "  make install-pyannote   - Install pyannote.audio for speaker diarization"
	@echo "  make install-system-deps - Install system packages (cmake, nasm, etc.)"
	@echo "  make check-deps         - Check if dependencies are installed"
	@echo "  make clean-python       - Remove Python cache files"
	@echo ""
	@echo "$(YELLOW)Platform detected: $(UNAME_S)$(RESET)"
ifeq ($(IS_WSL),1)
	@echo "$(YELLOW)Running in WSL$(RESET)"
endif

# Create virtual environment
venv:
	@if [ ! -d "$(VENV_DIR)" ] || [ ! -f "$(VENV_PIP)" ]; then \
		echo "$(CYAN)Creating Python virtual environment...$(RESET)"; \
		rm -rf $(VENV_DIR) 2>/dev/null || true; \
		$(SYS_PYTHON) -m venv $(VENV_DIR) || { \
			echo "$(RED)venv creation failed. Installing python3-venv...$(RESET)"; \
			if [ -f /etc/debian_version ]; then \
				sudo apt-get update && sudo apt-get install -y python3-venv; \
			fi; \
			$(SYS_PYTHON) -m venv $(VENV_DIR); \
		}; \
		if [ -f "$(VENV_PIP)" ]; then \
			echo "$(GREEN)Virtual environment created at $(VENV_DIR)$(RESET)"; \
		else \
			echo "$(RED)Failed to create virtual environment$(RESET)"; \
			exit 1; \
		fi; \
	else \
		echo "$(GREEN)Virtual environment already exists$(RESET)"; \
	fi

# One-command setup for all prerequisites
prerequisites: check-python venv
	@echo "$(CYAN)======================================$(RESET)"
	@echo "$(CYAN)  honeyclip Prerequisites Setup$(RESET)"
	@echo "$(CYAN)======================================$(RESET)"
	@echo ""
	@echo "$(YELLOW)Platform: $(UNAME_S)$(RESET)"
ifeq ($(IS_WSL),1)
	@echo "$(YELLOW)Environment: WSL$(RESET)"
endif
	@echo "$(YELLOW)Using venv: $(VENV_DIR)$(RESET)"
	@echo ""
	@# Step 1: System dependencies
	@echo "$(CYAN)[1/4] Installing system dependencies...$(RESET)"
	@$(MAKE) -s install-system-deps-silent || true
	@echo ""
	@# Step 2: Python dependencies
	@echo "$(CYAN)[2/4] Installing Python dependencies...$(RESET)"
	$(VENV_PIP) install --upgrade pip
	$(VENV_PIP) install av pytest
	@echo ""
	@# Step 3: Nim dependencies
	@echo "$(CYAN)[3/4] Installing Nim dependencies...$(RESET)"
	@if command -v nimble >/dev/null 2>&1; then \
		nimble install -y nimpy || echo "$(YELLOW)nimpy may already be installed$(RESET)"; \
	else \
		echo "$(YELLOW)Skipping: nimble not found$(RESET)"; \
	fi
	@echo ""
	@# Step 4: pyannote.audio (speaker diarization)
	@echo "$(CYAN)[4/4] Installing pyannote.audio (speaker diarization)...$(RESET)"
	@echo "$(YELLOW)Note: This downloads ~2GB (PyTorch + models)$(RESET)"
	@$(MAKE) -s install-pyannote-silent
	@echo ""
	@echo "$(GREEN)======================================$(RESET)"
	@echo "$(GREEN)  Prerequisites installed!$(RESET)"
	@echo "$(GREEN)======================================$(RESET)"
	@echo ""
	@echo "$(YELLOW)To use the virtual environment:$(RESET)"
	@echo "  $(CYAN)source $(VENV_DIR)/bin/activate$(RESET)"
	@echo ""
	@echo "$(YELLOW)Remaining manual steps:$(RESET)"
	@echo "  1. Get HuggingFace token:"
	@echo "     $(CYAN)https://huggingface.co/settings/tokens$(RESET)"
	@echo ""
	@echo "  2. Accept pyannote model license:"
	@echo "     $(CYAN)https://huggingface.co/pyannote/speaker-diarization-3.1$(RESET)"
	@echo ""
	@echo "  3. Set environment variable:"
	@echo "     $(CYAN)export HF_TOKEN=your_token_here$(RESET)"
	@echo ""
	@echo "  4. Verify setup:"
	@echo "     $(CYAN)make check-deps$(RESET)"
	@echo ""

# Silent version of install-system-deps (no prompts, best effort)
install-system-deps-silent:
ifeq ($(UNAME_S),Darwin)
	@command -v brew >/dev/null 2>&1 && brew install cmake nasm pkg-config python3 2>/dev/null || echo "  Homebrew not available, skipping"
else ifeq ($(UNAME_S),Linux)
	@if [ -f /etc/debian_version ]; then \
		sudo apt-get update -qq && sudo apt-get install -y -qq cmake nasm pkg-config python3 python3-pip build-essential 2>/dev/null || echo "  apt install skipped (may need sudo)"; \
	elif [ -f /etc/fedora-release ]; then \
		sudo dnf install -y -q cmake nasm pkg-config python3 python3-pip gcc gcc-c++ 2>/dev/null || echo "  dnf install skipped"; \
	elif [ -f /etc/arch-release ]; then \
		sudo pacman -S --noconfirm --quiet cmake nasm pkg-config python python-pip base-devel 2>/dev/null || echo "  pacman install skipped"; \
	fi
endif

# Silent pyannote install (always uses venv)
install-pyannote-silent:
ifeq ($(UNAME_S),Darwin)
	@$(VENV_PIP) install -q torch torchvision torchaudio 2>/dev/null || $(VENV_PIP) install torch torchvision torchaudio
	@$(VENV_PIP) install -q pyannote.audio 2>/dev/null || $(VENV_PIP) install pyannote.audio
else ifeq ($(UNAME_S),Linux)
	@if command -v nvidia-smi >/dev/null 2>&1; then \
		$(VENV_PIP) install -q torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121 2>/dev/null || \
		$(VENV_PIP) install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121; \
	else \
		$(VENV_PIP) install -q torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu 2>/dev/null || \
		$(VENV_PIP) install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu; \
	fi
	@$(VENV_PIP) install -q pyannote.audio 2>/dev/null || $(VENV_PIP) install pyannote.audio
else
	@if command -v nvidia-smi >/dev/null 2>&1; then \
		$(VENV_PIP) install -q torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121 2>/dev/null || \
		$(VENV_PIP) install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121; \
	else \
		$(VENV_PIP) install -q torch torchvision torchaudio 2>/dev/null || \
		$(VENV_PIP) install torch torchvision torchaudio; \
	fi
	@$(VENV_PIP) install -q pyannote.audio 2>/dev/null || $(VENV_PIP) install pyannote.audio
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
	@echo "$(GREEN)Virtual environment:$(RESET)"
	@if [ -d "$(VENV_DIR)" ]; then \
		echo "  $(GREEN)$(VENV_DIR) exists$(RESET)"; \
	else \
		echo "  $(YELLOW)Not created (run: make venv)$(RESET)"; \
	fi
	@echo ""
	@echo "$(GREEN)Python:$(RESET)"
	@if [ -f "$(VENV_PYTHON)" ]; then \
		$(VENV_PYTHON) --version; \
	else \
		$(SYS_PYTHON) --version; \
		echo "  $(YELLOW)(system python - run 'make venv' to create virtualenv)$(RESET)"; \
	fi
	@echo ""
	@echo "$(GREEN)pip packages:$(RESET)"
	@if [ -f "$(VENV_PIP)" ]; then \
		$(VENV_PIP) list 2>/dev/null | grep -E "^(av|pytest|torch|pyannote)" || echo "  (core packages not installed)"; \
	else \
		echo "  $(YELLOW)(no venv - packages not checked)$(RESET)"; \
	fi
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
	@if [ -f "$(VENV_PYTHON)" ]; then \
		$(VENV_PYTHON) -c "from pyannote.audio import Pipeline; print('  Installed')" 2>/dev/null || echo "  $(YELLOW)Not installed (run: make install-pyannote)$(RESET)"; \
	else \
		echo "  $(YELLOW)(no venv - run 'make prerequisites')$(RESET)"; \
	fi
	@echo ""
	@echo "$(GREEN)HF_TOKEN:$(RESET)"
	@if [ -n "$$HF_TOKEN" ]; then \
		echo "  Set ($${HF_TOKEN:0:8}...)"; \
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
	@echo "$(CYAN)Cleaning Python environment...$(RESET)"
	rm -rf $(VENV_DIR)
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
