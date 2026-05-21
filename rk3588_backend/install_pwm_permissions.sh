#!/bin/bash
# Install udev rules for PWM permissions (no sudo needed for servo control)
# Run once: sudo bash install_pwm_permissions.sh

set -e

RULES_FILE="/etc/udev/rules.d/99-pwm.rules"

echo "Installing PWM udev rules..."

cat > "$RULES_FILE" << 'EOF'
# udev rule: allow all users to access PWM sysfs (OrangePi 5 / RK3588S)
# This lets ./start.sh run without sudo for pygame display + PWM servo control
SUBSYSTEM=="pwm", ACTION=="add", RUN+="/bin/chmod -R 777 /sys/class/pwm/%k"
SUBSYSTEM=="pwm", ACTION=="change", RUN+="/bin/chmod -R 777 /sys/class/pwm/%k"
EOF

# Apply rules
udevadm control --reload-rules
udevadm trigger --subsystem-match=pwm

echo "[OK] PWM udev rules installed at $RULES_FILE"
echo "     Restart or replug PWM device to apply."
echo "     After that, run ./start.sh WITHOUT sudo."
