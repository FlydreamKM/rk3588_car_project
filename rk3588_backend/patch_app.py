import re

with open('/tmp/rk3588_car_project/rk3588_backend/app.py', 'r') as f:
    content = f.read()

# 1. Add camera_lock after imports
content = content.replace(
    'import numpy as np\nfrom motor_driver import MotorDriver',
    'import numpy as np\n\ncamera_lock = threading.Lock()\n\nfrom motor_driver import MotorDriver'
)

# 2. Replace find_camera with _open_camera
old_find = '''def find_camera():
    """Auto-detect available camera device"""
    # Try V4L2 indices 0-5
    for idx in range(6):
        cap = cv2.VideoCapture(idx)
        if cap.isOpened():
            print(f"[Camera] Found working camera at index {idx}")
            cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
            cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
            return cap
        cap.release()
    
    # Fallback: try specific device paths
    for path in ['/dev/video1', '/dev/video2', '/dev/video0']:
        cap = cv2.VideoCapture(path)
        if cap.isOpened():
            print(f"[Camera] Found working camera at {path}")
            cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
            cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
            return cap
        cap.release()
    
    print("[Camera] No camera found, creating dummy capture")
    # Return a dummy that will always fail isOpened()
    return cv2.VideoCapture(-1)

camera = find_camera()'''

new_open = '''def _open_camera(width=640, height=480):
    """Open camera with given resolution"""
    cap = cv2.VideoCapture(0)
    if not cap.isOpened():
        for path in ['/dev/video1', '/dev/video2', '/dev/video0']:
            cap = cv2.VideoCapture(path)
            if cap.isOpened():
                break
    if cap.isOpened():
        cap.set(cv2.CAP_PROP_FOURCC, cv2.VideoWriter_fourcc(*'MJPG'))
        cap.set(cv2.CAP_PROP_FRAME_WIDTH, width)
        cap.set(cv2.CAP_PROP_FRAME_HEIGHT, height)
        time.sleep(0.15)
    return cap

camera = _open_camera()'''

content = content.replace(old_find, new_open)

# 3. Lock get_camera_presets
old_presets = '''def get_camera_presets():
    """Test preset MJPEG resolutions and return available ones with FPS"""
    if not camera.isOpened():
        return []
    # Target presets: (width, height, target_fps)
    target_presets = [
        (640, 480, 400),
        (640, 512, 400),
        (960, 540, 200),
        (1280, 720, 200),
        (1280, 1024, 200),
    ]
    available = []
    # Save current
    orig_w = int(camera.get(cv2.CAP_PROP_FRAME_WIDTH))
    orig_h = int(camera.get(cv2.CAP_PROP_FRAME_HEIGHT))
    orig_fps = int(camera.get(cv2.CAP_PROP_FPS))
    # Force MJPEG format for high-FPS support
    camera.set(cv2.CAP_PROP_FOURCC, cv2.VideoWriter_fourcc(*'MJPG'))
    for w, h, fps in target_presets:
        camera.set(cv2.CAP_PROP_FRAME_WIDTH, w)
        camera.set(cv2.CAP_PROP_FRAME_HEIGHT, h)
        camera.set(cv2.CAP_PROP_FPS, fps)
        time.sleep(0.1)
        actual_w = int(camera.get(cv2.CAP_PROP_FRAME_WIDTH))
        actual_h = int(camera.get(cv2.CAP_PROP_FRAME_HEIGHT))
        actual_fps = int(camera.get(cv2.CAP_PROP_FPS))
        # Accept if close to requested resolution
        if abs(actual_w - w) <= 20 and abs(actual_h - h) <= 20:
            available.append({"width": actual_w, "height": actual_h, "fps": actual_fps})
            print(f"[Camera Preset] OK: {actual_w}x{actual_h}@{actual_fps}fps")
        else:
            print(f"[Camera Preset] Skip: requested {w}x{h}@{fps}fps, got {actual_w}x{actual_h}@{actual_fps}fps")
    # Restore original
    camera.set(cv2.CAP_PROP_FRAME_WIDTH, orig_w)
    camera.set(cv2.CAP_PROP_FRAME_HEIGHT, orig_h)
    camera.set(cv2.CAP_PROP_FPS, orig_fps)
    return available'''

