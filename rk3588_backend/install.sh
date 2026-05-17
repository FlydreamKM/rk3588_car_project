#!/bin/bash
###############################################################################
# RK3588S Smart Car Backend - Installation Script
# 
# Verifies and installs all system & Python dependencies.
# Run with: sudo ./install.sh
###############################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging helpers
info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

# Script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="${SCRIPT_DIR}/venv"
REQUIREMENTS="${SCRIPT_DIR}/requirements.txt"

# Detect system info
ARCH=$(uname -m)
DISTRO=$(lsb_release -is 2>/dev/null || echo "unknown")
CODENAME=$(lsb_release -cs 2>/dev/null || echo "unknown")
PYTHON3=$(command -v python3 || true)

###############################################################################
# 0. Pre-flight checks
###############################################################################
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║     RK3588S Smart Car Backend - Dependency Installer         ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

info "Detected architecture: ${ARCH}"
info "Detected distro: ${DISTRO} (${CODENAME})"

if [ "$EUID" -ne 0 ]; then
    error "This script must be run as root (use sudo)."
    exit 1
fi

if [ -z "$PYTHON3" ]; then
    error "python3 not found. Please install Python 3 first."
    exit 1
fi

PYTHON_VERSION=$($PYTHON3 --version 2>&1 | awk '{print $2}')
info "Python version: ${PYTHON_VERSION}"

# Parse major.minor
PY_MAJOR=$(echo "$PYTHON_VERSION" | cut -d. -f1)
PY_MINOR=$(echo "$PYTHON_VERSION" | cut -d. -f2)

if [ "$PY_MAJOR" -lt 3 ] || { [ "$PY_MAJOR" -eq 3 ] && [ "$PY_MINOR" -lt 10 ]; }; then
    error "Python 3.10+ required, found ${PYTHON_VERSION}"
    exit 1
fi

ok "Python version OK (>= 3.10)"

###############################################################################
# 1. System package installation
###############################################################################
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Step 1: Installing system dependencies (apt)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Core build tools
SYSTEM_PACKAGES=(
    # Build essentials
    "python3-dev"
    "python3-pip"
    "python3-venv"
    "pkg-config"
    "build-essential"
    "cmake"
    
    # SDL2 for pygame (KMS/DRM + X11 fallbacks)
    "libsdl2-dev"
    "libsdl2-image-2.0-0"
    "libsdl2-mixer-2.0-0"
    "libsdl2-ttf-2.0-0"
    "libsdl2-gfx-1.0-0"
    
    # OpenCV dependencies (headless but needs some libs)
    "libgl1"
    "libglx-mesa0"
    "libglib2.0-0"
    "libsm6"
    "libxext6"
    "libxrender-dev"
    "libgomp1"
    
    # Serial / USB
    "udev"
    
    # Optional but recommended
    "libportaudio2"      # For pygame audio (optional)
    "fonts-noto-cjk"   # For display Chinese text fallback
)

info "Updating package lists..."
apt-get update -qq

info "Installing system packages..."
apt-get install -y -qq --no-install-recommends "${SYSTEM_PACKAGES[@]}"

# Verify critical packages
info "Verifying critical system packages..."
MISSING_PKGS=()

for pkg in python3-dev pkg-config libsdl2-dev; do
    if ! dpkg -l | grep -q "^ii  ${pkg} "; then
        MISSING_PKGS+=("$pkg")
    fi
done

