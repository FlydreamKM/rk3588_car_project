#!/bin/bash
# RK3588S Smart Car Backend Startup Script
set -e

cd "$(dirname "$0")"

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

echo "Installing dependencies..."
# --prefer-binary: avoid compiling from source when wheels exist
# --upgrade: ensure versions match requirements.txt
pip install --prefer-binary --upgrade -r requirements.txt

# Set motor port from environment or use default
export MOTOR_PORT=${MOTOR_PORT:-/dev/ttyUSB0}

echo ""
echo "Starting RK3588S Smart Car Backend..."
echo "Motor port: $MOTOR_PORT"
echo "API: http://0.0.0.0:5000"
echo ""
echo "Press Ctrl+C to stop"

python app.py