new_presets = '''def get_camera_presets():
    """Test preset MJPEG resolutions and return available ones with FPS"""
    with camera_lock:
        if not camera.isOpened():
            return []
        target_presets = [
            (640, 480, 400),
            (640, 512, 400),
            (960, 540, 200),
            (1280, 720, 200),
            (1280, 1024, 200),
        ]
        available = []
        orig_w = int(camera.get(cv2.CAP_PROP_FRAME_WIDTH))
        orig_h = int(camera.get(cv2.CAP_PROP_FRAME_HEIGHT))
        orig_fps = int(camera.get(cv2.CAP_PROP_FPS))
        camera.set(cv2.CAP_PROP_FOURCC, cv2.VideoWriter_fourcc(*'MJPG'))
        for w, h, fps in target_presets:
            camera.set(cv2.CAP_PROP_FRAME_WIDTH, w)
            camera.set(cv2.CAP_PROP_FRAME_HEIGHT, h)
            camera.set(cv2.CAP_PROP_FPS, fps)
            time.sleep(0.1)
            actual_w = int(camera.get(cv2.CAP_PROP_FRAME_WIDTH))
            actual_h = int(camera.get(cv2.CAP_PROP_FRAME_HEIGHT))
            actual_fps = int(camera.get(cv2.CAP_PROP_FPS))
            if abs(actual_w - w) <= 20 and abs(actual_h - h) <= 20:
                available.append({"width": actual_w, "height": actual_h, "fps": actual_fps})
                print(f"[Camera Preset] OK: {actual_w}x{actual_h}@{actual_fps}fps")
            else:
                print(f"[Camera Preset] Skip: requested {w}x{h}@{fps}fps, got {actual_w}x{actual_h}@{actual_fps}fps")
        camera.set(cv2.CAP_PROP_FRAME_WIDTH, orig_w)
        camera.set(cv2.CAP_PROP_FRAME_HEIGHT, orig_h)
        camera.set(cv2.CAP_PROP_FPS, orig_fps)
        return available'''

content = content.replace(old_presets, new_presets)

# 4. Replace set_camera_resolution
old_set = '''def set_camera_resolution(w, h, fps=None):
    if not camera.isOpened():
        return False, "Camera not available"
    # Try MJPEG first for high-FPS cameras
    camera.set(cv2.CAP_PROP_FOURCC, cv2.VideoWriter_fourcc(*'MJPG'))
    camera.set(cv2.CAP_PROP_FRAME_WIDTH, w)
    camera.set(cv2.CAP_PROP_FRAME_HEIGHT, h)
    if fps:
        camera.set(cv2.CAP_PROP_FPS, fps)
    time.sleep(0.15)
    actual_w = int(camera.get(cv2.CAP_PROP_FRAME_WIDTH))
    actual_h = int(camera.get(cv2.CAP_PROP_FRAME_HEIGHT))
    actual_fps = int(camera.get(cv2.CAP_PROP_FPS))
    if actual_w <= 0 or actual_h <= 0:
        return False, f"Camera rejected {w}x{h}"
    robot_state["camera"]["width"] = actual_w
    robot_state["camera"]["height"] = actual_h
    robot_state["camera"]["target_fps"] = actual_fps
    return True, {"width": actual_w, "height": actual_h, "fps": actual_fps}'''

new_set = '''def set_camera_resolution(w, h, fps=None):
    global camera
    if not camera.isOpened():
        return False, "Camera not available"
    with camera_lock:
        camera.release()
        time.sleep(0.2)
        new_cam = _open_camera(w, h)
        if not new_cam.isOpened():
            new_cam = _open_camera(640, 480)
            if not new_cam.isOpened():
                return False, "Failed to re-open camera after resolution change"
        actual_w = int(new_cam.get(cv2.CAP_PROP_FRAME_WIDTH))
        actual_h = int(new_cam.get(cv2.CAP_PROP_FRAME_HEIGHT))
        actual_fps = int(new_cam.get(cv2.CAP_PROP_FPS))
        if actual_w <= 0 or actual_h <= 0:
            new_cam.release()
            return False, f"Camera rejected {w}x{h}"
        camera = new_cam
        robot_state["camera"]["width"] = actual_w
        robot_state["camera"]["height"] = actual_h
        robot_state["camera"]["target_fps"] = actual_fps
        return True, {"width": actual_w, "height": actual_h, "fps": actual_fps}'''

