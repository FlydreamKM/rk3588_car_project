"""
Motor Driver Interface for Dual Closed-LOOP Driver (STM32F103)
Binary protocol mode: [0xAA][0x55][LEN][CMD][DATA...][CHK]
"""

import serial
import struct
import threading
import time
import queue
from typing import Callable, Optional, Dict, Any


class MotorState:
    """Motor state container"""
    def __init__(self):
        self.actual_speed = 0.0      # rad/s
        self.actual_angle = 0.0      # rad
        self.pwm = 0.0               # PWM value
        self.target_speed = 0.0      # rad/s
        self.target_angle = 0.0      # rad
        self.timestamp = 0.0


class BinaryFrameParser:
    """
    Parse binary frames from STM32 motor driver.

    Frame format:
    [0xAA][0x55][LEN][CMD][DATA...][CHK]

    Checksum: sum of CMD + all DATA bytes, low 8 bits
    """

    HEADER = bytes([0xAA, 0x55])

    # Response codes (uplink)
    RSP_STATUS = 0x81

    def __init__(self):
        self.buffer = bytearray()
        self.motor1 = MotorState()
        self.motor2 = MotorState()
        self.callback: Optional[Callable] = None

    def feed(self, data: bytes) -> list:
        """Feed raw bytes and return list of parsed frames"""
        self.buffer.extend(data)
        frames = []

        while True:
            header_idx = self.buffer.find(self.HEADER)
            if header_idx < 0:
                if len(self.buffer) > 256:
                    self.buffer = self.buffer[-256:]
                break

            # Need header(2) + LEN(1) + CMD(1) + CHK(1) = 5 bytes minimum
            if len(self.buffer) - header_idx < 5:
                break

            len_byte = self.buffer[header_idx + 2]
            cmd = self.buffer[header_idx + 3]

            # Total frame: 2(header) + 1(len) + 1(cmd) + len(data) + 1(chk)
            frame_size = 5 + len_byte
            if len(self.buffer) - header_idx < frame_size:
                break

            frame = self.buffer[header_idx:header_idx + frame_size]

            # Verify checksum: sum of CMD + DATA
            payload = frame[3:-1]  # CMD + DATA
            expected_chk = sum(payload) & 0xFF
            actual_chk = frame[-1]

            if expected_chk == actual_chk:
                parsed = self._parse_frame(cmd, frame[4:-1])
                if parsed:
                    frames.append(parsed)

            self.buffer = self.buffer[header_idx + frame_size:]

        return frames

    def _parse_frame(self, cmd: int, data: bytes) -> Optional[Dict[str, Any]]:
        """Parse a single frame based on command code"""
        try:
            if cmd == self.RSP_STATUS:
                return self._parse_status(data)
            return None
        except Exception as e:
            print(f"Parse error for cmd 0x{cmd:02X}: {e}")
            return None

    def _parse_status(self, data: bytes) -> Optional[Dict[str, Any]]:
        """Parse RSP_STATUS (0x81) frame — 10 floats = 40 bytes"""
        if len(data) < 40:
            return None

        floats = struct.unpack('<10f', data[:40])

        self.motor1.actual_speed = floats[0]
        self.motor1.actual_angle = floats[1]
        self.motor1.pwm = floats[2]
        self.motor1.target_speed = floats[3]
        self.motor1.target_angle = floats[4]
        self.motor1.timestamp = time.time()

        self.motor2.actual_speed = floats[5]
        self.motor2.actual_angle = floats[6]
        self.motor2.pwm = floats[7]
        self.motor2.target_speed = floats[8]
        self.motor2.target_angle = floats[9]
        self.motor2.timestamp = time.time()

        result = {
            'motor1': {
                'speed': floats[0],
                'angle': floats[1],
                'pwm': floats[2],
                'target_speed': floats[3],
                'target_angle': floats[4]
            },
            'motor2': {
                'speed': floats[5],
                'angle': floats[6],
                'pwm': floats[7],
                'target_speed': floats[8],
                'target_angle': floats[9]
            },
            'timestamp': time.time()
        }

        if self.callback:
            self.callback(result)

        return result


