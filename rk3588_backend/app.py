"""
RK3588S Smart Car Flask Backend
Integrates motor control, servo, IMU, tracking, video streaming,
AI features, display, and SSH remote control.
"""

from flask import Flask, Response, jsonify, request
from flask_cors import CORS
import cv2
import json
import threading
import time
import random
import os
import subprocess
import numpy as np
from motor_driver import MotorDriver
from servo_driver import ServoDriver
from imu_driver import YbImuDriver
from tracking_driver import TrackingDriver
from display import CuteFaceDisplay

app = Flask(__name__)
CORS(app)  # Allow cross-origin for Flutter

# ===================== Motor Driver =====================
MOTOR_PORT = os.environ.get('MOTOR_PORT', '/dev/ttyUSB0')
motor_driver = MotorDriver(port=MOTOR_PORT)
motor_connected = False

# ===================== Servo Driver =====================
# OrangePi 5: try pwmchip4 first, fallback to 0
SERVO_PWM_CHIP = int(os.environ.get('SERVO_PWM_CHIP', '4'))
servo_driver = ServoDriver(chip=SERVO_PWM_CHIP)
servo_connected = servo_driver.init()

# ===================== IMU Driver =====================
IMU_PORT = os.environ.get('IMU_PORT', '/dev/ttyUSB1')
imu_driver = YbImuDriver(port=IMU_PORT)
imu_connected = imu_driver.connect()

# ===================== Tracking Driver =====================
TRACKING_PORT = os.environ.get('TRACKING_PORT', '/dev/ttyUSB2')
tracking_driver = TrackingDriver(port=TRACKING_PORT)
tracking_connected = tracking_driver.connect()

# ===================== Display =====================
face_display = CuteFaceDisplay()
display_connected = face_display.init()

# Try to connect to motor driver
try:
    motor_connected = motor_driver.connect()
    if motor_connected:
        # Enable both motors on startup
        motor_driver.enable(255)
except Exception as e:
    print(f"Motor driver not connected: {e}")
    print("Running in simulation mode")

# ===================== Global Robot State =====================
robot_state = {
    "speed": 0,           # Current speed cm/s
    "heading": 0,         # Heading angle
    "battery": 87,        # Battery percentage
    "mode": "manual",     # manual/auto/follow/gesture/park/line/track
    "status": "idle",     # idle/running/obstacle/charging
    "position": {"x": 0, "y": 0},
    "imu": {"pitch": 0, "roll": 0, "yaw": 0, "ax": 0, "ay": 0, "az": 0, "gx": 0, "gy": 0, "gz": 0},
    "obstacle_distance": 999,
    "target_locked": False,
    "emotion": "neutral",
    "motor1": {"speed": 0, "angle": 0, "pwm": 0},
    "motor2": {"speed": 0, "angle": 0, "pwm": 0},
    "servo": {"angle_percent": 0, "enabled": servo_connected},
    "tracking": {"ir_data": [0]*8, "error": 0, "pid_output": 0, "connected": tracking_connected},
    "ssh": {"status": "disconnected", "host": "", "uptime": 0},
}

# Update robot state from motor driver
def on_motor_state(state):
    global robot_state
    robot_state["motor1"] = state["motor1"]
    robot_state["motor2"] = state["motor2"]
    # Calculate combined speed (average of both motors)
    avg_speed = (state["motor1"]["speed"] + state["motor2"]["speed"]) / 2
    robot_state["speed"] = avg_speed * 10  # Rough conversion to cm/s
    robot_state["heading"] = state["motor1"]["angle"]
    robot_state["status"] = "running" if abs(avg_speed) > 0.1 else "idle"

if motor_connected:
    motor_driver.register_callback(on_motor_state)