if [ ${#MISSING_PKGS[@]} -gt 0 ]; then
    error "Failed to install: ${MISSING_PKGS[*]}"
    exit 1
fi

ok "System packages installed"

###############################################################################
# 2. Python development headers check
###############################################################################
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Step 2: Verifying Python development headers"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

PYTHON_INCLUDE_DIR=$($PYTHON3 -c "import sysconfig; print(sysconfig.get_path('include'))" 2>/dev/null || true)
PYTHON_H="${PYTHON_INCLUDE_DIR}/Python.h"

if [ -f "$PYTHON_H" ]; then
    ok "Python.h found: ${PYTHON_H}"
else
    # Try alternate locations
    FOUND=false
    for path in /usr/include/python3.*/Python.h /usr/local/include/python3.*/Python.h; do
        if [ -f "$path" ]; then
            ok "Python.h found: ${path}"
            FOUND=true
            break
        fi
    done
    
    if [ "$FOUND" = false ]; then
        error "Python.h not found. python3-dev may be corrupted or for wrong version."
        error "Expected at: ${PYTHON_H}"
        exit 1
    fi
fi

###############################################################################
# 3. Hardware capability checks
###############################################################################
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Step 3: Checking hardware interfaces"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# PWM sysfs
info "Checking PWM support..."
if [ -d /sys/class/pwm ]; then
    PWM_CHIPS=$(ls /sys/class/pwm/ 2>/dev/null | grep pwmchip | wc -l)
    if [ "$PWM_CHIPS" -gt 0 ]; then
        ok "PWM subsystem found (${PWM_CHIPS} chip(s))"
    else
        warn "PWM subsystem exists but no pwmchip found."
        warn "  → Servo control will not work until pwmchip is enabled in device tree."
    fi
else
    warn "PWM sysfs not available."
    warn "  → Install device tree overlay or kernel module for PWM."
fi

# Serial ports
info "Checking serial ports..."
for port in /dev/ttyUSB0 /dev/ttyUSB1 /dev/ttyACM0; do
    if [ -e "$port" ]; then
        ok "Serial port found: ${port}"
        # Check permissions
        if [ -r "$port" ] && [ -w "$port" ]; then
            ok "  ${port} is readable/writable"
        else
            warn "  ${port} exists but current user may lack permissions"
            warn "  → Add user to 'dialout' group: sudo usermod -a -G dialout $SUDO_USER"
        fi
    else
        warn "Serial port not found: ${port} (will be checked at runtime)"
    fi
done

# Camera
info "Checking camera..."
if [ -e /dev/video0 ]; then
    ok "Camera device found: /dev/video0"
else
    warn "Camera /dev/video0 not found (will use placeholder mode)"
fi

# Display / DRM
info "Checking display (KMS/DRM)..."
if [ -d /sys/class/drm ]; then
    DRM_CARDS=$(ls /sys/class/drm/ 2>/dev/null | grep card | wc -l)
    if [ "$DRM_CARDS" -gt 0 ]; then
        ok "DRM subsystem found (${DRM_CARDS} card(s))"
    else
        warn "DRM exists but no cards found"
    fi
else
    warn "DRM not available. Display will fall back to windowed/X11 mode."
fi

###############################################################################
# 4. User group setup (serial permissions)
###############################################################################
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Step 4: Setting up user permissions"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Get the user who ran sudo
if [ -n "${SUDO_USER:-}" ]; then
    TARGET_USER="$SUDO_USER"
else
    # Try to detect from environment
    TARGET_USER="${USER:-$(logname 2>/dev/null || echo "")}"
fi

if [ -n "$TARGET_USER" ] && [ "$TARGET_USER" != "root" ]; then
    info "Adding user '${TARGET_USER}' to 'dialout' group for serial access..."
    usermod -a -G dialout "$TARGET_USER" 2>/dev/null || true
    ok "User '${TARGET_USER}' added to dialout group"
    warn "  → You must LOG OUT and LOG BACK IN for group changes to take effect."
else
    warn "Could not detect non-root user. If running as root permanently, skip this."
    warn "  → Otherwise manually add your user: sudo usermod -a -G dialout \$USER"
fi

###############################################################################
# 5. Virtual environment setup
###############################################################################
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Step 5: Creating Python virtual environment"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ -d "$VENV_DIR" ]; then
    warn "Existing venv found at ${VENV_DIR}"
    read -p "  Remove and recreate? [Y/n] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        info "Removing old venv..."
        rm -rf "$VENV_DIR"
        info "Creating new virtual environment..."
        $PYTHON3 -m venv "$VENV_DIR"
        ok "Virtual environment recreated"
    else
        info "Keeping existing venv. Will upgrade packages."
    fi
else
    info "Creating virtual environment..."
    $PYTHON3 -m venv "$VENV_DIR"
    ok "Virtual environment created: ${VENV_DIR}"
fi

# Activate venv for the remainder of the script
info "Activating virtual environment..."
source "${VENV_DIR}/bin/activate"
ok "Virtual environment activated"

###############################################################################
# 6. Python package installation
###############################################################################
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Step 6: Installing Python packages"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

info "Upgrading pip, setuptools, wheel..."
pip install -q --upgrade pip setuptools wheel

if [ -f "$REQUIREMENTS" ]; then
    info "Installing from ${REQUIREMENTS}..."
    # --prefer-binary: avoid compiling from source when wheels exist
    # This is critical on aarch64 where compiling numpy/opencv can take hours
    pip install --prefer-binary -r "$REQUIREMENTS"
    ok "Python packages installed from requirements.txt"
else
    error "requirements.txt not found at ${REQUIREMENTS}"
    exit 1
fi

###############################################################################
# 7. Post-install verification
###############################################################################
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Step 7: Verifying Python imports"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

VERIFY_SCRIPT=$(cat <<'EOF'
import sys
errors = []

modules = {
    "Flask": "flask",
    "CORS": "flask_cors",
    "OpenCV": "cv2",
    "NumPy": "numpy",
    "Pygame": "pygame",
    "Serial": "serial",
    "Paramiko": "paramiko",
}

for name, module in modules.items():
    try:
        __import__(module)
        print(f"[OK]    {name} ({module})")
    except ImportError as e:
        print(f"[ERROR] {name} ({module}): {e}")
        errors.append(name)

if errors:
    print(f"\nFailed imports: {', '.join(errors)}")
    sys.exit(1)
else:
    print("\nAll Python dependencies verified.")
    sys.exit(0)
EOF
)

if $PYTHON3 -c "$VERIFY_SCRIPT"; then
    ok "All Python imports verified"
else
    error "Some Python packages failed to import. Check errors above."
    exit 1
fi

###############################################################################
# 8. Summary
###############################################################################
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║              Installation Complete                             ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
ok "Virtual environment: ${VENV_DIR}"
ok "Python: ${PYTHON_VERSION}"
ok "Architecture: ${ARCH}"
echo ""

if [ -n "$TARGET_USER" ] && [ "$TARGET_USER" != "root" ]; then
    warn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    warn "IMPORTANT: Log out and log back in for serial permissions!"
    warn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
fi

info "To start the backend:"
echo "    cd ${SCRIPT_DIR}"
echo "    sudo ./start.sh"
echo ""
info "To manually activate venv:"
echo "    source ${VENV_DIR}/bin/activate"
echo ""

# Check for any warnings to display
WARN_COUNT=0

# Summarize any hardware issues
if [ ! -e /dev/ttyUSB0 ] && [ ! -e /dev/ttyACM0 ]; then
    warn "⚠ No motor/IMU serial port detected. Connect USB↔TTL adapter."
    WARN_COUNT=$((WARN_COUNT + 1))
fi

if [ ! -d /sys/class/pwm/pwmchip0 ]; then
    warn "⚠ PWM chip not found. Servo steering requires pwmchip0 in device tree."
    WARN_COUNT=$((WARN_COUNT + 1))
fi

if [ ! -e /dev/video0 ]; then
    warn "⚠ Camera /dev/video0 not found. Video stream will use placeholder."
    WARN_COUNT=$((WARN_COUNT + 1))
fi

if [ $WARN_COUNT -gt 0 ]; then
    echo ""
    info "Some hardware was not detected — this is normal if devices are not yet connected."
    info "The backend will run in simulation/placeholder mode for missing hardware."
fi

ok "All done."
