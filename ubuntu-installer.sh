#!/data/data/com.termux/files/usr/bin/bash
# -*- coding: utf-8 -*-
#
# Ubuntu in Termux Installer - Final Version
# Handles permission issues and uses proper temp directory
#

set -e
trap 'error_handler $? $LINENO' ERR

# Color codes
readonly COLOR_RED='\x1b[38;5;1m'
readonly COLOR_YELLOW='\x1b[38;5;220m'
readonly COLOR_PURPLE='\x1b[38;5;128m'
readonly COLOR_GREEN='\x1b[38;5;83m'
readonly COLOR_CYAN='\x1b[38;5;31m'
readonly COLOR_ORANGE='\x1b[38;5;214m'
readonly COLOR_BLUE='\x1b[38;5;87m'
readonly COLOR_RESET='\x1b[0m'

# Configuration
readonly DIRECTORY="ubuntu-fs"
readonly UBUNTU_VERSION="jammy"
readonly ARCHIVE_FILE="ubuntu.tar.gz"
readonly START_SCRIPT="start.sh"
readonly BINDS_DIR="ubuntu-binds"
readonly MAX_DOWNLOAD_RETRIES=3

error_handler() {
    local exit_code=$1
    local line_number=$2
    print_ew "error" "Failed at line $line_number (exit code: $exit_code)"
    cleanup_failed
    exit "$exit_code"
}

print_ew() {
    local level="$1"
    local message="$2"
    local s_text=""
    local text=""
    
    case "$level" in
        error)
            s_text="${COLOR_RED}[ERROR]:"
            text="${message}\n"
            ;;
        warn)
            s_text="${COLOR_YELLOW}[WARNING]:"
            text="${message}\n"
            ;;
        question)
            s_text="${COLOR_PURPLE}[QUESTION]:"
            text="${message}"
            ;;
        info)
            s_text="${COLOR_GREEN}[INFO]:"
            text="${message}\n"
            ;;
        success)
            s_text="${COLOR_GREEN}[SUCCESS]:"
            text="${message}\n"
            ;;
        *)
            s_text="${COLOR_CYAN}[${level}]:"
            text="${message}\n"
            ;;
    esac
    
    local current_time
    current_time="$(date +"%H:%M:%S")"
    
    printf "${COLOR_ORANGE}[${current_time}] ${s_text}${COLOR_RESET} ${COLOR_BLUE}${text}${COLOR_RESET}"
}

check_termux() {
    if [[ "$(uname -o)" != "Android" ]]; then
        print_ew "error" "This script is for Termux only."
        exit 1
    fi
}

check_write_permission() {
    print_ew "info" "Checking write permissions..."
    
    local test_file=".write_test_$$"
    
    if ! touch "$test_file" 2>/dev/null; then
        print_ew "error" "Cannot write to current directory!"
        print_ew "error" "Current directory: $(pwd)"
        print_ew "error" ""
        print_ew "error" "Solution: Move to Termux home directory"
        print_ew "info" "Run these commands:"
        print_ew "info" "  cd ~"
        print_ew "info" "  bash $(basename "$0")"
        exit 1
    fi
    
    rm -f "$test_file"
    print_ew "success" "Write permission OK"
}

cleanup_all() {
    print_ew "info" "Performing complete cleanup..."
    
    local items=(
        "$DIRECTORY"
        "$BINDS_DIR"
        "$START_SCRIPT"
        "$ARCHIVE_FILE"
        "${ARCHIVE_FILE}.partial"
        ".git"
        "extract.log"
        "start.sh.old"
    )
    
    for item in "${items[@]}"; do
        if [ -e "$item" ]; then
            print_ew "info" "Removing: $item"
            rm -rf "$item" 2>/dev/null || true
        fi
    done
    
    print_ew "success" "Cleanup complete!"
}

cleanup_failed() {
    print_ew "warn" "Cleaning up failed installation..."
    rm -rf "$DIRECTORY" "$BINDS_DIR" "$START_SCRIPT" "$ARCHIVE_FILE" 2>/dev/null || true
}