# Update robot state from IMU
def on_imu_state(state):
    global robot_state
    euler = state.get("euler", {})
    acc = state.get("accelerometer", {})
    gyro = state.get("gyroscope", {})
    robot_state["imu"] = {
        "pitch": euler.get("pitch", 0),
        "roll": euler.get("roll", 0),
        "yaw": euler.get("yaw", 0),
        "ax": acc.get("x", 0),
        "ay": acc.get("y", 0),
        "az": acc.get("z", 0),
        "gx": gyro.get("x", 0),
        "gy": gyro.get("y", 0),
        "gz": gyro.get("z", 0),
    }

if imu_connected:
    imu_driver.register_callback(on_imu_state)

# Update robot state from tracking module
def on_tracking_state(state):
    global robot_state
    robot_state["tracking"] = {
        "ir_data": state.get("ir_data", [0]*8),
        "error": state.get("error", 0),
        "pid_output": state.get("pid_output", 0),
        "connected": state.get("connected", False),
    }

if tracking_connected:
    tracking_driver.register_callback(on_tracking_state)

# ===================== Camera =====================
camera = cv2.VideoCapture(0)
camera.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
camera.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)

def generate_frames():
    """Generate MJPEG frames"""
    while True:
        success, frame = camera.read()
        if not success:
            # Generate a placeholder frame if camera fails
            frame = create_placeholder_frame()
        else:
            # Add overlays
            frame = draw_overlays(frame)
            
        ret, buffer = cv2.imencode('.jpg', frame, [cv2.IMWRITE_JPEG_QUALITY, 70])
        if ret:
            frame_bytes = buffer.tobytes()
            yield (b'--frame\r\n'
                   b'Content-Type: image/jpeg\r\n\r\n' + frame_bytes + b'\r\n')
        time.sleep(0.033)  # ~30fps

def create_placeholder_frame():
    """Create a placeholder frame when camera is unavailable"""
    frame = cv2.imread('/tmp/placeholder.jpg') if os.path.exists('/tmp/placeholder.jpg') else None
    if frame is None:
        frame = cv2.imread('/usr/share/pixmaps/ubuntu-logo-dark.png') if os.path.exists('/usr/share/pixmaps/ubuntu-logo-dark.png') else None
    if frame is None:
        frame = cv2.imread('/usr/share/pixmaps/fedora-logo-small.png') if os.path.exists('/usr/share/pixmaps/fedora-logo-small.png') else None
    if frame is None:
        # Create a blank frame with text
        frame = cv2.zeros((480, 640, 3), dtype=np.uint8)
        cv2.putText(frame, "Camera Offline", (180, 240), cv2.FONT_HERSHEY_SIMPLEX, 1.5, (255, 255, 255), 2)
    return cv2.resize(frame, (640, 480)) if frame is not None else cv2.zeros((480, 640, 3), dtype=np.uint8)

def draw_overlays(frame):
    """Draw HUD overlays on video frame"""
    h, w = frame.shape[:2]
    
    # Battery indicator
    battery = robot_state["battery"]
    color = (0, 255, 0) if battery > 30 else (0, 0, 255)
    cv2.rectangle(frame, (w-120, 20), (w-20, 50), (255, 255, 255), 2)
    fill_width = int((battery / 100) * 90)
    cv2.rectangle(frame, (w-118, 22), (w-118 + fill_width, 48), color, -1)
    cv2.putText(frame, f"{battery:.0f}%", (w-115, 43), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 255, 255), 1)
    
    # Speed
    speed = robot_state["speed"]
    cv2.putText(frame, f"{speed:.1f} cm/s", (20, 40), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (0, 255, 255), 2)
    
    # Mode
    mode = robot_state["mode"]
    cv2.putText(frame, f"Mode: {mode.upper()}", (20, 80), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 255, 255), 2)
    
    # IMU yaw
    yaw = robot_state["imu"]["yaw"]
    cv2.putText(frame, f"Yaw: {yaw:.1f} deg", (20, 110), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 255, 255), 1)
    
    # Tracking status
    track = robot_state["tracking"]
    if track["connected"]:
        ir_str = "".join(str(v) for v in track["ir_data"])
        cv2.putText(frame, f"Line: {ir_str} e={track['error']}", (20, 140), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 255, 0), 1)
    
    # Crosshair
    cx, cy = w // 2, h // 2
    cv2.line(frame, (cx - 20, cy), (cx + 20, cy), (0, 255, 0), 1)
    cv2.line(frame, (cx, cy - 20), (cx, cy + 20), (0, 255, 0), 1)
    
    return frame