class MotorDriver:
    """
    High-level motor driver interface using binary protocol.
    Frame: [0xAA][0x55][LEN][CMD][DATA...][CHK]
    """

    # Command codes (downlink)
    CMD_SET_TARGET = 0x01
    CMD_SET_PID = 0x02
    CMD_CONTROL = 0x03
    CMD_REQ_STATUS = 0x04

    def __init__(self, port: str = '/dev/ttyACM0', baudrate: int = 115200):
        self.port = port
        self.baudrate = baudrate
        self.serial: Optional[serial.Serial] = None
        self.parser = BinaryFrameParser()
        self.running = False
        self.read_thread: Optional[threading.Thread] = None
        self.callbacks: list[Callable] = []
        self.latest_state: Optional[Dict] = None
        self.lock = threading.Lock()
        self.command_queue: queue.Queue = queue.Queue()
        self.command_thread: Optional[threading.Thread] = None

    def _build_frame(self, cmd: int, data: bytes) -> bytes:
        """Build binary frame: [0xAA][0x55][LEN][CMD][DATA...][CHK]"""
        payload = bytes([cmd]) + data
        chk = sum(payload) & 0xFF
        return bytes([0xAA, 0x55, len(data), cmd]) + data + bytes([chk])

    def connect(self) -> bool:
        """Connect to motor driver via serial port"""
        try:
            self.serial = serial.Serial(
                port=self.port,
                baudrate=self.baudrate,
                bytesize=serial.EIGHTBITS,
                parity=serial.PARITY_NONE,
                stopbits=serial.STOPBITS_ONE,
                timeout=0.1
            )
            self.running = True
            self.read_thread = threading.Thread(target=self._read_loop, daemon=True)
            self.read_thread.start()
            self.command_thread = threading.Thread(target=self._command_loop, daemon=True)
            self.command_thread.start()
            print(f"[Motor] Connected on {self.port}@{self.baudrate}")
            return True
        except Exception as e:
            print(f"[Motor] Failed to connect: {e}")
            return False

    def disconnect(self):
        """Disconnect from motor driver"""
        self.running = False
        if self.read_thread:
            self.read_thread.join(timeout=1.0)
        if self.command_thread:
            self.command_thread.join(timeout=1.0)
        if self.serial and self.serial.is_open:
            self.serial.close()
        print("[Motor] Disconnected")

    def _read_loop(self):
        """Background thread: read and parse binary frames"""
        while self.running:
            try:
                if self.serial and self.serial.is_open:
                    data = self.serial.read(min(1024, self.serial.in_waiting or 1))
                    if data:
                        frames = self.parser.feed(data)
                        if frames:
                            with self.lock:
                                self.latest_state = frames[-1]
                            for cb in self.callbacks:
                                try:
                                    cb(frames[-1])
                                except Exception as e:
                                    print(f"Callback error: {e}")
            except Exception as e:
                print(f"[Motor] Read error: {e}")
                time.sleep(0.01)

    def _command_loop(self):
        """Background thread: send queued commands"""
        while self.running:
            try:
                cmd = self.command_queue.get(timeout=0.1)
                if self.serial and self.serial.is_open:
                    self.serial.write(cmd)
                    self.serial.flush()
                    time.sleep(0.01)
            except queue.Empty:
                continue
            except Exception as e:
                print(f"[Motor] Command error: {e}")

    def get_state(self) -> Optional[Dict]:
        """Get latest parsed motor state"""
        with self.lock:
            return self.latest_state.copy() if self.latest_state else None

    def register_callback(self, callback: Callable):
        self.callbacks.append(callback)

    def unregister_callback(self, callback: Callable):
        if callback in self.callbacks:
            self.callbacks.remove(callback)

    def _send_raw(self, cmd: int, data: bytes):
        """Queue a raw binary frame for transmission"""
        frame = self._build_frame(cmd, data)
        self.command_queue.put(frame)

    # === Binary Protocol API ===

    def set_target(self, motor: int, mode: int, speed: float, angle: float,
                   accel: float, decel: float):
        """
        CMD_SET_TARGET (0x01): Set motor target parameters
        motor: 0 or 1
        mode: 0=speed mode, 1=position mode
        speed: rad/s, angle: rad, accel/decel: rad/s^2
        Data: motor(1) + mode(1) + speed(4) + angle(4) + accel(4) + decel(4) = 14 bytes
        """
        data = struct.pack('<B B f f f f', motor, mode, speed, angle, accel, decel)
        self._send_raw(self.CMD_SET_TARGET, data)

    def set_pid(self, motor: int, pid_type: int, kp: float, ki: float, kd: float):
        """
        CMD_SET_PID (0x02): Set PID for a single motor
        motor: 0 or 1 (DO NOT use 'B' — call twice for both motors)
        pid_type: 0=speed loop, 1=position loop
        Data: motor(1) + pid_type(1) + kp(4) + ki(4) + kd(4) = 14 bytes
        """
        data = struct.pack('<B B f f f', motor, pid_type, kp, ki, kd)
        self._send_raw(self.CMD_SET_PID, data)

    def control(self, motor: int, cmd_code: int):
        """
        CMD_CONTROL (0x03): Control commands
        motor: 0, 1, or 255 for both
        cmd_code: 0=ENABLE, 1=DISABLE, 2=HOME, 3=EMERGENCY, 4=CLEAR_FAULT
        Data: motor(1) + cmd_code(1) = 2 bytes
        """
        data = struct.pack('<B B', motor, cmd_code)
        self._send_raw(self.CMD_CONTROL, data)

    def request_status(self):
        """CMD_REQ_STATUS (0x04): Request status frame — no data"""
        self._send_raw(self.CMD_REQ_STATUS, b'')

    # === Convenience methods ===

    def enable(self, motor: int = 255):
        """Enable motor(s)"""
        self.control(motor, 0)

    def disable(self, motor: int = 255):
        """Disable motor(s)"""
        self.control(motor, 1)

    def emergency_stop(self, motor: int = 255):
        """Emergency stop (hard stop)"""
        self.control(motor, 3)

    def clear_fault(self, motor: int = 255):
        """Clear fault and return to IDLE"""
        self.control(motor, 4)

    def home(self, motor: int = 255):
        """Home (reset encoder and trajectory)"""
        self.control(motor, 2)

    def set_speed(self, motor: int, speed: float, accel: float = 10.0):
        """Set speed mode target"""
        self.set_target(motor, 0, speed, 0.0, accel, accel)

    def set_position(self, motor: int, angle: float, speed: float = 2.0, accel: float = 5.0):
        """Set position mode target"""
        self.set_target(motor, 1, speed, angle, accel, accel)

    def set_car_speed(self, linear: float, angular: float):
        """Set differential drive speed (left/right wheel speeds)"""
        left_speed = linear - angular * 5.0
        right_speed = linear + angular * 5.0
        self.set_speed(0, left_speed)
        self.set_speed(1, right_speed)