check_storage() {
    local current_dir
    current_dir="$(pwd)"
    
    print_ew "info" "Installation directory: $current_dir"
    
    # Check filesystem type
    local fs_type
    fs_type="$(df -T . 2>/dev/null | tail -1 | awk '{print $2}' || echo "unknown")"
    print_ew "info" "Filesystem: $fs_type"
    
    if [[ "$fs_type" =~ (vfat|exfat|fuseblk|fuse) ]]; then
        print_ew "error" "===================================="
        print_ew "error" "CRITICAL: You are on SD card/external storage!"
        print_ew "error" "===================================="
        print_ew "error" "This WILL fail due to:"
        print_ew "error" "  - Permission issues"
        print_ew "error" "  - Symlink restrictions"
        print_ew "error" "  - File system limitations"
        print_ew "error" ""
        print_ew "error" "You MUST install in Termux home:"
        print_ew "info" "  cd ~"
        print_ew "info" "  pwd    # Should show: /data/data/com.termux/files/home"
        print_ew "info" "  bash $(basename "$0")"
        exit 1
    fi
    
    # Check free space
    local free_space_kb
    free_space_kb="$(df . 2>/dev/null | tail -1 | awk '{print $4}' || echo "0")"
    local free_space_mb=$((free_space_kb / 1024))
    
    print_ew "info" "Free space: ${free_space_mb}MB"
    
    if [ "$free_space_kb" -lt 1500000 ]; then
        print_ew "error" "Insufficient space! Need 1500MB, have ${free_space_mb}MB"
        exit 1
    fi
}

check_dependencies() {
    local missing_deps=()
    
    for cmd in proot wget tar gzip; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        print_ew "error" "Missing packages: ${missing_deps[*]}"
        print_ew "info" "Install with: pkg install ${missing_deps[*]}"
        exit 1
    fi
    
    print_ew "success" "All dependencies installed!"
}

detect_architecture() {
    local arch
    arch="$(uname -m)"
    
    case "$arch" in
        aarch64|arm64)
            echo "arm64"
            ;;
        armv7l|armv8l|arm)
            echo "armhf"
            ;;
        x86_64|amd64)
            echo "amd64"
            ;;
        i386|i686)
            echo "i386"
            ;;
        *)
            print_ew "error" "Unsupported architecture: $arch"
            exit 1
            ;;
    esac
}

verify_archive() {
    local archive="$1"
    
    print_ew "info" "Verifying archive..."
    
    # Check file exists and not empty
    if [ ! -f "$archive" ] || [ ! -s "$archive" ]; then
        print_ew "error" "Archive missing or empty!"
        return 1
    fi
    
    # Check file size (should be > 100MB)
    local size_bytes
    size_bytes="$(stat -c%s "$archive" 2>/dev/null || stat -f%z "$archive" 2>/dev/null || echo "0")"
    local size_mb=$((size_bytes / 1024 / 1024))
    
    print_ew "info" "Archive size: ${size_mb}MB"
    
    if [ "$size_mb" -lt 100 ]; then
        print_ew "error" "Archive too small (${size_mb}MB)! Expected >100MB"
        return 1
    fi
    
    # Test gzip integrity
    print_ew "info" "Testing gzip integrity..."
    if ! gzip -t "$archive" 2>&1; then
        print_ew "error" "Archive corrupted (gzip test failed)!"
        return 1
    fi
    
    # Test tar listing (just first few entries)
    print_ew "info" "Testing tar contents..."
    if ! tar -tzf "$archive" 2>/dev/null | head -5 > /dev/null; then
        print_ew "error" "Archive corrupted (tar test failed)!"
        return 1
    fi
    
    print_ew "success" "Archive verification passed!"
    return 0
}

download_rootfs() {
    local architecture="$1"
    local url="https://partner-images.canonical.com/core/${UBUNTU_VERSION}/current/ubuntu-${UBUNTU_VERSION}-core-cloudimg-${architecture}-root.tar.gz"
    
    print_ew "info" "========================================="
    print_ew "info" "Downloading Ubuntu ${UBUNTU_VERSION} (${architecture})"
    print_ew "info" "========================================="
    print_ew "info" "Source: Canonical Partner Images"
    print_ew "info" "Expected size: ~130-180MB"
    print_ew "info" "Time estimate: 3-10 minutes"
    echo ""
    
    local retry=0
    local download_success=false
    
    while [ $retry -lt $MAX_DOWNLOAD_RETRIES ]; do
        if [ $retry -gt 0 ]; then
            print_ew "warn" "Retry $((retry + 1))/$MAX_DOWNLOAD_RETRIES..."
            sleep 3
        fi
        
        # Remove any partial downloads
        rm -f "$ARCHIVE_FILE" "${ARCHIVE_FILE}.partial" 2>/dev/null || true
        
        print_ew "info" "Starting download..."
        
        # Use wget with better options
        if wget "$url" \
            -O "$ARCHIVE_FILE" \
            --no-check-certificate \
            --timeout=60 \
            --waitretry=5 \
            --tries=2 \
            --progress=dot:giga \
            2>&1; then
            
            echo ""
            print_ew "info" "Download completed, verifying..."
            
            # Verify the download
            if verify_archive "$ARCHIVE_FILE"; then
                download_success=true
                break
            else
                print_ew "warn" "Verification failed!"
            fi
        else
            echo ""
            print_ew "warn" "Download failed!"
        fi
        
        retry=$((retry + 1))
    done
    
    if [ "$download_success" = false ]; then
        print_ew "error" "========================================="
        print_ew "error" "Download failed after $MAX_DOWNLOAD_RETRIES attempts!"
        print_ew "error" "========================================="
        print_ew "error" "Troubleshooting:"
        print_ew "info" "1. Check internet connection"
        print_ew "info" "2. Try again later (server may be busy)"
        print_ew "info" "3. Check storage space: df -h ~"
        print_ew "info" "4. Try from Termux home: cd ~"
        rm -f "$ARCHIVE_FILE"
        exit 1
    fi
    
    print_ew "success" "Download successful!"
}

