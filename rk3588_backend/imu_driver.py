#!/usr/bin/env python3
"""
IMU Driver for RK3588S Smart Car
Wraps the official YbImuSerialLib from Yahboom for robust IMU data reading.

Compatible with /dev/ttyUSB* devices on 115200 baud.
Provides: accelerometer, gyroscope, magnetometer, quaternion, Euler angles.
"""

import os
import threading
import time
from typing import Callable, Optional, Dict, Any

# Use the official YbImuLib from Yahboom
from YbImuLib.YbImuSerialLib import YbImuSerial


class YbImuDriver:
    """
    YB-IMU serial driver wrapper.
    Port auto-detection: /dev/ttyUSB0, /dev/ttyUSB1, /dev/ttyUSB2
    Baudrate: 115200
    """

    def __init__(self, port: str = None):
        self.port = port
        self._imu: Optional[YbImuSerial] = None
        self._running = False
        self._callbacks: list[Callable] = []
        self._lock = threading.Lock()
        self._connected = False

    def _find_port(self) -> Optional[str]:
        """Auto-detect IMU serial port, skipping motor port if known"""
        motor_port = os.environ.get('MOTOR_PORT', '/dev/ttyUSB0')
        candidates = [
            "/dev/ttyUSB1", "/dev/ttyUSB2", "/dev/ttyUSB3",
            "/dev/ttyACM0", "/dev/ttyACM1", "/dev/ttyTHS1",
            "/dev/ttyUSB0",  # last resort
        ]
        for p in candidates:
            if os.path.exists(p) and p != motor_port:
                return p
        # If only motor port exists, warn but return it anyway
        if os.path.exists(motor_port):
            print(f"[IMU] WARNING: Only {motor_port} available, may conflict with motor driver!")
            return motor_port
        return None

    def connect(self) -> bool:
        """Connect to IMU serial port using official YbImuLib"""
        target_port = self.port or self._find_port()
        if not target_port:
            print("[IMU] No IMU port found")
            return False

        try:
            self._imu = YbImuSerial(target_port, debug=False)
            # Start the official receive thread
            self._imu.create_receive_threading()
            time.sleep(0.5)  # Let thread start and buffer settle
            self._running = True
            self._connected = True
            print(f"[IMU] Connected on {target_port} via YbImuLib")
            return True
        except Exception as e:
            print(f"[IMU] Failed to connect: {e}")
            self._imu = None
            self._connected = False
            return False

    def disconnect(self):
        """Disconnect from IMU"""
        self._running = False
        self._connected = False
        if self._imu is not None:
            try:
                del self._imu
            except Exception:
                pass
            self._imu = None
        print("[IMU] Disconnected")

    def get_state(self) -> Dict[str, Any]:
        """Get current IMU state (thread-safe)"""
        if not self._connected or self._imu is None:
            return {
                "accelerometer": {"x": 0, "y": 0, "z": 0},
                "gyroscope": {"x": 0, "y": 0, "z": 0},
                "magnetometer": {"x": 0, "y": 0, "z": 0},
                "quaternion": {"w": 1, "x": 0, "y": 0, "z": 0},
                "euler": {"roll": 0, "pitch": 0, "yaw": 0},
                "temperature": 0,
                "pressure": 0,
                "timestamp": 0,
            }

        with self._lock:
            accel = self._imu.get_accelerometer_data()
            gyro = self._imu.get_gyroscope_data()
            mag = self._imu.get_magnetometer_data()
            euler = self._imu.get_imu_attitude_data(ToAngle=True)
            quat = self._imu.get_imu_quaternion_data()
            baro = self._imu.get_baro_data()

            return {
                "accelerometer": {"x": accel[0], "y": accel[1], "z": accel[2]},
                "gyroscope": {"x": gyro[0], "y": gyro[1], "z": gyro[2]},
                "magnetometer": {"x": mag[0], "y": mag[1], "z": mag[2]},
                "quaternion": {"w": quat[0], "x": quat[1], "y": quat[2], "z": quat[3]},
                "euler": {"roll": euler[0], "pitch": euler[1], "yaw": euler[2]},
                "temperature": baro[1] if len(baro) > 1 else 0,
                "pressure": baro[2] if len(baro) > 2 else 0,
                "timestamp": time.time(),
            }

    def register_callback(self, callback: Callable):
        self._callbacks.append(callback)

    def unregister_callback(self, callback: Callable):
        if callback in self._callbacks:
            self._callbacks.remove(callback)

    # ── Calibration API (wraps YbImuSerialLib) ──
    def get_version(self) -> Optional[str]:
        """Get IMU firmware version string like V1.0.0"""
        if not self._connected or self._imu is None:
            return None
        try:
            return self._imu.get_version()
        except Exception as e:
            print(f"[IMU] get_version error: {e}")
            return None

    def calibrate_imu(self) -> dict:
        """Calibrate accelerometer + gyroscope. Takes ~7 seconds."""
        if not self._connected or self._imu is None:
            return {"success": False, "error": "IMU not connected"}
        try:
            print("[IMU] Starting accelerometer + gyroscope calibration (keep still for ~7s)...")
            result = self._imu.calibration_imu()
            return {"success": True, "type": "imu", "result": result}
        except Exception as e:
            return {"success": False, "type": "imu", "error": str(e)}

    def calibrate_mag(self) -> dict:
        """Calibrate magnetometer. Requires rotating the device in all axes."""
        if not self._connected or self._imu is None:
            return {"success": False, "error": "IMU not connected"}
        try:
            print("[IMU] Starting magnetometer calibration — rotate device in all axes...")
            result = self._imu.calibration_mag()
            return {"success": True, "type": "mag", "result": result}
        except Exception as e:
            return {"success": False, "type": "mag", "error": str(e)}

    def calibrate_temperature(self, now_temperature: float) -> dict:
        """Calibrate temperature compensation. Provide current ambient temp in °C."""
        if not self._connected or self._imu is None:
            return {"success": False, "error": "IMU not connected"}
        try:
            if now_temperature > 50.0 or now_temperature < -50.0:
                return {"success": False, "error": "Temperature out of range (-50~50°C)"}
            print(f"[IMU] Starting temperature calibration at {now_temperature}°C...")
            result = self._imu.calibration_temperature(now_temperature)
            return {"success": True, "type": "temp", "temperature": now_temperature, "result": result}
        except Exception as e:
            return {"success": False, "type": "temp", "error": str(e)}

    def reset_user_data(self) -> dict:
        """Reset all calibration data to factory defaults."""
        if not self._connected or self._imu is None:
            return {"success": False, "error": "IMU not connected"}
        try:
            print("[IMU] Resetting all user calibration data to factory defaults...")
            self._imu.reset_user_data()
            return {"success": True, "type": "reset", "message": "User data reset. Re-calibration recommended."}
        except Exception as e:
            return {"success": False, "type": "reset", "error": str(e)}


# ============ Standalone Test ============
if __name__ == "__main__":
    imu = YbImuDriver()
    if imu.connect():
        try:
            while True:
                state = imu.get_state()
                euler = state["euler"]
                print(
                    f"\rRoll={euler['roll']:7.2f}° "
                    f"Pitch={euler['pitch']:7.2f}° "
                    f"Yaw={euler['yaw']:7.2f}°",
                    end='', flush=True,
                )
                time.sleep(0.1)
        except KeyboardInterrupt:
            pass
        finally:
            imu.disconnect()
    else:
        print("IMU not available.")
