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

    # 55Hz servo: period = 1/55s ≈ 18.18ms
    SERVO_PERIOD_NS = 18181818

    # User's servo: duty_ratio 8%=center, 9%=left limit, 7%=right limit
    # sysfs on this platform has INVERTED output (measured 92% when writing 8%)
    # So we write period * (1 - target_ratio) to sysfs
    SERVO_CENTER_RATIO = 0.08   # 8% center
    SERVO_DELTA_RATIO = 0.01    # ±1% from center to limits
    SERVO_MIN_RATIO = 0.07      # 7% right limit
    SERVO_MAX_RATIO = 0.09      # 9% left limit

    def __init__(self, chip: int = None, channel: int = 0):
        self.chip = chip if chip is not None else int(os.environ.get('SERVO_PWM_CHIP', '4'))
        self.channel = channel
        self.pwm_base = ""
        self.pwm_path = ""
        self.enabled = False
        # Initialize center position using inverted duty for sysfs
        initial_duty = int(self.SERVO_PERIOD_NS * (1.0 - self.SERVO_CENTER_RATIO))
        self.current_duty = initial_duty
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
            pwm.frequency = 55          # 55Hz to match user's servo
            pwm.duty_cycle = 1.0 - self.SERVO_CENTER_RATIO  # 92% = 8% inverted
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

                # Set period (18.18ms for 55Hz servo)
                self._write_sysfs(f"{self.pwm_path}/period", str(self.SERVO_PERIOD_NS))
                # Set initial duty: inverted, so write 92% to get 8% output
                initial_duty = int(self.SERVO_PERIOD_NS * (1.0 - self.SERVO_CENTER_RATIO))
                self._write_sysfs(f"{self.pwm_path}/duty_cycle", str(initial_duty))
                # Enable PWM
                self._write_sysfs(f"{self.pwm_path}/enable", "1")
                self.enabled = True
                self.current_duty = initial_duty
                print(f"[Servo] PWM initialized: chip={chip}, channel={self.channel}")
                print(f"[Servo] Period={self.SERVO_PERIOD_NS}ns, Center ratio={self.SERVO_CENTER_RATIO}, Inverted output")
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

        # Convert angle to target duty ratio:
        #   -100 (left)  → 9%  (larger duty)
        #     +0 (center) → 8%
        #  +100 (right)  → 7%  (smaller duty)
        target_ratio = self.SERVO_CENTER_RATIO - (angle_percent / 100.0) * self.SERVO_DELTA_RATIO

        # Clamp to safe limits [7%, 9%]
        target_ratio = max(self.SERVO_MIN_RATIO, min(self.SERVO_MAX_RATIO, target_ratio))

        # INVERTED output: sysfs duty_cycle controls LOW time on this platform
        # Measured: writing 8% produces 92% on scope → write (1 - target)
        duty_ns = int(self.SERVO_PERIOD_NS * (1.0 - target_ratio))

        # Final safety clamp: keep within [91%, 93%] of period for sysfs
        min_duty = int(self.SERVO_PERIOD_NS * (1.0 - self.SERVO_MAX_RATIO))  # 91%
        max_duty = int(self.SERVO_PERIOD_NS * (1.0 - self.SERVO_MIN_RATIO))  # 93%
        duty_ns = max(min_duty, min(duty_ns, max_duty))

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
            "period_ns": self.SERVO_PERIOD_NS,
            "center_ratio": self.SERVO_CENTER_RATIO,
            "left_ratio": self.SERVO_MAX_RATIO,
            "right_ratio": self.SERVO_MIN_RATIO,
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