# ── Test / CLI entry ──
if __name__ == '__main__':
    import sys

    port = sys.argv[1] if len(sys.argv) > 1 else '/dev/ttyACM0'
    driver = MotorDriver(port)

    def on_state(state):
        print(f"\rM1: s={state['motor1']['speed']:6.2f} a={state['motor1']['angle']:6.2f} "
              f"pwm={state['motor1']['pwm']:6.1f} | "
              f"M2: s={state['motor2']['speed']:6.2f} a={state['motor2']['angle']:6.2f}",
              end='', flush=True)

    driver.register_callback(on_state)

    if driver.connect():
        print("\n[CLI] e=enable  d=disable  s=emergency_stop  h=home  q=quit")
        print("      f <speed>=forward  b <speed>=backward")
        try:
            while True:
                tokens = input("\n> ").strip().split()
                if not tokens:
                    continue
                c = tokens[0]
                if c == 'e':
                    driver.enable()
                elif c == 'd':
                    driver.disable()
                elif c == 's':
                    driver.emergency_stop()
                elif c == 'h':
                    driver.home()
                elif c == 'q':
                    break
                elif c == 'f':
                    sp = float(tokens[1]) if len(tokens) > 1 else 5.0
                    driver.set_speed(0, sp)
                    driver.set_speed(1, sp)
                elif c == 'b':
                    sp = float(tokens[1]) if len(tokens) > 1 else 5.0
                    driver.set_speed(0, -sp)
                    driver.set_speed(1, -sp)
                elif c == 'l':
                    driver.set_speed(0, -3.0)
                    driver.set_speed(1, 3.0)
                elif c == 'r':
                    driver.set_speed(0, 3.0)
                    driver.set_speed(1, -3.0)
        except KeyboardInterrupt:
            pass
        finally:
            driver.emergency_stop()
            driver.disconnect()
    else:
        print("Failed to connect!")
