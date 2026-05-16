#!/usr/bin/env python3
"""
IMU Driver for RK3588S Smart Car
Reads IMU data via UART/USB-to-TTL serial port.
Based on YB-IMU module protocol (Yahboom IMU).

Compatible with /dev/ttyUSB* or /dev/ttyACM* devices.
Provides: accelerometer, gyroscope, magnetometer, quaternion, Euler angles.
"""

import serial
import struct
import threading
import time
from typing import Callable, Optional, Dict, Any


class YbImuDriver:
    """
    YB-IMU serial driver.
    Port auto-detection: /dev/myimu, /dev/ttyUSB0, /dev/ttyUSB1, /dev/ttyUSB2
    Baudrate: 115200 (default)
    """

    # Command bytes for YB-IMU protocol
    CMD_GET_ACC = 0x51
    CMD_GET_GYRO = 0x52
    CMD_GET_MAG = 0x53
    CMD_GET_QUAT = 0x59
    CMD_GET_EULER = 0x5A
    CMD_GET_BARO = 0x56

    def __init__(self, port: str = None, baudrate: int = 115200):
        self.port = port
        self.baudrate = baudrate
        self.serial = None
        self.running = False
        self.read_thread = None
        self.callbacks: list[Callable] = []

        # Sensor data (all raw / unscaled)
        self._ax = 0.0
        self._ay = 0.0
        self._az = 0.0
        self._gx = 0.0
        self._gy = 0.0
        self._gz = 0.0
        self._mx = 0.0
        self._my = 0.0
        self._mz = 0.0
        self._q0 = 1.0
        self._q1 = 0.0
        self._q2 = 0.0
        self._q3 = 0.0
        self._roll = 0.0
        self._pitch = 0.0
        self._yaw = 0.0
        self._temperature = 0.0
        self._pressure = 0.0
        self._timestamp = 0.0
        self._lock = threading.Lock()

    def _find_port(self) -> Optional[str]:
        """Auto-detect IMU serial port"""
        import os
        candidates = ["/dev/myimu", "/dev/ttyUSB0", "/dev/ttyUSB1", "/dev/ttyUSB2",
                        "/dev/ttyACM0", "/dev/ttyACM1"]
        for p in candidates:
            if os.path.exists(p):
                try:
                    # Quick open test
                    s = serial.Serial(p, self.baudrate, timeout=0.5)
                    s.close()
                    return p
                except Exception:
                    continue
        return None

    def connect(self) -> bool:
        """Connect to IMU serial port"""
        target_port = self.port or self._find_port()
        if not target_port:
            print("[IMU] No IMU port found")
            return False
        try:
            self.serial = serial.Serial(
                port=target_port,
                baudrate=self.baudrate,
                bytesize=serial.EIGHTBITS,
                parity=serial.PARITY_NONE,
                stopbits=serial.STOPBITS_ONE,
                timeout=0.05
            )
            self.running = True
            self.read_thread = threading.Thread(target=self._read_loop, daemon=True)
            self.read_thread.start()
            print(f"[IMU] Connected on {target_port}@{self.baudrate}")
            return True
        except Exception as e:
            print(f"[IMU] Failed to connect: {e}")
            return False

    def disconnect(self):
        """Disconnect from IMU"""
        self.running = False
        if self.read_thread:
            self.read_thread.join(timeout=1.0)
        if self.serial and self.serial.is_open:
            self.serial.close()
        print("[IMU] Disconnected")

    def _read_loop(self):
        """Background read loop parsing YB-IMU binary frames"""
        buffer = bytearray()
        while self.running:
            try:
                if self.serial and self.serial.is_open:
                    data = self.serial.read(max(1, self.serial.in_waiting))
                    if data:
                        buffer.extend(data)
                        # Parse all complete frames in buffer
                        while len(buffer) >= 11:
                            # YB-IMU frame: 0x55 + type_byte + 8 data bytes + checksum
                            idx = buffer.find(0x55)
                            if idx < 0 or len(buffer) - idx < 11:
                                break
                            frame = buffer[idx:idx+11]
                            self._parse_frame(frame)
                            buffer = buffer[idx+11:]
            except Exception as e:
                print(f"[IMU] Read error: {e}")
                time.sleep(0.01)

    def _parse_frame(self, frame: bytes):
        """Parse a single 11-byte YB-IMU frame"""
        if len(frame) < 11:
            return
        # Verify checksum
        checksum = sum(frame[:10]) & 0xFF
        if checksum != frame[10]:
            return

        data_type = frame[1]
        payload = frame[2:10]

        with self._lock:
            self._timestamp = time.time()
            if data_type == self.CMD_GET_ACC:
                # Accelerometer: x, y, z (16-bit signed, scale / 32768 * 16g)
                ax, ay, az = struct.unpack('<hhh', payload[:6])
                self._ax = ax / 32768.0 * 16.0 * 9.8
                self._ay = ay / 32768.0 * 16.0 * 9.8
                self._az = az / 32768.0 * 16.0 * 9.8
            elif data_type == self.CMD_GET_GYRO:
                # Gyroscope: x, y, z (16-bit signed, scale / 32768 * 2000 deg/s)
                gx, gy, gz = struct.unpack('<hhh', payload[:6])
                self._gx = gx / 32768.0 * 2000.0
                self._gy = gy / 32768.0 * 2000.0
                self._gz = gz / 32768.0 * 2000.0
            elif data_type == self.CMD_GET_MAG:
                # Magnetometer: x, y, z
                mx, my, mz = struct.unpack('<hhh', payload[:6])
                self._mx = mx
                self._my = my
                self._mz = mz
            elif data_type == self.CMD_GET_QUAT:
                # Quaternion: q0, q1, q2, q3 (16-bit signed, scale / 32768)
                q0, q1, q2, q3 = struct.unpack('<hhhh', payload[:8])
                self._q0 = q0 / 32768.0
                self._q1 = q1 / 32768.0
                self._q2 = q2 / 32768.0
                self._q3 = q3 / 32768.0
            elif data_type == self.CMD_GET_EULER:
                # Euler angles: roll, pitch, yaw (16-bit signed, scale / 32768 * 180)
                roll, pitch, yaw = struct.unpack('<hhh', payload[:6])
                self._roll = roll / 32768.0 * 180.0
                self._pitch = pitch / 32768.0 * 180.0
                self._yaw = yaw / 32768.0 * 180.0
            elif data_type == self.CMD_GET_BARO:
                # Barometer: temperature (16-bit signed, /100), pressure (24-bit unsigned)
                temp = struct.unpack('<h', payload[:2])[0]
                press = struct.unpack('<I', payload[2:6] + b'\x00')[0]
                self._temperature = temp / 100.0
                self._pressure = press / 100.0

        # Notify callbacks
        for cb in self.callbacks:
            try:
                cb(self.get_state())
            except Exception as e:
                print(f"[IMU] Callback error: {e}")

    def get_state(self) -> Dict[str, Any]:
        """Get current IMU state"""
        with self._lock:
            return {
                "accelerometer": {"x": self._ax, "y": self._ay, "z": self._az},
                "gyroscope": {"x": self._gx, "y": self._gy, "z": self._gz},
                "magnetometer": {"x": self._mx, "y": self._my, "z": self._mz},
                "quaternion": {"w": self._q0, "x": self._q1, "y": self._q2, "z": self._q3},
                "euler": {"roll": self._roll, "pitch": self._pitch, "yaw": self._yaw},
                "temperature": self._temperature,
                "pressure": self._pressure,
                "timestamp": self._timestamp,
            }

    def register_callback(self, callback: Callable):
        self.callbacks.append(callback)

    def unregister_callback(self, callback: Callable):
        if callback in self.callbacks:
            self.callbacks.remove(callback)


# ============ Standalone Test ============
if __name__ == "__main__":
    imu = YbImuDriver()
    if imu.connect():
        try:
            while True:
                state = imu.get_state()
                euler = state["euler"]
                print(f"\rRoll={euler['roll']:7.2f}° Pitch={euler['pitch']:7.2f}° Yaw={euler['yaw']:7.2f}°", end='', flush=True)
                time.sleep(0.1)
        except KeyboardInterrupt:
            pass
        finally:
            imu.disconnect()
    else:
        print("IMU not available.")