content = content.replace(old_set, new_set)

# 5. Lock generate_frames read
old_gen = '''def generate_frames():
    """Generate MJPEG frames at camera native rate"""
    global _camera_fps, _camera_frame_count, _camera_fps_time
    while True:
        success, frame = camera.read()'''

new_gen = '''def generate_frames():
    """Generate MJPEG frames at camera native rate"""
    global _camera_fps, _camera_frame_count, _camera_fps_time
    while True:
        with camera_lock:
            success, frame = camera.read()'''

content = content.replace(old_gen, new_gen)

# 6. Lock video_feed resolution change
old_video = '''@app.route('/video_feed')
def video_feed():
    """MJPEG video stream endpoint. Supports ?w=640&h=480 for resolution override."""
    w = request.args.get('w', type=int)
    h = request.args.get('h', type=int)
    if w and h and camera.isOpened():
        camera.set(cv2.CAP_PROP_FRAME_WIDTH, w)
        camera.set(cv2.CAP_PROP_FRAME_HEIGHT, h)
        time.sleep(0.05)
    return Response(generate_frames(),
                    mimetype='multipart/x-mixed-replace; boundary=frame')'''

new_video = '''@app.route('/video_feed')
def video_feed():
    """MJPEG video stream endpoint. Supports ?w=640&h=480 for resolution override."""
    w = request.args.get('w', type=int)
    h = request.args.get('h', type=int)
    if w and h and camera.isOpened():
        with camera_lock:
            curr_w = int(camera.get(cv2.CAP_PROP_FRAME_WIDTH))
            curr_h = int(camera.get(cv2.CAP_PROP_FRAME_HEIGHT))
            if curr_w != w or curr_h != h:
                camera.set(cv2.CAP_PROP_FRAME_WIDTH, w)
                camera.set(cv2.CAP_PROP_FRAME_HEIGHT, h)
                time.sleep(0.05)
    return Response(generate_frames(),
                    mimetype='multipart/x-mixed-replace; boundary=frame')'''

content = content.replace(old_video, new_video)

# 7. Fix display emotion 503 -> 200
old_disp1 = '''@app.route('/api/display/emotion', methods=['POST'])
def set_display_emotion():
    """Set display emotion face"""
    if not display_connected:
        return jsonify({"success": False, "error": "Display not connected"}), 503
    emotion = request.json.get('emotion', 'neutral')
    face_display.set_emotion(emotion)
    robot_state["emotion"] = emotion
    return jsonify({"success": True, "emotion": emotion})'''

new_disp1 = '''@app.route('/api/display/emotion', methods=['POST'])
def set_display_emotion():
    """Set display emotion face"""
    emotion = request.json.get('emotion', 'neutral')
    robot_state["emotion"] = emotion
    if display_connected:
        face_display.set_emotion(emotion)
        return jsonify({"success": True, "emotion": emotion})
    return jsonify({"success": False, "error": "Display not connected", "emotion": emotion, "unavailable": True})'''

content = content.replace(old_disp1, new_disp1)

# 8. Fix display status 503 -> 200
old_disp2 = '''@app.route('/api/display/status', methods=['GET'])
def get_display_status():
    """Get display status"""
    if display_connected:
        return jsonify({"success": True, "data": face_display.get_state()})
    return jsonify({"success": False, "error": "Display not connected"}), 503'''

new_disp2 = '''@app.route('/api/display/status', methods=['GET'])
def get_display_status():
    """Get display status"""
    if display_connected:
        return jsonify({"success": True, "data": face_display.get_state()})
    return jsonify({"success": False, "error": "Display not connected", "unavailable": True})'''

content = content.replace(old_disp2, new_disp2)

# 9. Lock camera release in signal handler
old_sig = '''        if display_connected:
            face_display.stop()
        camera.release()
        sys.exit(0)'''

new_sig = '''        if display_connected:
            face_display.stop()
        with camera_lock:
            camera.release()
        sys.exit(0)'''

content = content.replace(old_sig, new_sig)

with open('/tmp/rk3588_car_project/rk3588_backend/app.py', 'w') as f:
    f.write(content)

print("Patch applied successfully")
