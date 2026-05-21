#!/bin/bash
# RK3588S Smart Car Backend Startup Script
# NOTE: Run WITHOUT sudo. PWM permissions are handled by udev rules.
#       If PWM fails with permission denied, run: sudo bash install_pwm_permissions.sh
set -e

cd "$(dirname "$0")"

# Check if running as root — warn but don't block (user may have udev rules)
if [ "$(id -u)" -eq 0 ]; then
    echo "[!] Running as root. pygame display may fail to connect to KDE."
    echo "    Recommendation: run without sudo after installing PWM permissions:"
    echo "    sudo bash install_pwm_permissions.sh"
    echo ""
fi

# Kill any existing process on port 5000
PORT_PID=$(ss -tlnp 2>/dev/null | grep ':5000' | grep -oP 'pid=\K[0-9]+' || true)
if [ -n "$PORT_PID" ]; then
    echo "[!] Port 5000 is in use by PID $PORT_PID, stopping it..."
    kill "$PORT_PID" 2>/dev/null || kill -9 "$PORT_PID" 2>/dev/null || true
    sleep 1
fi

# Check system dependencies
check_cmd() { command -v "$1" > /dev/null 2>&1; }

if ! check_cmd pkg-config; then
    echo "[!] Missing pkg-config. Run: sudo apt update && sudo apt install -y pkg-config"
    exit 1
fi

# python3-dev is required for compiling some packages
if [ ! -f /usr/include/python3.*/Python.h ] && [ ! -f /usr/local/include/python3.*/Python.h ]; then
    echo "[!] Missing python3-dev (Python.h not found). Run:"
    echo "    sudo apt update && sudo apt install -y python3-dev"
    exit 1
fi

# Install dependencies if needed
if [ ! -d "venv" ]; then
    echo "Creating virtual environment..."
    python3 -m venv venv
fi

source venv/bin/activate

echo "Checking dependencies..."
# Only install if missing (avoid --upgrade which re-checks everything)
if ! python -c "import flask, flask_cors, cv2, numpy, pygame" 2>/dev/null; then
    pip install --prefer-binary -r requirements.txt
fi

# Set ports from environment or use defaults
# Wiring: IMU=ttyUSB0, Motor=ttyACM0, Tracking=ttyUSB1
export MOTOR_PORT=${MOTOR_PORT:-/dev/ttyACM0}
export IMU_PORT=${IMU_PORT:-/dev/ttyUSB0}
export TRACKING_PORT=${TRACKING_PORT:-/dev/ttyUSB1}
export SERVO_PWM_CHIP=${SERVO_PWM_CHIP:-4}   # OrangePi 5 default pwmchip4

echo ""
echo "Starting RK3588S Smart Car Backend..."
echo "Motor port:   $MOTOR_PORT"
echo "IMU port:     $IMU_PORT"
echo "Tracking port: $TRACKING_PORT"
echo "Servo PWM chip: pwmchip$SERVO_PWM_CHIP"
echo "API:          http://0.0.0.0:5000"
echo ""
echo "Press Ctrl+C to stop"

python app.py &
APP_PID=$!

# Wait for backend to bind port 5000 (max 10s, with 0.2s interval = 50 checks)
echo -n "Waiting for backend "
for i in {1..50}; do
    sleep 0.2
    if ss -tlnp 2>/dev/null | grep -q ":5000"; then
        echo ""
        echo "[DONE] RK3588S Backend Ready on port 5000"
        break
    fi
    echo -n "."
done

# If still not listening, report error
if ! ss -tlnp 2>/dev/null | grep -q ":5000"; then
    echo ""
    echo "[ERROR] Backend failed to start within 10 seconds"
    kill $APP_PID 2>/dev/null || true
    exit 1
fi

wait $APP_PID
