#!/usr/bin/env bash
#
# Bootstrap script for honeyclip
# Installs Nim and system dependencies on macOS, Linux, and Windows (Git Bash)
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Detect OS
detect_os() {
    case "$(uname -s)" in
        Darwin*)  OS="macos" ;;
        Linux*)   OS="linux" ;;
        MINGW*|MSYS*|CYGWIN*) OS="windows" ;;
        *)        error "Unsupported operating system: $(uname -s)" ;;
    esac
    info "Detected OS: $OS"
}

# Detect Linux distribution
detect_linux_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
    elif [ -f /etc/debian_version ]; then
        DISTRO="debian"
    elif [ -f /etc/redhat-release ]; then
        DISTRO="fedora"
    elif [ -f /etc/arch-release ]; then
        DISTRO="arch"
    else
        DISTRO="unknown"
    fi
    info "Detected Linux distribution: $DISTRO"
}

# Check if a command exists
has_command() {
    command -v "$1" &> /dev/null
}

# Install Nim via choosenim
install_nim() {
    if has_command nim; then
        local version=$(nim --version | head -1)
        info "Nim already installed: $version"
        return 0
    fi

    info "Installing Nim via choosenim..."

    if has_command choosenim; then
        choosenim stable
    else
        curl https://nim-lang.org/choosenim/init.sh -sSf | sh -s -- -y
        export PATH="$HOME/.nimble/bin:$PATH"
    fi

    # Verify installation
    if has_command nim; then
        info "Nim installed successfully: $(nim --version | head -1)"
    else
        error "Failed to install Nim. Please install manually from https://nim-lang.org/install.html"
    fi
}

# Install dependencies on macOS
install_macos_deps() {
    info "Installing macOS dependencies via Homebrew..."

    if ! has_command brew; then
        error "Homebrew not found. Install from https://brew.sh"
    fi

    local packages=()

    has_command cmake || packages+=(cmake)
    has_command nasm || packages+=(nasm)
    has_command pkg-config || packages+=(pkg-config)
    has_command meson || packages+=(meson)
    has_command ninja || packages+=(ninja)

    if [ ${#packages[@]} -gt 0 ]; then
        info "Installing: ${packages[*]}"
        brew install "${packages[@]}"
    else
        info "All macOS dependencies already installed"
    fi
}

# Install dependencies on Linux
install_linux_deps() {
    info "Installing Linux dependencies..."

    case "$DISTRO" in
        ubuntu|debian|pop|linuxmint)
            local packages=()
            has_command cmake || packages+=(cmake)
            has_command nasm || packages+=(nasm)
            has_command pkg-config || packages+=(pkg-config)
            has_command meson || packages+=(meson)
            has_command ninja || packages+=(ninja-build)
            has_command curl || packages+=(curl)
            has_command gcc || packages+=(build-essential)

            if [ ${#packages[@]} -gt 0 ]; then
                info "Installing: ${packages[*]}"
                sudo apt update
                sudo apt install -y "${packages[@]}"
            fi
            ;;
        fedora|rhel|centos)
            local packages=()
            has_command cmake || packages+=(cmake)
            has_command nasm || packages+=(nasm)
            has_command pkg-config || packages+=(pkgconfig)
            has_command meson || packages+=(meson)
            has_command ninja || packages+=(ninja-build)
            has_command curl || packages+=(curl)
            has_command gcc || packages+=(gcc gcc-c++)

            if [ ${#packages[@]} -gt 0 ]; then
                info "Installing: ${packages[*]}"
                sudo dnf install -y "${packages[@]}"
            fi
            ;;
        arch|manjaro)
            local packages=()
            has_command cmake || packages+=(cmake)
            has_command nasm || packages+=(nasm)
            has_command pkg-config || packages+=(pkgconf)
            has_command meson || packages+=(meson)
            has_command ninja || packages+=(ninja)
            has_command curl || packages+=(curl)
            has_command gcc || packages+=(base-devel)

            if [ ${#packages[@]} -gt 0 ]; then
                info "Installing: ${packages[*]}"
                sudo pacman -Sy --noconfirm "${packages[@]}"
            fi
            ;;
        *)
            warn "Unknown Linux distribution: $DISTRO"
            warn "Please install manually: cmake nasm pkg-config meson ninja"

            # Try pip as fallback for meson/ninja
            if ! has_command meson || ! has_command ninja; then
                if has_command pip3; then
                    info "Attempting to install meson/ninja via pip..."
                    pip3 install --user meson ninja
                elif has_command pip; then
                    pip install --user meson ninja
                fi
            fi
            ;;
    esac

    info "Linux dependencies installed"
}

# Install dependencies on Windows (Git Bash)
install_windows_deps() {
    info "Installing Windows dependencies..."

    # Check for Python/pip
    if ! has_command python3 && ! has_command python; then
        error "Python not found. Install Python 3.14+ from https://python.org"
    fi

    local pip_cmd="pip"
    has_command pip3 && pip_cmd="pip3"

    # Install meson and ninja via pip
    if ! has_command meson || ! has_command ninja; then
        info "Installing meson and ninja via pip..."
        $pip_cmd install meson ninja
    fi

    # Check for other dependencies
    if ! has_command cmake; then
        warn "cmake not found. Install from https://cmake.org/download/"
    fi

    if ! has_command nasm; then
        warn "nasm not found. Install from https://nasm.us/"
    fi

    info "Windows dependencies check complete"
}

# Print PATH setup instructions if needed
print_path_warning() {
    # Check if nimble is in current PATH
    if has_command nimble; then
        return 0
    fi

    local nimble_bin="$HOME/.nimble/bin"
    local shell_name=$(basename "$SHELL")
    local rc_file

    case "$shell_name" in
        zsh)  rc_file="~/.zshrc" ;;
        bash) rc_file="~/.bashrc" ;;
        fish) rc_file="~/.config/fish/config.fish" ;;
        *)    rc_file="~/.profile" ;;
    esac

    echo ""
    echo -e "${YELLOW}=========================================="
    echo "  ACTION REQUIRED: Add Nim to your PATH"
    echo -e "==========================================${NC}"
    echo ""
    echo "  Run these commands:"
    echo ""
    if [ "$shell_name" = "fish" ]; then
        echo -e "    ${GREEN}echo 'set -gx PATH $nimble_bin \$PATH' >> $rc_file${NC}"
    else
        echo -e "    ${GREEN}echo 'export PATH=$nimble_bin:\$PATH' >> $rc_file${NC}"
    fi
    echo -e "    ${GREEN}source $rc_file${NC}"
    echo ""
    echo "  Or restart your terminal."
    echo ""
}