# ===================== API Endpoints =====================

@app.route('/video_feed')
def video_feed():
    """MJPEG video stream endpoint"""
    return Response(generate_frames(),
                    mimetype='multipart/x-mixed-replace; boundary=frame')

@app.route('/api/status', methods=['GET'])
def get_status():
    """Get current robot status"""
    if motor_connected:
        state = motor_driver.get_state()
        if state:
            robot_state["motor1"] = state["motor1"]
            robot_state["motor2"] = state["motor2"]
    return jsonify(robot_state)

# ---- Servo Control ----
@app.route('/api/servo', methods=['POST'])
def set_servo():
    """Set servo steering angle: angle_percent -100 to +100"""
    if not servo_connected:
        return jsonify({"success": False, "error": "Servo not connected"}), 503
    data = request.json or {}
    angle = data.get('angle', 0)
    try:
        servo_driver.set_angle(float(angle))
        robot_state["servo"]["angle_percent"] = float(angle)
        return jsonify({"success": True, "angle": float(angle)})
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500

@app.route('/api/servo/center', methods=['POST'])
def servo_center():
    """Center the servo"""
    if not servo_connected:
        return jsonify({"success": False, "error": "Servo not connected"}), 503
    servo_driver.center()
    robot_state["servo"]["angle_percent"] = 0
    return jsonify({"success": True, "angle": 0})

# ---- IMU Data ----
@app.route('/api/imu', methods=['GET'])
def get_imu():
    """Get IMU sensor data"""
    if imu_connected:
        state = imu_driver.get_state()
        return jsonify({"success": True, "data": state})
    return jsonify({"success": False, "error": "IMU not connected", "data": robot_state["imu"]}), 503

# ---- Tracking Data ----
@app.route('/api/tracking', methods=['GET'])
def get_tracking():
    """Get 8-channel line tracking data"""
    if tracking_connected:
        state = tracking_driver.get_state()
        return jsonify({"success": True, "data": state})
    return jsonify({"success": False, "error": "Tracking module not connected", "data": robot_state["tracking"]}), 503

@app.route('/api/tracking/start', methods=['POST'])
def start_tracking_mode():
    """Enable line-tracking autonomous mode"""
    global robot_state
    robot_state["mode"] = "track"
    if display_connected:
        face_display.set_emotion("cool")
    return jsonify({"success": True, "mode": "track"})

@app.route('/api/tracking/stop', methods=['POST'])
def stop_tracking_mode():
    """Disable line-tracking mode, return to manual"""
    global robot_state
    robot_state["mode"] = "manual"
    if motor_connected:
        motor_driver.emergency_stop()
    if display_connected:
        face_display.set_emotion("neutral")
    return jsonify({"success": True, "mode": "manual"})

# ---- Display / Emotion ----
@app.route('/api/display/emotion', methods=['POST'])
def set_display_emotion():
    """Set display emotion face"""
    if not display_connected:
        return jsonify({"success": False, "error": "Display not connected"}), 503
    emotion = request.json.get('emotion', 'neutral')
    face_display.set_emotion(emotion)
    robot_state["emotion"] = emotion
    return jsonify({"success": True, "emotion": emotion})

@app.route('/api/display/status', methods=['GET'])
def get_display_status():
    """Get display status"""
    if display_connected:
        return jsonify({"success": True, "data": face_display.get_state()})
    return jsonify({"success": False, "error": "Display not connected"}), 503

