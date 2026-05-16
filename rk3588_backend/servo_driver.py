#!/usr/bin/env python3
"""
RK3588S Servo PWM Driver
Controls steering servo via Linux PWM sysfs interface.

Parameters:
    SERVO_MID_DUTY = 157000    # Center position (nanoseconds)
    SERVO_R_LIMIT_DUTY = 15500  # Right limit offset
    SERVO_L_LIMIT_DUTY = 13500  # Left limit offset

PWM channel defaults to pwmchip0/pwm0.
"""

import os
import time


class ServoDriver:
    """
    PWM servo driver for steering control.
    Uses Linux sysfs PWM interface: /sys/class/pwm/pwmchip0/pwm0
    """

    SERVO_MID_DUTY = 157000       # Center (ns)
    SERVO_R_LIMIT_DUTY = 15500    # Max right offset (ns)
    SERVO_L_LIMIT_DUTY = 13500    # Max left offset (ns)

    # Typical 50Hz servo: period = 20ms = 20000000 ns
    SERVO_PERIOD_NS = 20000000

    def __init__(self, chip: int = 0, channel: int = 0):
        self.chip = chip
        self.channel = channel
        self.pwm_base = f"/sys/class/pwm/pwmchip{chip}"
        self.pwm_path = f"{self.pwm_base}/pwm{channel}"
        self.enabled = False
        self.current_duty = self.SERVO_MID_DUTY

    def _write_sysfs(self, path: str, value: str):
        """Write value to sysfs path"""
        try:
            with open(path, 'w') as f:
                f.write(value)
        except Exception as e:
            print(f"[Servo] Sysfs write error ({path}): {e}")

    def _read_sysfs(self, path: str) -> str:
        """Read value from sysfs path"""
        try:
            with open(path, 'r') as f:
                return f.read().strip()
        except Exception:
            return ""

    def init(self) -> bool:
        """Export and initialize PWM channel"""
        try:
            # Export PWM if not already exported
            if not os.path.exists(self.pwm_path):
                export_path = f"{self.pwm_base}/export"
                self._write_sysfs(export_path, str(self.channel))
                time.sleep(0.2)

            # Set period (20ms for 50Hz servo)
            self._write_sysfs(f"{self.pwm_path}/period", str(self.SERVO_PERIOD_NS))
            # Set initial duty to center
            self._write_sysfs(f"{self.pwm_path}/duty_cycle", str(self.SERVO_MID_DUTY))
            # Enable PWM
            self._write_sysfs(f"{self.pwm_path}/enable", "1")
            self.enabled = True
            self.current_duty = self.SERVO_MID_DUTY
            print(f"[Servo] PWM initialized: chip={self.chip}, channel={self.channel}")
            print(f"[Servo] Center={self.SERVO_MID_DUTY}ns, Right=+{self.SERVO_R_LIMIT_DUTY}ns, Left=-{self.SERVO_L_LIMIT_DUTY}ns")
            return True
        except Exception as e:
            print(f"[Servo] Failed to initialize PWM: {e}")
            return False

    def set_angle(self, angle_percent: float):
        """
        Set servo angle as percentage.
        angle_percent: -100.0 (full left) to +100.0 (full right), 0 = center
        """
        if not self.enabled:
            return

        # Clamp to [-100, 100]
        angle_percent = max(-100.0, min(100.0, angle_percent))

        if angle_percent >= 0:
            # Right side: interpolate from center to center + R_LIMIT
            duty_ns = self.SERVO_MID_DUTY + int((angle_percent / 100.0) * self.SERVO_R_LIMIT_DUTY)
        else:
            # Left side: interpolate from center to center - L_LIMIT
            duty_ns = self.SERVO_MID_DUTY + int((angle_percent / 100.0) * self.SERVO_L_LIMIT_DUTY)

        self._write_sysfs(f"{self.pwm_path}/duty_cycle", str(duty_ns))
        self.current_duty = duty_ns

    def center(self):
        """Return servo to center position"""
        self.set_angle(0)

    def release(self):
        """Disable PWM and unexport"""
        if os.path.exists(self.pwm_path):
            self._write_sysfs(f"{self.pwm_path}/enable", "0")
            unexport_path = f"{self.pwm_base}/unexport"
            self._write_sysfs(unexport_path, str(self.channel))
        self.enabled = False
        print("[Servo] PWM released")

    def get_state(self) -> dict:
        """Get current servo state"""
        return {
            "enabled": self.enabled,
            "current_duty_ns": self.current_duty,
            "center_duty_ns": self.SERVO_MID_DUTY,
            "right_limit_ns": self.SERVO_R_LIMIT_DUTY,
            "left_limit_ns": self.SERVO_L_LIMIT_DUTY,
        }


# ============ Standalone Test ============
if __name__ == "__main__":
    servo = ServoDriver()
    if servo.init():
        try:
            print("Testing servo movement...")
            for i in range(-100, 101, 20):
                servo.set_angle(i)
                print(f"Angle: {i:4}% -> Duty: {servo.current_duty}ns")
                time.sleep(0.5)
            servo.center()
            print("Test complete, servo centered.")
            time.sleep(1)
        except KeyboardInterrupt:
            pass
        finally:
            servo.release()
    else:
        print("PWM not available. Make sure pwmchip0 is enabled in device tree.")
