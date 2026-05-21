"""
Motor Driver Interface — Vofa+ Mode
- Downlink (RK3588S → STM32): FireWater text protocol
- Uplink   (STM32 → RK3588S): JustFloat binary protocol

FireWater commands (ASCII + newline):
    M <motor> <mode> <speed> <angle> <accel> <decel>   # set target
    P <motor> <pid_type> <kp> <ki> <kd>                # set PID
    C <motor> <code>                                    # control
    V <interval_ms>                                     # set output freq
    S                                                   # request status

JustFloat status frame (binary):
    [ch0..ch9 float32] + tail 0x00 0x00 0x80 0x7f
    ch0~4 = motor1 [actual_speed, actual_angle, pwm, target_speed, target_angle]
    ch5~9 = motor2 [actual_speed, actual_angle, pwm, target_speed, target_angle]
"""

import serial
import struct
import threading
import time
import queue
from typing import Callable, Optional, Dict, Any


# JustFloat tail: little-endian float NaN = bytes([0x00,0x00,0x80,0x7f])
JUSTFLOAT_TAIL = struct.pack('<f', float('nan'))
assert JUSTFLOAT_TAIL == b'\x00\x00\x80\x7f'


class JustFloatFrameParser:
    """
    Parse JustFloat frames: N floats (4 bytes each) + tail (4 bytes).
    No header. Tail = 0x00 0x00 0x80 0x7f.
    """

    TAIL = JUSTFLOAT_TAIL
    NUM_CHANNELS = 10
    FRAME_SIZE = NUM_CHANNELS * 4 + 4  # 44 bytes

    def __init__(self):
        self.buffer = bytearray()
        self.callback: Optional[Callable[[Dict], None]] = None

    def feed(self, data: bytes) -> list:
        """Feed raw bytes and return list of parsed status dicts"""
        self.buffer.extend(data)
        frames = []

        while len(self.buffer) >= self.FRAME_SIZE:
            # Search for tail
            tail_idx = self.buffer.find(self.TAIL)
            if tail_idx < 0:
                # Keep last frame_size-1 bytes in case tail is split
                if len(self.buffer) > self.FRAME_SIZE * 2:
                    self.buffer = self.buffer[-(self.FRAME_SIZE - 1):]
                break

            # Data starts at tail_idx - NUM_CHANNELS*4
            data_start = tail_idx - self.NUM_CHANNELS * 4
            if data_start < 0:
                # Partial frame, keep from data_start and break
                self.buffer = self.buffer[data_start:]
                break

            float_data = self.buffer[data_start:tail_idx]
            if len(float_data) == self.NUM_CHANNELS * 4:
                floats = struct.unpack(f'<{self.NUM_CHANNELS}f', float_data)
                parsed = self._parse_status(floats)
                if parsed:
                    frames.append(parsed)
                    if self.callback:
                        try:
                            self.callback(parsed)
                        except Exception as e:
                            print(f"[Motor] Callback error: {e}")

            # Advance past this frame
            self.buffer = self.buffer[tail_idx + len(self.TAIL):]

        return frames

    def _parse_status(self, floats: tuple) -> Optional[Dict[str, Any]]:
        if len(floats) < 10:
            return None
        return {
            'motor1': {
                'speed': floats[0],
                'angle': floats[1],
                'pwm': floats[2],
                'target_speed': floats[3],
                'target_angle': floats[4],
            },
            'motor2': {
                'speed': floats[5],
                'angle': floats[6],
                'pwm': floats[7],
                'target_speed': floats[8],
                'target_angle': floats[9],
            },
            'timestamp': time.time()
        }