extract_rootfs() {
    print_ew "info" "========================================="
    print_ew "info" "Extracting Ubuntu rootfs"
    print_ew "info" "========================================="
    print_ew "info" "Creating directory: $DIRECTORY"
    
    mkdir -p "$DIRECTORY"
    
    print_ew "warn" "This will take 5-15 minutes!"
    print_ew "warn" "Symlink warnings are NORMAL - ignore them"
    print_ew "info" ""
    print_ew "info" "Starting extraction..."
    
    cd "$DIRECTORY"
    
    # Extract with proot
    if proot --link2symlink tar -xzf "../${ARCHIVE_FILE}" --exclude='dev' 2>&1 | \
       grep -v "Cannot create symlink" | \
       tee ../extract.log; then
        
        cd ..
        print_ew "success" "Extraction phase complete!"
    else
        cd ..
        print_ew "error" "Extraction failed!"
        exit 1
    fi
    
    # Check for critical errors
    if grep -q "Error is not recoverable\|invalid compressed data\|Unexpected EOF" extract.log 2>/dev/null; then
        print_ew "error" "Critical errors found during extraction!"
        cat extract.log | tail -20
        exit 1
    fi
    
    # Verify critical files
    print_ew "info" "Verifying installation..."
    
    local critical_files=(
        "$DIRECTORY/bin/bash"
        "$DIRECTORY/bin/sh"
        "$DIRECTORY/usr/bin/env"
        "$DIRECTORY/etc/passwd"
        "$DIRECTORY/lib"
        "$DIRECTORY/usr"
    )
    
    local missing_files=()
    for file in "${critical_files[@]}"; do
        if [ ! -e "$file" ]; then
            missing_files+=("$file")
        fi
    done
    
    if [ ${#missing_files[@]} -gt 0 ]; then
        print_ew "error" "Installation incomplete! Missing:"
        for file in "${missing_files[@]}"; do
            print_ew "error" "  - $file"
        done
        exit 1
    fi
    
    print_ew "success" "All critical files verified!"
}

configure_rootfs() {
    print_ew "info" "Configuring Ubuntu..."
    
    # DNS configuration
    cat > "${DIRECTORY}/etc/resolv.conf" <<-'EOF'
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 1.1.1.1
EOF
    
    # Create stubs for compatibility
    if [ -f "${DIRECTORY}/usr/bin/groups" ]; then
        cat > "${DIRECTORY}/usr/bin/groups" <<-'EOF'
#!/bin/sh
exit 0
EOF
        chmod +x "${DIRECTORY}/usr/bin/groups"
    fi
    
    print_ew "success" "Configuration complete!"
}

create_start_script() {
    print_ew "info" "Creating start script..."
    
    mkdir -p "$BINDS_DIR"
    
    cat > "$START_SCRIPT" <<-'EOFSTART'
#!/data/data/com.termux/files/usr/bin/bash
cd "$(dirname "$0")" || exit 1

if [ ! -d "ubuntu-fs" ]; then
    echo "Error: ubuntu-fs not found!"
    echo "Please run the installer."
    exit 1
fi

if [ ! -f "ubuntu-fs/bin/bash" ]; then
    echo "Error: Installation incomplete!"
    exit 1
fi

unset LD_PRELOAD

exec proot \
    --link2symlink \
    -0 \
    -r ubuntu-fs \
    -b /dev \
    -b /proc \
    -b /sys \
    -b ubuntu-fs/tmp:/dev/shm \
    -b /data/data/com.termux \
    -b /:/host-rootfs \
    -b /sdcard \
    -b /storage \
    -b /mnt \
    -w /root \
    /usr/bin/env -i \
    HOME=/root \
    PATH=/usr/local/sbin:/usr/local/bin:/bin:/usr/bin:/sbin:/usr/sbin:/usr/games:/usr/local/games \
    TERM="${TERM:-xterm-256color}" \
    LANG=C.UTF-8 \
    /bin/bash --login "$@"
EOFSTART
    
    chmod +x "$START_SCRIPT"
    
    if command -v termux-fix-shebang &> /dev/null; then
        termux-fix-shebang "$START_SCRIPT" 2>/dev/null || true
    fi
    
    print_ew "success" "Start script created!"
}

cleanup_temp() {
    print_ew "info" "Cleaning temporary files..."
    rm -f "$ARCHIVE_FILE" extract.log 2>/dev/null || true
}

fn_install() {
    clear
    
    echo ""
    print_ew "info" "========================================="
    print_ew "info" "  Ubuntu in Termux - Final Installer"
    print_ew "info" "========================================="
    echo ""
    
    # Show current location
    print_ew "info" "Current location: $(pwd)"
    print_ew "info" "Recommended location: /data/data/com.termux/files/home"
    echo ""
    
    # Check for existing installation
    if [ -d "$DIRECTORY" ]; then
        print_ew "warn" "Found existing installation!"
        print_ew "question" "Remove and reinstall? [y/N] "
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            cleanup_all
            echo ""
        else
            print_ew "info" "Keeping existing installation"
            if [ ! -f "$START_SCRIPT" ]; then
                create_start_script
            fi
            print_ew "info" "Start Ubuntu: bash $START_SCRIPT"
            exit 0
        fi
    fi
    
    # Pre-flight checks
    print_ew "info" "Running pre-flight checks..."
    check_write_permission
    check_storage
    check_dependencies
    echo ""
    
    # Architecture
    local architecture
    architecture="$(detect_architecture)"
    print_ew "info" "Architecture: $architecture"
    echo ""
    
    # Download
    if [ -f "$ARCHIVE_FILE" ]; then
        print_ew "warn" "Found existing archive"
        if verify_archive "$ARCHIVE_FILE"; then
            print_ew "success" "Archive is valid, using it"
        else
            print_ew "warn" "Archive corrupted, re-downloading"
            rm -f "$ARCHIVE_FILE"
            download_rootfs "$architecture"
        fi
    else
        download_rootfs "$architecture"
    fi
    echo ""
    
    # Extract
    extract_rootfs
    echo ""
    
    # Configure
    configure_rootfs
    
    # Create start script
    create_start_script
    
    # Cleanup
    cleanup_temp
    
    # Success!
    echo ""
    print_ew "success" "========================================="
    print_ew "success" "     Installation Complete!"
    print_ew "success" "========================================="
    echo ""
    print_ew "info" "Start Ubuntu:"
    print_ew "info" "  bash $START_SCRIPT"
    echo ""
    print_ew "info" "First-time setup (inside Ubuntu):"
    print_ew "info" "  apt update"
    print_ew "info" "  apt upgrade -y"
    print_ew "info" "  apt install sudo nano vim wget curl -y"
    echo ""
    print_ew "success" "Enjoy Ubuntu in Termux!"
    echo ""
}

trap 'print_ew "warn" "Interrupted!"; cleanup_failed; exit 130' INT

main() {
    check_termux
    
    case "${1:-}" in
        -y|--yes)
            fn_install
            ;;
        -c|--clean)
            cleanup_all
            print_ew "success" "Cleaned!"
            ;;
        -h|--help)
            cat <<-EOF

Ubuntu in Termux - Final Installer

Usage: bash $0 [OPTIONS]

Options:
  -y, --yes      Install without prompts
  -c, --clean    Remove all files
  -h, --help     Show this help

IMPORTANT:
  Run from Termux home directory!
  
  cd ~
  bash $0

EOF
            ;;
        "")
            print_ew "question" "Install Ubuntu? [Y/n] "
            read -r response
            
            if [[ "$response" =~ ^[Yy]$ ]] || [[ -z "$response" ]]; then
                fn_install
            else
                print_ew "info" "Cancelled"
            fi
            ;;
        *)
            print_ew "error" "Unknown option: $1"
            exit 1
            ;;
    esac
}

main "$@"
