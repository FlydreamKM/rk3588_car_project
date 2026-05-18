#!/bin/bash
# RK3588S USB Serial Device Scanner
# Lists all USB-to-TTL devices and their /dev/ttyUSB* mappings

echo "=== USB Serial Device Scan ==="
echo ""

echo "--- /dev/ttyUSB* ports ---"
ls -la /dev/ttyUSB* 2>/dev/null || echo "No ttyUSB devices found"
echo ""

echo "--- /dev/ttyACM* ports ---"
ls -la /dev/ttyACM* 2>/dev/null || echo "No ttyACM devices found"
echo ""

echo "--- USB device details (vendor:product) ---"
for dev in /dev/ttyUSB* /dev/ttyACM*; do
    if [ -e "$dev" ]; then
        # Find sysfs path
        sysfs_path=$(udevadm info -q path -n "$dev" 2>/dev/null)
        if [ -n "$sysfs_path" ]; then
            # Get parent USB device info
            usb_dev=$(echo "$sysfs_path" | sed 's|/ttyUSB[0-9]*||; s|/ttyACM[0-9]*||')
            vendor=$(cat "/sys$usb_dev/../../idVendor" 2>/dev/null || echo "unknown")
            product=$(cat "/sys$usb_dev/../../idProduct" 2>/dev/null || echo "unknown")
            manufacturer=$(cat "/sys$usb_dev/../../manufacturer" 2>/dev/null || echo "unknown")
            echo "  $dev -> vendor=$vendor product=$product ($manufacturer)"
        fi
    fi
done
echo ""

echo "--- dmesg last 10 USB serial entries ---"
dmesg | grep -i "usb.*serial\|ttyUSB\|ttyACM\|ch34\|cp210\|ftdi\|pl2303" | tail -10
echo ""

echo "--- Currently open serial ports (lsof) ---"
if command -v lsof >/dev/null 2>&1; then
    lsof /dev/ttyUSB* /dev/ttyACM* 2>/dev/null || echo "No ports currently open"
else
    echo "lsof not installed, skipping"
fi
echo ""

echo "--- PWM sysfs availability ---"
ls -la /sys/class/pwm/ 2>/dev/null || echo "No PWM sysfs found"
echo ""

echo "--- Video devices ---"
ls -la /dev/video* 2>/dev/null || echo "No video devices found"
echo ""

echo "--- Port 5000 usage ---"
ss -tlnp 2>/dev/null | grep 5000 || netstat -tlnp 2>/dev/null | grep 5000 || echo "No process on port 5000"
echo ""

echo "=== End Scan ==="
echo ""
echo "To assign specific ports, run:"
echo "  export MOTOR_PORT=/dev/ttyUSB0"
echo "  export IMU_PORT=/dev/ttyUSB1"
echo "  export TRACKING_PORT=/dev/ttyUSB2"
echo "  ./start.sh"