# Download Whisper model for speech analysis
download_whisper_model() {
    local model_dir="$HOME/.cache/whisper"
    local model_file="$model_dir/ggml-base.en.bin"
    local model_url="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin"

    if [ -f "$model_file" ]; then
        info "Whisper model already downloaded"
        return 0
    fi

    echo ""
    echo -e "${YELLOW}Optional: Download Whisper model for speech analysis${NC}"
    echo "  Model: ggml-base.en.bin (~142MB)"
    echo "  For better accuracy, manually download ggml-small.en.bin (~466MB)"
    echo "  or ggml-medium.en.bin (~1.5GB) from:"
    echo "  https://huggingface.co/ggerganov/whisper.cpp"
    echo ""
    read -p "Download base model now? [y/N] " -n 1 -r
    echo ""

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        info "Downloading Whisper model..."
        mkdir -p "$model_dir"
        if curl -L -o "$model_file" "$model_url"; then
            info "Whisper model downloaded to $model_file"
        else
            warn "Failed to download Whisper model. You can download it manually later."
        fi
    else
        info "Skipping Whisper model download"
    fi
}

# Print post-install instructions
print_instructions() {
    print_path_warning

    echo ""
    info "Bootstrap complete!"
    echo ""
    echo "Next steps:"
    echo "  1. Build FFmpeg and dependencies (takes 1-2 hours first time):"
    echo "     nimble makeff"
    echo ""
    if [ "$OS" = "windows" ]; then
        echo "  2. Build honeyclip:"
        echo "     nimble make"
        echo "     (ML features are stubbed on Windows)"
    else
        echo "  2. Build ML libraries (libfacedetection, OpenCV, ONNX Runtime):"
        echo "     nimble makeml"
        echo ""
        echo "  3. Build honeyclip:"
        echo "     nimble make"
    fi
    echo ""
    echo "  4. Download Whisper model (if not already done):"
    echo "     mkdir -p ~/.cache/whisper"
    echo "     curl -L -o ~/.cache/whisper/ggml-base.en.bin \\"
    echo "       https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin"
    echo ""
    echo "  Run tests:"
    echo "     nimble test"
    echo ""
}

# Main
main() {
    echo "=========================================="
    echo "  honeyclip bootstrap script"
    echo "=========================================="
    echo ""

    detect_os

    case "$OS" in
        macos)
            install_macos_deps
            ;;
        linux)
            detect_linux_distro
            install_linux_deps
            ;;
        windows)
            install_windows_deps
            ;;
    esac

    install_nim
    download_whisper_model
    print_instructions
}

main "$@"