# ---- SSH Remote Control ----
ssh_process = None
ssh_start_time = 0

@app.route('/api/ssh/start', methods=['POST'])
def ssh_start():
    """Start backend server via local script (one-click start)"""
    global ssh_process, ssh_start_time
    try:
        # Run start.sh in background
        backend_dir = os.path.dirname(os.path.abspath(__file__))
        start_script = os.path.join(backend_dir, "start.sh")
        if os.path.exists(start_script):
            ssh_process = subprocess.Popen(
                ["bash", start_script],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                cwd=backend_dir
            )
            ssh_start_time = time.time()
            robot_state["ssh"]["status"] = "running"
            robot_state["ssh"]["host"] = "localhost"
            robot_state["ssh"]["uptime"] = 0
            return jsonify({"success": True, "status": "running", "pid": ssh_process.pid})
        else:
            return jsonify({"success": False, "error": "start.sh not found"}), 500
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500

@app.route('/api/ssh/status', methods=['GET'])
def ssh_status():
    """Get SSH / server process status"""
    global ssh_process
    if ssh_process is not None:
        ret = ssh_process.poll()
        running = ret is None
        uptime = int(time.time() - ssh_start_time) if ssh_start_time else 0
        robot_state["ssh"]["status"] = "running" if running else "stopped"
        robot_state["ssh"]["uptime"] = uptime
        return jsonify({"success": True, "running": running, "uptime": uptime, "returncode": ret})
    return jsonify({"success": True, "running": False, "uptime": 0})

@app.route('/api/ssh/stop', methods=['POST'])
def ssh_stop():
    """Stop backend server process"""
    global ssh_process
    if ssh_process is not None:
        try:
            ssh_process.terminate()
            ssh_process.wait(timeout=5)
        except Exception:
            ssh_process.kill()
        ssh_process = None
        robot_state["ssh"]["status"] = "stopped"
        return jsonify({"success": True, "status": "stopped"})
    return jsonify({"success": False, "error": "No server process running"}), 400

# ---- Legacy Control Endpoints ----
@app.route('/api/control', methods=['POST'])
def control():
    """Control commands: forward/backward/left/right/stop"""
    global robot_state
    cmd = request.json or {}
    action = cmd.get('action', 'stop')
    speed = cmd.get('speed', 50)
    
    if motor_connected:
        try:
            if action == 'forward':
                motor_driver.set_car_speed(speed, 0)
            elif action == 'backward':
                motor_driver.set_car_speed(-speed, 0)
            elif action == 'left':
                motor_driver.set_car_speed(0, -speed * 0.1)
                if servo_connected:
                    servo_driver.set_angle(-50)
            elif action == 'right':
                motor_driver.set_car_speed(0, speed * 0.1)
                if servo_connected:
                    servo_driver.set_angle(50)
            elif action == 'stop':
                motor_driver.emergency_stop()
                motor_driver.enable(255)  # Re-enable after stop
                if servo_connected:
                    servo_driver.center()
            
            robot_state['status'] = 'running' if action != 'stop' else 'idle'
            return jsonify({"success": True, "action": action, "speed": speed})
        except Exception as e:
            return jsonify({"success": False, "error": str(e)}), 500
    else:
        robot_state['speed'] = speed if action != 'stop' else 0
        robot_state['status'] = 'running' if action != 'stop' else 'idle'
        return jsonify({"success": True, "action": action, "speed": speed, "mode": "simulation"})

@app.route('/api/mode', methods=['POST'])
def set_mode():
    """Switch mode: manual/auto/follow/gesture/park/voice/track"""
    global robot_state
    mode = request.json.get('mode', 'manual')
    robot_state['mode'] = mode
    if display_connected:
        emotion_map = {
            "manual": "neutral",
            "auto": "cool",
            "follow": "love",
            "gesture": "surprised",
            "park": "sleepy",
            "voice": "happy",
            "track": "cool",
        }
        face_display.set_emotion(emotion_map.get(mode, "neutral"))
    return jsonify({"success": True, "mode": mode})

