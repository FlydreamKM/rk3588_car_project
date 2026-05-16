"""
RK3588S Smart Car Flask Backend
Integrates motor control, video streaming, and AI features
"""

from flask import Flask, Response, jsonify, request
from flask_cors import CORS
import cv2
import json
import threading
import time
import random
import os
import numpy as np
from motor_driver import MotorDriver

app = Flask(__name__)
CORS(app)  # Allow cross-origin for Flutter

# ===================== Motor Driver =====================
MOTOR_PORT = os.environ.get('MOTOR_PORT', '/dev/ttyUSB0')
motor_driver = MotorDriver(port=MOTOR_PORT)
motor_connected = False

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
    "mode": "manual",     # manual/auto/follow/gesture/park
    "status": "idle",     # idle/running/obstacle/charging
    "position": {"x": 0, "y": 0},
    "imu": {"pitch": 0, "roll": 0, "yaw": 0},
    "obstacle_distance": 999,
    "target_locked": False,
    "emotion": "neutral",
    "motor1": {"speed": 0, "angle": 0, "pwm": 0},
    "motor2": {"speed": 0, "angle": 0, "pwm": 0},
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
            elif action == 'right':
                motor_driver.set_car_speed(0, speed * 0.1)
            elif action == 'stop':
                motor_driver.emergency_stop()
                motor_driver.enable(255)  # Re-enable after stop
            
            robot_state['status'] = 'running' if action != 'stop' else 'idle'
            return jsonify({"success": True, "action": action, "speed": speed})
        except Exception as e:
            return jsonify({"success": False, "error": str(e)}), 500
    else:
        # Simulation mode
        robot_state['speed'] = speed if action != 'stop' else 0
        robot_state['status'] = 'running' if action != 'stop' else 'idle'
        return jsonify({"success": True, "action": action, "speed": speed, "mode": "simulation"})

@app.route('/api/mode', methods=['POST'])
def set_mode():
    """Switch mode: manual/auto/follow/gesture/park/voice"""
    global robot_state
    mode = request.json.get('mode', 'manual')
    robot_state['mode'] = mode
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
    """Set robot emotion"""
    data = request.json or {}
    emotion = data.get('emotion', 'neutral')
    robot_state['emotion'] = emotion
    # TODO: Update OLED display
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
            
            # Simulate battery drain
            robot_state['battery'] = max(0, robot_state['battery'] - random.randint(0, 1) * 0.01)
            robot_state['imu']['yaw'] = (robot_state['imu']['yaw'] + 1) % 360
            
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
        camera.release()
        sys.exit(0)
    
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    print("=" * 50)
    print("RK3588S Smart Car Backend")
    print("=" * 50)
    print(f"Motor: {'Connected' if motor_connected else 'SIMULATION MODE'}")
    print(f"Camera: {'OK' if camera.isOpened() else 'NOT AVAILABLE'}")
    print("API Endpoints:")
    print("  GET  /video_feed     - MJPEG video stream")
    print("  GET  /api/status     - Robot status")
    print("  POST /api/control    - Control commands")
    print("  POST /api/mode       - Mode switch")
    print("  POST /api/motor/*    - Direct motor control")
    print("  GET  /api/telemetry  - SSE real-time stream")
    print("=" * 50)
    
    app.run(host='0.0.0.0', port=5000, threaded=True)
