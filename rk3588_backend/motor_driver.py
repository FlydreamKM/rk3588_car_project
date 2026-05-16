"""
Motor Driver Interface for Dual Closed-LOOP Driver (STM32F103)
VOFA-only mode: JustFloat frame parsing + FireWater command sending
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


class JustFloatParser:
    """
    Parse JustFloat frames from STM32 motor driver.
    
    Frame format:
    - 10 channels of float32 (IEEE 754, little-endian)
    - Frame tail: 0x00 0x00 0x80 0x7f
    
    Channel mapping:
    ch0: motor1 actual speed (rad/s)
    ch1: motor1 actual angle (rad)
    ch2: motor1 PWM
    ch3: motor1 trajectory target speed (rad/s)
    ch4: motor1 trajectory target angle (rad)
    ch5: motor2 actual speed (rad/s)
    ch6: motor2 actual angle (rad)
    ch7: motor2 PWM
    ch8: motor2 trajectory target speed (rad/s)
    ch9: motor2 trajectory target angle (rad)
    """
    
    FRAME_TAIL = b'\x00\x00\x80\x7f'
    NUM_CHANNELS = 10
    FRAME_SIZE = NUM_CHANNELS * 4 + 4  # 10 floats + 4 byte tail
    
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
            # Find frame tail
            tail_idx = self.buffer.find(self.FRAME_TAIL)
            if tail_idx < 0:
                # Keep last FRAME_SIZE bytes for next call
                if len(self.buffer) > self.FRAME_SIZE * 2:
                    self.buffer = self.buffer[-self.FRAME_SIZE * 2:]
                break
                
            frame_start = tail_idx - self.NUM_CHANNELS * 4
            if frame_start < 0:
                # Incomplete frame before tail, remove tail and continue
                self.buffer = self.buffer[tail_idx + 4:]
                continue
                
            frame_data = self.buffer[frame_start:tail_idx + 4]
            if len(frame_data) >= self.FRAME_SIZE:
                parsed = self._parse_frame(frame_data)
                if parsed:
                    frames.append(parsed)
                    
            self.buffer = self.buffer[tail_idx + 4:]
            
        return frames
    
    def _parse_frame(self, data: bytes) -> Optional[Dict[str, Any]]:
        """Parse a single JustFloat frame"""
        try:
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
        except Exception as e:
            print(f"Parse error: {e}")
            return None


class MotorDriver:
    """
    High-level motor driver interface.
    Connects to STM32 via serial port, parses JustFloat frames,
    and sends FireWater text commands.
    """
    
    def __init__(self, port: str = '/dev/ttyUSB0', baudrate: int = 115200):
        self.port = port
        self.baudrate = baudrate
        self.serial = None
        self.parser = JustFloatParser()
        self.running = False
        self.read_thread = None
        self.callbacks: list[Callable] = []
        self.latest_state: Optional[Dict] = None
        self.lock = threading.Lock()
        self.command_queue = queue.Queue()
        self.command_thread = None
        
    def connect(self) -> bool:
        """Connect to the motor driver"""
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
            print(f"Connected to motor driver on {self.port}@{self.baudrate}")
            return True
        except Exception as e:
            print(f"Failed to connect: {e}")
            return False
    
    def disconnect(self):
        """Disconnect from the motor driver"""
        self.running = False
        if self.read_thread:
            self.read_thread.join(timeout=1.0)
        if self.command_thread:
            self.command_thread.join(timeout=1.0)
        if self.serial and self.serial.is_open:
            self.serial.close()
        print("Disconnected from motor driver")
    
    def _read_loop(self):
        """Background thread for reading JustFloat frames"""
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
                print(f"Read error: {e}")
                time.sleep(0.01)
    
    def _command_loop(self):
        """Background thread for sending commands"""
        while self.running:
            try:
                cmd = self.command_queue.get(timeout=0.1)
                if self.serial and self.serial.is_open:
                    self.serial.write(cmd.encode('ascii'))
                    self.serial.flush()
                    time.sleep(0.01)  # Small delay between commands
            except queue.Empty:
                continue
            except Exception as e:
                print(f"Command error: {e}")
    
    def get_state(self) -> Optional[Dict]:
        """Get latest motor state"""
        with self.lock:
            return self.latest_state.copy() if self.latest_state else None
    
    def register_callback(self, callback: Callable):
        """Register a callback for state updates"""
        self.callbacks.append(callback)
    
    def unregister_callback(self, callback: Callable):
        """Unregister a callback"""
        if callback in self.callbacks:
            self.callbacks.remove(callback)
    
    # FireWater Command Methods
    
    def send_command(self, cmd: str):
        """Send a raw FireWater command (with newline)"""
        if not cmd.endswith('\n'):
            cmd += '\n'
        self.command_queue.put(cmd)
    
    def set_target(self, motor: int, mode: int, speed: float, angle: float, 
                   accel: float, decel: float):
        """
        M command: Set target parameters
        motor: 0 or 1
        mode: 0=speed, 1=position
        speed: rad/s
        angle: rad (only for position mode)
        accel/decel: rad/s^2
        """
        cmd = f"M {motor} {mode} {speed} {angle} {accel} {decel}"
        self.send_command(cmd)
    
    def set_pid(self, motor: int, pid_type: int, kp: float, ki: float, kd: float):
        """
        P command: Set PID parameters
        motor: 0, 1, or 'B' for both
        pid_type: 0=speed loop, 1=position loop
        """
        if motor == 'B':
            cmd = f"PB {pid_type} {kp} {ki} {kd}"
        else:
            cmd = f"P {motor} {pid_type} {kp} {ki} {kd}"
        self.send_command(cmd)
    
    def control(self, motor: int, cmd_code: int):
        """
        C command: Control commands
        motor: 0, 1, or 255 for both
        cmd_code: 0=ENABLE, 1=DISABLE, 2=HOME, 3=EMERGENCY, 4=CLEAR_FAULT
        """
        cmd = f"C {motor} {cmd_code}"
        self.send_command(cmd)
    
    def set_vofa_freq(self, interval_ms: int):
        """
        V command: Set JustFloat output frequency
        interval_ms: 0=off, 5=200Hz, 10=100Hz
        """
        cmd = f"V {interval_ms}"
        self.send_command(cmd)
    
    # Convenience methods
    
    def enable(self, motor: int = 255):
        """Enable motor(s)"""
        self.control(motor, 0)
    
    def disable(self, motor: int = 255):
        """Disable motor(s)"""
        self.control(motor, 1)
    
    def emergency_stop(self, motor: int = 255):
        """Emergency stop"""
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
        """
        Set differential drive speed.
        linear: linear speed (cm/s)
        angular: angular speed (rad/s)
        """
        # Convert to wheel speeds (assuming wheel radius r, wheel separation d)
        # left_speed = linear - angular * d/2
        # right_speed = linear + angular * d/2
        # For now, simple mapping
        left_speed = linear - angular * 5.0  # Adjust factor as needed
        right_speed = linear + angular * 5.0
        self.set_speed(0, left_speed)
        self.set_speed(1, right_speed)


# Test code
if __name__ == '__main__':
    import sys
    
    port = sys.argv[1] if len(sys.argv) > 1 else '/dev/ttyUSB0'
    
    driver = MotorDriver(port)
    
    def on_state(state):
        print(f"\rMotor1: speed={state['motor1']['speed']:6.2f} rad/s, "
              f"angle={state['motor1']['angle']:6.2f} rad, "
              f"pwm={state['motor1']['pwm']:7.1f} | "
              f"Motor2: speed={state['motor2']['speed']:6.2f} rad/s, "
              f"angle={state['motor2']['angle']:6.2f} rad", end='', flush=True)
    
    driver.register_callback(on_state)
    
    if driver.connect():
        print("\nConnected! Press Ctrl+C to exit.")
        print("Commands: e=enable, d=disable, s=stop, h=home, q=quit")
        print("          f <speed>=forward, b <speed>=backward")
        
        try:
            while True:
                cmd = input("\n> ").strip().split()
                if not cmd:
                    continue
                    
                if cmd[0] == 'e':
                    driver.enable()
                elif cmd[0] == 'd':
                    driver.disable()
                elif cmd[0] == 's':
                    driver.emergency_stop()
                elif cmd[0] == 'h':
                    driver.home()
                elif cmd[0] == 'q':
                    break
                elif cmd[0] == 'f':
                    speed = float(cmd[1]) if len(cmd) > 1 else 5.0
                    driver.set_speed(0, speed)
                    driver.set_speed(1, speed)
                elif cmd[0] == 'b':
                    speed = float(cmd[1]) if len(cmd) > 1 else 5.0
                    driver.set_speed(0, -speed)
                    driver.set_speed(1, -speed)
                elif cmd[0] == 'l':
                    driver.set_speed(0, -3.0)
                    driver.set_speed(1, 3.0)
                elif cmd[0] == 'r':
                    driver.set_speed(0, 3.0)
                    driver.set_speed(1, -3.0)
                    
        except KeyboardInterrupt:
            pass
        finally:
            driver.emergency_stop()
            driver.disconnect()
    else:
        print("Failed to connect!")