@app.route('/api/motor/target', methods=['POST'])
def set_motor_target():
    """Direct motor target control"""
    if not motor_connected:
        return jsonify({"success": False, "error": "Motor not connected"}), 503
    
    data = request.json or {}
    motor = data.get('motor', 0)
    mode = data.get('mode', 0)
    speed = data.get('speed', 0.0)
    angle = data.get('angle', 0.0)
    accel = data.get('accel', 10.0)
    decel = data.get('decel', 10.0)
    
    try:
        motor_driver.set_target(motor, mode, speed, angle, accel, decel)
        return jsonify({"success": True, "motor": motor, "mode": mode, "speed": speed})
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500

@app.route('/api/motor/pid', methods=['POST'])
def set_motor_pid():
    """Set motor PID parameters"""
    if not motor_connected:
        return jsonify({"success": False, "error": "Motor not connected"}), 503
    
    data = request.json or {}
    motor = data.get('motor', 0)
    pid_type = data.get('pid_type', 0)
    kp = data.get('kp', 2.0)
    ki = data.get('ki', 0.5)
    kd = data.get('kd', 0.0)
    
    try:
        motor_driver.set_pid(motor, pid_type, kp, ki, kd)
        return jsonify({"success": True, "motor": motor, "pid_type": pid_type, "kp": kp, "ki": ki, "kd": kd})
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500

@app.route('/api/motor/enable', methods=['POST'])
def motor_enable():
    """Enable motor(s)"""
    if not motor_connected:
        return jsonify({"success": False, "error": "Motor not connected"}), 503
    motor = request.json.get('motor', 255)
    motor_driver.enable(motor)
    return jsonify({"success": True, "motor": motor, "action": "enable"})

@app.route('/api/motor/disable', methods=['POST'])
def motor_disable():
    """Disable motor(s)"""
    if not motor_connected:
        return jsonify({"success": False, "error": "Motor not connected"}), 503
    motor = request.json.get('motor', 255)
    motor_driver.disable(motor)
    return jsonify({"success": True, "motor": motor, "action": "disable"})

@app.route('/api/motor/stop', methods=['POST'])
def motor_stop():
    """Emergency stop"""
    if not motor_connected:
        return jsonify({"success": False, "error": "Motor not connected"}), 503
    motor = request.json.get('motor', 255)
    motor_driver.emergency_stop(motor)
    if servo_connected:
        servo_driver.center()
    return jsonify({"success": True, "motor": motor, "action": "emergency_stop"})

@app.route('/api/motor/home', methods=['POST'])
def motor_home():
    """Home motor(s)"""
    if not motor_connected:
        return jsonify({"success": False, "error": "Motor not connected"}), 503
    motor = request.json.get('motor', 255)
    motor_driver.home(motor)
    return jsonify({"success": True, "motor": motor, "action": "home"})

@app.route('/api/light', methods=['POST'])
def set_light():
    """Set LED light color and pattern"""
    data = request.json or {}
    color = data.get('color', 'blue')
    pattern = data.get('pattern', 'solid')
    # TODO: Control WS2812 LED strip
    robot_state['emotion'] = color
    return jsonify({"success": True, "color": color, "pattern": pattern})

@app.route('/api/speak', methods=['POST'])
def speak():
    """Text-to-speech"""
    data = request.json or {}
    text = data.get('text', '')
    # TODO: Implement TTS
    return jsonify({"success": True, "text": text})

@app.route('/api/emotion', methods=['POST'])
def set_emotion():
    """Set robot emotion (legacy, also updates display)"""
    data = request.json or {}
    emotion = data.get('emotion', 'neutral')
    robot_state['emotion'] = emotion
    if display_connected:
        face_display.set_emotion(emotion)
    return jsonify({"success": True, "emotion": emotion})

