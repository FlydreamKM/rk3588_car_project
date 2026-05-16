#!/usr/bin/env python3
"""
8-Channel Line Tracking (巡线) Driver for RK3588S Smart Car
Reads tracking sensor data via UART/USB-to-TTL and provides error value for PID control.

Protocol: The 8-channel module sends data as "$0,0,1,0,1,1,1,0#" (8 binary values)
Uses PID controller for smooth line following.

Reference: Adapted from Yahboom RaspbotV2 8-channel tracking examples.
"""

import serial
import threading
import time
from typing import Callable, Optional, Dict, Any, List
from PID import PositionalPID


class TrackingDriver:
    """
    8-channel infrared line tracking driver.
    Connects via serial port (UART/USB-to-TTL).
    """

    def __init__(self, port: str = "/dev/ttyUSB1", baudrate: int = 115200):
        self.port = port
        self.baudrate = baudrate
        self.serial = None
        self.running = False
        self.read_thread = None
        self.callbacks: list[Callable] = []

        # 8 sensor values [0/1] (0=black line detected, 1=no line)
        self._ir_data = [0, 0, 0, 0, 0, 0, 0, 0]
        self._error = 0
        self._timestamp = 0.0
        self._lock = threading.Lock()
        self._connected = False

        # PID for line following
        self.pid = PositionalPID(P=6.0, I=0.0, D=0.0)
        self.go_speed = 30  # base forward speed (arbitrary units)

    def connect(self) -> bool:
        """Connect to tracking module serial port"""
        try:
            self.serial = serial.Serial(
                port=self.port,
                baudrate=self.baudrate,
                bytesize=serial.EIGHTBITS,
                parity=serial.PARITY_NONE,
                stopbits=serial.STOPBITS_ONE,
                timeout=0.1
            )
            # Send init command to module (numeric-only mode)
            init_cmd = "$0,0,1#"
            self.serial.write(bytes(init_cmd, 'utf-8'))
            self.serial.flush()

            self.running = True
            self.read_thread = threading.Thread(target=self._read_loop, daemon=True)
            self.read_thread.start()
            self._connected = True
            print(f"[Tracking] Connected on {self.port}@{self.baudrate}")
            return True
        except Exception as e:
            print(f"[Tracking] Failed to connect: {e}")
            return False

    def disconnect(self):
        """Disconnect and stop module"""
        self.running = False
        if self.serial and self.serial.is_open:
            try:
                stop_cmd = "$0,0,0#"
                self.serial.write(bytes(stop_cmd, 'utf-8'))
            except Exception:
                pass
        if self.read_thread:
            self.read_thread.join(timeout=1.0)
        if self.serial and self.serial.is_open:
            self.serial.close()
        self._connected = False
        print("[Tracking] Disconnected")

    def _read_loop(self):
        """Background loop reading tracking data"""
        rx_buff = ""
        rx_started = False
        while self.running:
            try:
                if self.serial and self.serial.is_open:
                    data = self.serial.read(1)
                    if not data:
                        continue
                    ch = data.decode('utf-8', errors='ignore')
                    if not rx_started:
                        if ch == '$':
                            rx_started = True
                            rx_buff = ch
                    else:
                        rx_buff += ch
                        if ch == '#':
                            self._parse_packet(rx_buff)
                            rx_buff = ""
                            rx_started = False
            except Exception as e:
                print(f"[Tracking] Read error: {e}")
                time.sleep(0.01)

    def _parse_packet(self, packet: str):
        """Parse tracking packet like '$0,0,1,0,1,1,1,0#'"""
        try:
            # Remove $ and #, split by comma
            inner = packet[1:-1]
            parts = inner.split(',')
            if len(parts) >= 8:
                for i in range(8):
                    self._ir_data[i] = int(parts[i])
                self._compute_error()
                self._timestamp = time.time()
                self._connected = True

                # Notify callbacks
                state = self.get_state()
                for cb in self.callbacks:
                    try:
                        cb(state)
                    except Exception as e:
                        print(f"[Tracking] Callback error: {e}")
        except Exception as e:
            pass  # ignore malformed packets

    def _compute_error(self):
        """
        Compute line-following error from 8 IR sensors.
        Mapping (sensor indices 0-7, left to right):
        Left deviation  -> positive error
        Right deviation -> negative error
        Center (s3=0, s4=0) -> error=0
        """
        x = self._ir_data
        error = self._error  # default: keep last

        # Pre-defined patterns (0 = line detected under this sensor)
        if x[0] == 1 and x[1] == 1 and x[2] == 1 and x[3] == 0 and x[4] == 1 and x[5] == 1 and x[6] == 1 and x[7] == 1:
            error = 1
        elif x[0] == 1 and x[1] == 1 and x[2] == 0 and x[3] == 0 and x[4] == 1 and x[5] == 1 and x[6] == 1 and x[7] == 1:
            error = 2
        elif x[0] == 1 and x[1] == 1 and x[2] == 0 and x[3] == 1 and x[4] == 1 and x[5] == 1 and x[6] == 1 and x[7] == 1:
            error = 2
        elif x[0] == 1 and x[1] == 0 and x[2] == 0 and x[3] == 1 and x[4] == 1 and x[5] == 1 and x[6] == 1 and x[7] == 1:
            error = 3
        elif x[0] == 1 and x[1] == 0 and x[2] == 1 and x[3] == 1 and x[4] == 1 and x[5] == 1 and x[6] == 1 and x[7] == 1:
            error = 3
        elif x[0] == 0 and x[1] == 0 and x[2] == 1 and x[3] == 1 and x[4] == 1 and x[5] == 1 and x[6] == 1 and x[7] == 1:
            error = 4
        elif x[0] == 0 and x[1] == 1 and x[2] == 1 and x[3] == 1 and x[4] == 1 and x[5] == 1 and x[6] == 1 and x[7] == 1:
            error = 4

        elif x[0] == 1 and x[1] == 1 and x[2] == 1 and x[3] == 1 and x[4] == 0 and x[5] == 1 and x[6] == 1 and x[7] == 1:
            error = -1
        elif x[0] == 1 and x[1] == 1 and x[2] == 1 and x[3] == 1 and x[4] == 0 and x[5] == 0 and x[6] == 1 and x[7] == 1:
            error = -2
        elif x[0] == 1 and x[1] == 1 and x[2] == 1 and x[3] == 1 and x[4] == 1 and x[5] == 0 and x[6] == 1 and x[7] == 1:
            error = -2
        elif x[0] == 1 and x[1] == 1 and x[2] == 1 and x[3] == 1 and x[4] == 1 and x[5] == 0 and x[6] == 0 and x[7] == 1:
            error = -3
        elif x[0] == 1 and x[1] == 1 and x[2] == 1 and x[3] == 1 and x[4] == 1 and x[5] == 1 and x[6] == 0 and x[7] == 1:
            error = -3
        elif x[0] == 1 and x[1] == 1 and x[2] == 1 and x[3] == 1 and x[4] == 1 and x[5] == 1 and x[6] == 0 and x[7] == 0:
            error = -4
        elif x[0] == 1 and x[1] == 1 and x[2] == 1 and x[3] == 1 and x[4] == 1 and x[5] == 1 and x[6] == 1 and x[7] == 0:
            error = -4

        elif x[3] == 0 and x[4] == 0:
            error = 0  # centered
        # else: keep previous error (loss-of-line hold)

        self._error = error

        # Update PID
        self.pid.SystemOutput = error
        self.pid.SetStepSignal(0)  # target = 0 (center)
        self.pid.SetInertiaTime(0.01, 0.1)

    def get_state(self) -> Dict[str, Any]:
        """Get current tracking state"""
        with self._lock:
            return {
                "ir_data": list(self._ir_data),
                "error": self._error,
                "pid_output": self.pid.SystemOutput,
                "timestamp": self._timestamp,
                "connected": self._connected,
            }

    def get_correction(self) -> float:
        """
        Get PID-corrected steering value for line following.
        Returns steering offset to be applied to motor differential drive.
        """
        with self._lock:
            return float(self.pid.SystemOutput)

    def register_callback(self, callback: Callable):
        self.callbacks.append(callback)

    def unregister_callback(self, callback: Callable):
        if callback in self.callbacks:
            self.callbacks.remove(callback)


# ============ Standalone Test ============
if __name__ == "__main__":
    track = TrackingDriver()
    if track.connect():
        try:
            while True:
                state = track.get_state()
                print(f"\rIR={state['ir_data']} error={state['error']:3} pid_out={state['pid_output']:7.2f}", end='', flush=True)
                time.sleep(0.1)
        except KeyboardInterrupt:
            pass
        finally:
            track.disconnect()
    else:
        print("Tracking module not available.")
