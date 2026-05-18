#!/usr/bin/env python3
"""
RK3588S Servo PWM Driver
Controls steering servo via Linux PWM sysfs interface.

Parameters:
    SERVO_MID_DUTY = 157000    # Center position (nanoseconds)
    SERVO_R_LIMIT_DUTY = 15500  # Right limit offset
    SERVO_L_LIMIT_DUTY = 13500  # Left limit offset

OrangePi 5: PWM may be on pwmchip4 instead of pwmchip0.
Set SERVO_PWM_CHIP env var or pass chip=4 to constructor.
"""

import os
import time


class ServoDriver:
    """
    PWM servo driver for steering control.
    Tries sysfs PWM first, falls back to gpiod if available.
    """

    SERVO_MID_DUTY = 157000       # Center (ns)
    SERVO_R_LIMIT_DUTY = 15500    # Max right offset (ns)
    SERVO_L_LIMIT_DUTY = 13500    # Max left offset (ns)

    # Typical 50Hz servo: period = 20ms = 20000000 ns
    SERVO_PERIOD_NS = 20000000

    def __init__(self, chip: int = None, channel: int = 0):
        self.chip = chip if chip is not None else int(os.environ.get('SERVO_PWM_CHIP', '4'))
        self.channel = channel
        self.pwm_base = ""
        self.pwm_path = ""
        self.enabled = False
        self.current_duty = self.SERVO_MID_DUTY
        self._gpiod_chip = None
        self._gpiod_line = None
        self._use_gpiod = False

    def _write_sysfs(self, path: str, value: str):
        """Write value to sysfs path"""
        try:
            with open(path, 'w') as f:
                f.write(value)
        except Exception as e:
            print(f"[Servo] Sysfs write error ({path}): {e}")

    def _find_pwm_chip(self) -> int:
        """Find available PWM chip. OrangePi 5 often uses chip 4."""
        # Try user-specified chip first
        base = f"/sys/class/pwm/pwmchip{self.chip}"
        if os.path.exists(base):
            return self.chip
        # Fallback chips to try
        for fallback in [4, 0, 1, 2, 5, 6]:
            base = f"/sys/class/pwm/pwmchip{fallback}"
            if os.path.exists(base):
                print(f"[Servo] Fallback to pwmchip{fallback}")
                self.chip = fallback
                return fallback
        return -1

    def _try_gpiod_init(self) -> bool:
        """Try initializing via python-periphery (gpiod wrapper)"""
        try:
            from periphery import PWM
            # Common OrangePi 5 mappings: chip=0, channel varies by pin
            pwm = PWM(self.chip, self.channel)
            pwm.frequency = 50          # 50Hz
            pwm.duty_cycle = 0.075      # 1.5ms / 20ms = 7.5% center
            pwm.enable = True
            self._gpiod_pwm = pwm
            self._use_gpiod = True
            self.enabled = True
            print(f"[Servo] Initialized via gpiod: chip={self.chip}, channel={self.channel}")
            return True
        except ImportError:
            print("[Servo] python-periphery not installed. Run: pip install python-periphery")
        except Exception as e:
            print(f"[Servo] gpiod init failed: {e}")
        return False

    def init(self) -> bool:
        """Export and initialize PWM channel"""
        # Strategy 1: sysfs PWM
        chip = self._find_pwm_chip()
        if chip >= 0:
            self.pwm_base = f"/sys/class/pwm/pwmchip{chip}"
            self.pwm_path = f"{self.pwm_base}/pwm{self.channel}"
            try:
                # Export PWM if not already exported
                if not os.path.exists(self.pwm_path):
                    export_path = f"{self.pwm_base}/export"
                    self._write_sysfs(export_path, str(self.channel))
                    time.sleep(0.3)

                # Set period (20ms for 50Hz servo)
                self._write_sysfs(f"{self.pwm_path}/period", str(self.SERVO_PERIOD_NS))
                # Set initial duty to center
                self._write_sysfs(f"{self.pwm_path}/duty_cycle", str(self.SERVO_MID_DUTY))
                # Enable PWM
                self._write_sysfs(f"{self.pwm_path}/enable", "1")
                self.enabled = True
                self.current_duty = self.SERVO_MID_DUTY
                print(f"[Servo] PWM initialized: chip={chip}, channel={self.channel}")
                print(f"[Servo] Center={self.SERVO_MID_DUTY}ns, Right=+{self.SERVO_R_LIMIT_DUTY}ns, Left=-{self.SERVO_L_LIMIT_DUTY}ns")
                return True
            except Exception as e:
                print(f"[Servo] Sysfs PWM init failed: {e}")

        # Strategy 2: gpiod fallback
        if self._try_gpiod_init():
            return True

        print("[Servo] PWM not available.")
        print("  For sysfs PWM: enable PWM overlay in Armbian (e.g., 'orangepi-config' or dtoverlay)")
        print("  For gpiod: run 'pip install python-periphery' and set SERVO_PWM_CHIP")
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

        if self._use_gpiod:
            try:
                # Convert ns duty to cycle ratio: duty_ns / period_ns
                self._gpiod_pwm.duty_cycle = duty_ns / self.SERVO_PERIOD_NS
            except Exception as e:
                print(f"[Servo] gpiod set error: {e}")
        else:
            self._write_sysfs(f"{self.pwm_path}/duty_cycle", str(duty_ns))
        self.current_duty = duty_ns

    def center(self):
        """Return servo to center position"""
        self.set_angle(0)

    def release(self):
        """Disable PWM and unexport"""
        if self._use_gpiod and self._gpiod_pwm is not None:
            try:
                self._gpiod_pwm.enable = False
                self._gpiod_pwm.close()
            except Exception:
                pass
            self._gpiod_pwm = None
            self._use_gpiod = False
        elif os.path.exists(self.pwm_path):
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
        print("PWM not available. Make sure pwmchip is enabled in device tree.")
        print("OrangePi 5: try 'sudo orangepi-config' to enable PWM overlays.")