class MotorDriver:
    """
    FireWater commands downlink + JustFloat status uplink.
    """

    def __init__(self, port: str = '/dev/ttyACM0', baudrate: int = 115200):
        self.port = port
        self.baudrate = baudrate
        self.serial: Optional[serial.Serial] = None
        self.parser = JustFloatFrameParser()
        self.running = False
        self.read_thread: Optional[threading.Thread] = None
        self.callbacks: list[Callable] = []
        self.latest_state: Optional[Dict] = None
        self.lock = threading.Lock()
        self.command_queue: queue.Queue = queue.Queue()
        self.command_thread: Optional[threading.Thread] = None

    # ── FireWater text helpers ──

    def _send_text(self, text: str):
        """Queue a FireWater text command (ASCII + newline)"""
        if not text.endswith('\n'):
            text += '\n'
        self.command_queue.put(text.encode('ascii'))

    # ── Connection ──

    def connect(self) -> bool:
        try:
            self.serial = serial.Serial(
                port=self.port,
                baudrate=self.baudrate,
                bytesize=serial.EIGHTBITS,
                parity=serial.PARITY_NONE,
                stopbits=serial.STOPBITS_ONE,
                timeout=0.05
            )
            self.running = True
            self.read_thread = threading.Thread(target=self._read_loop, daemon=True)
            self.read_thread.start()
            self.command_thread = threading.Thread(target=self._command_loop, daemon=True)
            self.command_thread.start()
            print(f"[Motor] Connected on {self.port}@{self.baudrate} (FireWater↓ / JustFloat↑)")
            return True
        except Exception as e:
            print(f"[Motor] Failed to connect: {e}")
            return False

    def disconnect(self):
        self.running = False
        if self.read_thread:
            self.read_thread.join(timeout=1.0)
        if self.command_thread:
            self.command_thread.join(timeout=1.0)
        if self.serial and self.serial.is_open:
            self.serial.close()
        print("[Motor] Disconnected")

    def _read_loop(self):
        """Background thread: read and parse JustFloat frames"""
        while self.running:
            try:
                if self.serial and self.serial.is_open:
                    data = self.serial.read(min(256, self.serial.in_waiting or 1))
                    if data:
                        frames = self.parser.feed(data)
                        if frames:
                            with self.lock:
                                self.latest_state = frames[-1]
                            for cb in self.callbacks:
                                try:
                                    cb(frames[-1])
                                except Exception as e:
                                    print(f"[Motor] Callback error: {e}")
            except Exception as e:
                print(f"[Motor] Read error: {e}")
                time.sleep(0.01)

    def _command_loop(self):
        """Background thread: send queued FireWater text commands"""
        while self.running:
            try:
                cmd = self.command_queue.get(timeout=0.1)
                if self.serial and self.serial.is_open:
                    self.serial.write(cmd)
                    self.serial.flush()
                    time.sleep(0.005)
            except queue.Empty:
                continue
            except Exception as e:
                print(f"[Motor] Command error: {e}")

    def get_state(self) -> Optional[Dict]:
        with self.lock:
            return self.latest_state.copy() if self.latest_state else None

    def register_callback(self, callback: Callable):
        self.callbacks.append(callback)
        self.parser.callback = callback

    def unregister_callback(self, callback: Callable):
        if callback in self.callbacks:
            self.callbacks.remove(callback)

    # ── FireWater API ──

    def set_target(self, motor: int, mode: int, speed: float, angle: float,
                   accel: float, decel: float):
        """M <motor> <mode> <speed> <angle> <accel> <decel>"""
        self._send_text(f"M {motor} {mode} {speed} {angle} {accel} {decel}")

    def set_pid(self, motor: int, pid_type: int, kp: float, ki: float, kd: float):
        """P <motor> <pid_type> <kp> <ki> <kd>"""
        self._send_text(f"P {motor} {pid_type} {kp} {ki} {kd}")

    def control(self, motor: int, cmd_code: int):
        """C <motor> <code>   (0=ENABLE,1=DISABLE,2=HOME,3=EMERGENCY,4=CLEAR_FAULT)"""
        self._send_text(f"C {motor} {cmd_code}")

    def set_output_freq(self, interval_ms: int):
        """V <interval_ms>   e.g. V 5 → 200Hz output"""
        self._send_text(f"V {interval_ms}")

    def request_status(self):
        """S"""
        self._send_text("S")

    # ── Convenience methods ──

    def enable(self, motor: int = 255):
        self.control(motor, 0)

    def disable(self, motor: int = 255):
        self.control(motor, 1)

    def emergency_stop(self, motor: int = 255):
        self.control(motor, 3)

    def clear_fault(self, motor: int = 255):
        self.control(motor, 4)

    def home(self, motor: int = 255):
        self.control(motor, 2)

    def set_speed(self, motor: int, speed: float, accel: float = 10.0):
        self.set_target(motor, 0, speed, 0.0, accel, accel)

    def set_position(self, motor: int, angle: float, speed: float = 2.0, accel: float = 5.0):
        self.set_target(motor, 1, speed, angle, accel, accel)

    def set_car_speed(self, linear: float, angular: float):
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
