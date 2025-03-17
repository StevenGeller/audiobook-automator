#!/bin/bash
#
# audiobook-automator: install prerequisites
# usage: ./install_prerequisites.sh
#
# this script installs all required dependencies for the audiobook processor
# supports: macos (homebrew), linux (apt, yum, dnf), and windows (wsl)
#

set -e  # exit on error

# output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# function to print section headers
print_header() {
    echo -e "\n${BLUE}${BOLD}$1${NC}"
    echo -e "${BLUE}$(printf '=%.0s' $(seq 1 ${#1}))${NC}\n"
}

# function to print success messages
print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

# function to print error messages and exit
print_error() {
    echo -e "${RED}✗ ERROR: $1${NC}" >&2
    exit 1
}

# detect operating system
detect_os() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        OS="macos"
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        OS="linux"
        # detect package manager
        if command -v apt &> /dev/null; then
            PKG_MANAGER="apt"
        elif command -v yum &> /dev/null; then
            PKG_MANAGER="yum"
        elif command -v dnf &> /dev/null; then
            PKG_MANAGER="dnf"
        else
            print_error "Unsupported Linux distribution. Please install dependencies manually."
        fi
    elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
        if command -v wsl &> /dev/null; then
            OS="wsl"
        else
            print_error "Windows is only supported through WSL (Windows Subsystem for Linux)."
        fi
    else
        print_error "Unsupported operating system: $OSTYPE"
    fi
}

# install dependencies based on OS
install_dependencies() {
    print_header "Installing required tools for Audiobook Automator"
    
    case $OS in
        macos)
            install_macos_dependencies
            ;;
        linux)
            install_linux_dependencies
            ;;
        wsl)
            install_wsl_dependencies
            ;;
    esac
    
    install_python_packages
}

# install dependencies for macOS using Homebrew
install_macos_dependencies() {
    echo "Detected macOS system..."
    
    # check if Homebrew is installed
    if ! command -v brew &> /dev/null; then
        echo "Homebrew not found. Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || print_error "Failed to install Homebrew"
    else
        echo "Homebrew is already installed. Updating..."
        brew update || print_error "Failed to update Homebrew"
    fi
    
    echo "Installing required command line tools..."
    brew install ffmpeg mp4v2 fd jq mediainfo python3 || print_error "Failed to install one or more required tools"
    
    print_success "Successfully installed macOS dependencies"
}

# install dependencies for Linux
install_linux_dependencies() {
    echo "Detected Linux system using $PKG_MANAGER..."
    
    case $PKG_MANAGER in
        apt)
            sudo apt-get update || print_error "Failed to update package database"
            sudo apt-get install -y ffmpeg mp4v2-utils fd-find jq mediainfo python3 python3-pip || print_error "Failed to install one or more required tools"
            # fd-find has a different name on Debian/Ubuntu
            if ! command -v fd &> /dev/null; then
                echo "Creating fd alias for fd-find..."
                echo 'alias fd=fdfind' >> ~/.bashrc
                echo 'alias fd=fdfind' >> ~/.zshrc 2>/dev/null || true
            fi
            ;;
        yum|dnf)
            sudo $PKG_MANAGER update -y || print_error "Failed to update package database"
            sudo $PKG_MANAGER install -y ffmpeg mp4v2 fd-find jq mediainfo python3 python3-pip || print_error "Failed to install one or more required tools"
            ;;
    esac
    
    print_success "Successfully installed Linux dependencies"
}

# install dependencies for WSL (using apt)
install_wsl_dependencies() {
    echo "Detected Windows WSL environment..."
    sudo apt-get update || print_error "Failed to update package database"
    sudo apt-get install -y ffmpeg mp4v2-utils fd-find jq mediainfo python3 python3-pip || print_error "Failed to install one or more required tools"
    
    # fd-find has a different name on Debian/Ubuntu
    if ! command -v fd &> /dev/null; then
        echo "Creating fd alias for fd-find..."
        echo 'alias fd=fdfind' >> ~/.bashrc
        echo 'alias fd=fdfind' >> ~/.zshrc 2>/dev/null || true
    fi
    
    print_success "Successfully installed WSL dependencies"
}

# install required Python packages
install_python_packages() {
    print_header "Installing required Python packages"
    
    # ensure pip is available
    if ! command -v pip3 &> /dev/null; then
        print_error "pip3 not found. Please ensure Python 3 is correctly installed."
    fi
    
    pip3 install --user requests beautifulsoup4 fuzzywuzzy python-Levenshtein || print_error "Failed to install Python packages"
    
    print_success "Successfully installed Python packages"
}

# verify installations
verify_installations() {
    print_header "Verifying installations"
    
    local missing=0
    local commands=("ffmpeg" "jq" "mediainfo" "python3" "pip3")
    
    # fd command might be aliased as fdfind on some systems
    if ! command -v fd &> /dev/null; then
        if ! command -v fdfind &> /dev/null; then
            echo -e "${RED}✗ fd/fdfind not found${NC}"
            missing=1
        else
            echo -e "${GREEN}✓ fd command available as fdfind${NC}"
        fi
    else
        echo -e "${GREEN}✓ fd command available${NC}"
    fi
    
    # check for other required commands
    for cmd in "${commands[@]}"; do
        if command -v $cmd &> /dev/null; then
            echo -e "${GREEN}✓ $cmd command available${NC}"
        else
            echo -e "${RED}✗ $cmd command not found${NC}"
            missing=1
        fi
    done
    
    # check for Python packages
    local packages=("requests" "bs4" "fuzzywuzzy")
    local package_names=("requests" "beautifulsoup4" "fuzzywuzzy")
    for i in "${!packages[@]}"; do
        pkg=${packages[$i]}
        pkg_name=${package_names[$i]}
        if python3 -c "import $pkg" &> /dev/null; then
            echo -e "${GREEN}✓ Python package $pkg_name is installed${NC}"
        else
            echo -e "${RED}✗ Python package $pkg_name is not installed${NC}"
            missing=1
        fi
    done
    
    if [ $missing -eq 1 ]; then
        echo -e "\n${RED}Some required dependencies could not be verified.${NC}"
        echo "You may need to install them manually or restart your terminal."
    else
        print_success "All required dependencies are installed!"
    fi
}

# main execution
main() {
    detect_os
    install_dependencies
    verify_installations
    
    echo ""
    print_success "Installation complete!"
    echo -e "${BOLD}You can now run the audiobook_processor.sh script.${NC}"
    echo "For more information, see the README.md file."
}

main