@app.route('/api/telemetry')
def telemetry():
    """SSE real-time data stream"""
    def event_stream():
        while True:
            if motor_connected:
                state = motor_driver.get_state()
                if state:
                    robot_state["motor1"] = state["motor1"]
                    robot_state["motor2"] = state["motor2"]
            
            if imu_connected:
                state = imu_driver.get_state()
                if state:
                    euler = state.get("euler", {})
                    robot_state["imu"]["pitch"] = euler.get("pitch", 0)
                    robot_state["imu"]["roll"] = euler.get("roll", 0)
                    robot_state["imu"]["yaw"] = euler.get("yaw", 0)
            
            if tracking_connected:
                state = tracking_driver.get_state()
                if state:
                    robot_state["tracking"] = {
                        "ir_data": state.get("ir_data", [0]*8),
                        "error": state.get("error", 0),
                        "pid_output": state.get("pid_output", 0),
                        "connected": state.get("connected", False),
                    }
                    # Auto line-follow in track mode
                    if robot_state["mode"] == "track" and motor_connected:
                        correction = tracking_driver.get_correction()
                        # Simple differential steering based on tracking error
                        base_speed = 20
                        turn = correction * 0.5
                        motor_driver.set_speed(0, base_speed - turn)
                        motor_driver.set_speed(1, base_speed + turn)
            
            # Simulate battery drain
            robot_state['battery'] = max(0, robot_state['battery'] - random.randint(0, 1) * 0.01)
            
            # SSH uptime
            if ssh_process is not None:
                robot_state["ssh"]["uptime"] = int(time.time() - ssh_start_time)
            
            yield f"data: {json.dumps(robot_state)}\n\n"
            time.sleep(0.1)  # 10Hz update
    return Response(event_stream(), mimetype='text/event-stream')

# ===================== Startup =====================
if __name__ == '__main__':
    import signal
    import sys
    
    def signal_handler(sig, frame):
        print('\nShutting down...')
        if motor_connected:
            motor_driver.emergency_stop()
            motor_driver.disconnect()
        if servo_connected:
            servo_driver.release()
        if imu_connected:
            imu_driver.disconnect()
        if tracking_connected:
            tracking_driver.disconnect()
        if display_connected:
            face_display.stop()
        camera.release()
        sys.exit(0)
    
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    print("=" * 50)
    print("RK3588S Smart Car Backend")
    print("=" * 50)
    print(f"Motor:    {'Connected' if motor_connected else 'SIMULATION MODE'} ({MOTOR_PORT})")
    print(f"Servo:    {'Connected' if servo_connected else 'NOT AVAILABLE'} (pwmchip{SERVO_PWM_CHIP})")
    print(f"IMU:      {'Connected' if imu_connected else 'NOT AVAILABLE'} ({IMU_PORT})")
    print(f"Tracking: {'Connected' if tracking_connected else 'NOT AVAILABLE'} ({TRACKING_PORT})")
    print(f"Display:  {'Connected' if display_connected else 'NOT AVAILABLE'}")
    print(f"Camera:   {'OK' if camera.isOpened() else 'NOT AVAILABLE'}")
    print("API Endpoints:")
    print("  GET  /video_feed           - MJPEG video stream")
    print("  GET  /api/status           - Robot status")
    print("  POST /api/control          - Control commands")
    print("  POST /api/mode             - Mode switch")
    print("  POST /api/servo            - Servo steering")
    print("  GET  /api/imu              - IMU data")
    print("  GET  /api/tracking         - Line tracking data")
    print("  POST /api/display/emotion  - Face display emotion")
    print("  POST /api/ssh/start        - One-click start backend")
    print("=" * 50)
    
    app.run(host='0.0.0.0', port=5000, threaded=True)
