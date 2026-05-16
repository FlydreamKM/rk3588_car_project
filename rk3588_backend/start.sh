#!/bin/bash
# RK3588S Smart Car Backend Startup Script

cd "$(dirname "$0")"

# Install dependencies if needed
if [ ! -d "venv" ]; then
    echo "Creating virtual environment..."
    python3 -m venv venv
fi

source venv/bin/activate

echo "Installing dependencies..."
pip install -q -r requirements.txt

# Set motor port from environment or use default
export MOTOR_PORT=${MOTOR_PORT:-/dev/ttyUSB0}

echo "Starting RK3588S Smart Car Backend..."
echo "Motor port: $MOTOR_PORT"
echo "API: http://0.0.0.0:5000"
echo ""
echo "Press Ctrl+C to stop"

python app.py
