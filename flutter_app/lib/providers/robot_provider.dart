import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';

class RobotProvider extends ChangeNotifier {
  Map<String, dynamic> _state = {
    'speed': 0.0,
    'heading': 0.0,
    'battery': 87.0,
    'mode': 'manual',
    'status': 'idle',
    'position': {'x': 0, 'y': 0},
    'imu': {'pitch': 0, 'roll': 0, 'yaw': 0},
    'obstacle_distance': 999,
    'target_locked': false,
    'emotion': 'neutral',
    'motor1': {'speed': 0, 'angle': 0, 'pwm': 0},
    'motor2': {'speed': 0, 'angle': 0, 'pwm': 0},
  };

  bool _connected = false;
  String _serverIp = '192.168.1.100';
  StreamSubscription? _telemetrySub;

  // Screen size (read at startup)
  double _screenWidth = 360;
  double _screenHeight = 640;

  // HUD settings (persisted)
  double _hudOpacity = 0.85;
  double _hudScale = 1.0;
  bool _showMotorHud = true;
  bool _showImuHud = true;

  // 3D Cube settings (persisted)
  bool _showCube3D = true;
  double _cubeOpacity = 0.5;

  // Emotion panel expanded (persisted)
  bool _emotionExpanded = false;

  // Draggable HUD positions (persisted as ratio 0.0-1.0)
  // Default values approximate v57 fixed positions: motor bottom-left, imu bottom-right
  double _motorHudX = 0.20;  // left ratio (center-ish)
  double _motorHudY = 0.35;  // top ratio (center-ish)
  double _imuHudX = 0.60;    // left ratio (center-ish)
  double _imuHudY = 0.35;    // top ratio (center-ish)
  bool _motorHudLocked = false; // default unlocked (draggable)
  bool _imuHudLocked = false;   // default unlocked (draggable)

  // Motor limits (persisted)
  double _motorSpeedLimit = 5.0;   // rad/s
  double _motorAccelLimit = 10.0;  // rad/s^2

  // PID parameters (persisted)
  Map<String, double> _pidSpeed = {'kp': 2.0, 'ki': 0.5, 'kd': 0.0};
  Map<String, double> _pidPosition = {'kp': 2.0, 'ki': 0.5, 'kd': 0.0};

  static const String _prefMotorSpeedLimit = 'motor_speed_limit';
  static const String _prefMotorAccelLimit = 'motor_accel_limit';
  static const String _prefPidSpeedKp = 'pid_speed_kp';
  static const String _prefPidSpeedKi = 'pid_speed_ki';
  static const String _prefPidSpeedKd = 'pid_speed_kd';
  static const String _prefPidPosKp = 'pid_pos_kp';
  static const String _prefPidPosKi = 'pid_pos_ki';
  static const String _prefPidPosKd = 'pid_pos_kd';

  static const String _prefServerIp = 'last_server_ip';
  static const String _prefHudOpacity = 'hud_opacity';
  static const String _prefHudScale = 'hud_scale';
  static const String _prefShowMotorHud = 'show_motor_hud';
  static const String _prefShowImuHud = 'show_imu_hud';
  static const String _prefShowCube3D = 'show_cube_3d';
  static const String _prefCubeOpacity = 'cube_opacity';
  static const String _prefEmotionExpanded = 'emotion_expanded';
  static const String _prefMotorHudX = 'motor_hud_x';
  static const String _prefMotorHudY = 'motor_hud_y';
  static const String _prefImuHudX = 'imu_hud_x';
  static const String _prefImuHudY = 'imu_hud_y';
  static const String _prefMotorHudLocked = 'motor_hud_locked';
  static const String _prefImuHudLocked = 'imu_hud_locked';

  // Camera info
  int _cameraWidth = 640;
  int _cameraHeight = 480;
  List<Map<String, dynamic>> _cameraPresets = [];

  Map<String, dynamic> get state => _state;
  bool get connected => _connected;
  String get serverIp => _serverIp;
  double get hudOpacity => _hudOpacity;
  double get hudScale => _hudScale;
  bool get showMotorHud => _showMotorHud;
  bool get showImuHud => _showImuHud;
  bool get showCube3D => _showCube3D;
  double get cubeOpacity => _cubeOpacity;
  int get cameraWidth => _cameraWidth;
  int get cameraHeight => _cameraHeight;
  List<Map<String, dynamic>> get cameraPresets => _cameraPresets;

  double get motorSpeedLimit => _motorSpeedLimit;
  double get motorAccelLimit => _motorAccelLimit;
  Map<String, double> get pidSpeed => Map.unmodifiable(_pidSpeed);
  Map<String, double> get pidPosition => Map.unmodifiable(_pidPosition);

  double get screenWidth => _screenWidth;
  double get screenHeight => _screenHeight;
  bool get emotionExpanded => _emotionExpanded;
  double get motorHudX => _motorHudX;
  double get motorHudY => _motorHudY;
  double get imuHudX => _imuHudX;
  double get imuHudY => _imuHudY;
  bool get motorHudLocked => _motorHudLocked;
  bool get imuHudLocked => _imuHudLocked;

  double get speed => (_state['speed'] as num?)?.toDouble() ?? 0;
  double get battery => (_state['battery'] as num?)?.toDouble() ?? 0;
  double get heading => (_state['heading'] as num?)?.toDouble() ?? 0;
  String get mode => _state['mode'] as String? ?? 'manual';
  String get status => _state['status'] as String? ?? 'idle';

  RobotProvider() {
    _loadSavedSettings();
  }

  Future<void> _loadSavedSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedIp = prefs.getString(_prefServerIp);
      if (savedIp != null && savedIp.isNotEmpty) {
        _serverIp = savedIp;
        ApiService.setServerIp(_serverIp);
      }
      _hudOpacity = prefs.getDouble(_prefHudOpacity) ?? 0.85;
      _hudScale = prefs.getDouble(_prefHudScale) ?? 1.0;
      _showMotorHud = prefs.getBool(_prefShowMotorHud) ?? true;
      _showImuHud = prefs.getBool(_prefShowImuHud) ?? true;
      _showCube3D = prefs.getBool(_prefShowCube3D) ?? true;
      _cubeOpacity = prefs.getDouble(_prefCubeOpacity) ?? 0.5;
      _emotionExpanded = prefs.getBool(_prefEmotionExpanded) ?? false;
      // Draggable HUD positions (persisted as ratio 0.0-1.0)
      // Default values approximate v57 fixed positions: motor bottom-left, imu bottom-right
      _motorHudX = (prefs.getDouble(_prefMotorHudX) ?? 0.20).clamp(0.0, 0.9);
      _motorHudY = (prefs.getDouble(_prefMotorHudY) ?? 0.35).clamp(0.0, 0.9);
      _imuHudX = (prefs.getDouble(_prefImuHudX) ?? 0.60).clamp(0.0, 0.9);
      _imuHudY = (prefs.getDouble(_prefImuHudY) ?? 0.35).clamp(0.0, 0.9);
      _motorHudLocked = prefs.getBool(_prefMotorHudLocked) ?? false;
      _imuHudLocked = prefs.getBool(_prefImuHudLocked) ?? false;
      // Motor limits
      _motorSpeedLimit = prefs.getDouble(_prefMotorSpeedLimit) ?? 5.0;
      _motorAccelLimit = prefs.getDouble(_prefMotorAccelLimit) ?? 10.0;
      // PID params
      _pidSpeed['kp'] = prefs.getDouble(_prefPidSpeedKp) ?? 2.0;
      _pidSpeed['ki'] = prefs.getDouble(_prefPidSpeedKi) ?? 0.5;
      _pidSpeed['kd'] = prefs.getDouble(_prefPidSpeedKd) ?? 0.0;
      _pidPosition['kp'] = prefs.getDouble(_prefPidPosKp) ?? 2.0;
      _pidPosition['ki'] = prefs.getDouble(_prefPidPosKi) ?? 0.5;
      _pidPosition['kd'] = prefs.getDouble(_prefPidPosKd) ?? 0.0;
      notifyListeners();
    } catch (e) {
      debugPrint('Load saved settings error: $e');
    }
  }

  Future<void> _saveHudSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_prefHudOpacity, _hudOpacity);
      await prefs.setDouble(_prefHudScale, _hudScale);
      await prefs.setBool(_prefShowMotorHud, _showMotorHud);
      await prefs.setBool(_prefShowImuHud, _showImuHud);
      await prefs.setBool(_prefShowCube3D, _showCube3D);
      await prefs.setDouble(_prefCubeOpacity, _cubeOpacity);
      await prefs.setBool(_prefEmotionExpanded, _emotionExpanded);
      await prefs.setDouble(_prefMotorHudX, _motorHudX);
      await prefs.setDouble(_prefMotorHudY, _motorHudY);
      await prefs.setDouble(_prefImuHudX, _imuHudX);
      await prefs.setDouble(_prefImuHudY, _imuHudY);
      await prefs.setBool(_prefMotorHudLocked, _motorHudLocked);
      await prefs.setBool(_prefImuHudLocked, _imuHudLocked);
    } catch (e) {
      debugPrint('Save HUD settings error: $e');
    }
  }

  Future<void> _saveMotorSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_prefMotorSpeedLimit, _motorSpeedLimit);
      await prefs.setDouble(_prefMotorAccelLimit, _motorAccelLimit);
      await prefs.setDouble(_prefPidSpeedKp, _pidSpeed['kp']!);
      await prefs.setDouble(_prefPidSpeedKi, _pidSpeed['ki']!);
      await prefs.setDouble(_prefPidSpeedKd, _pidSpeed['kd']!);
      await prefs.setDouble(_prefPidPosKp, _pidPosition['kp']!);
      await prefs.setDouble(_prefPidPosKi, _pidPosition['ki']!);
      await prefs.setDouble(_prefPidPosKd, _pidPosition['kd']!);
    } catch (e) {
      debugPrint('Save motor settings error: $e');
    }
  }

  void setScreenSize(double w, double h) {
    _screenWidth = w;
    _screenHeight = h;
    notifyListeners();
  }

  void setHudOpacity(double v) {
    _hudOpacity = v.clamp(0.3, 1.0);
    _saveHudSettings();
    notifyListeners();
  }

  void setHudScale(double v) {
    _hudScale = v.clamp(0.5, 1.5);
    _saveHudSettings();
    notifyListeners();
  }

  void setShowMotorHud(bool v) {
    _showMotorHud = v;
    _saveHudSettings();
    notifyListeners();
  }

  void setShowImuHud(bool v) {
    _showImuHud = v;
    _saveHudSettings();
    notifyListeners();
  }

  void setShowCube3D(bool v) {
    _showCube3D = v;
    _saveHudSettings();
    notifyListeners();
  }

  void setCubeOpacity(double v) {
    _cubeOpacity = v.clamp(0.0, 1.0);
    _saveHudSettings();
    notifyListeners();
  }

  void setEmotionExpanded(bool v) {
    _emotionExpanded = v;
    _saveHudSettings();
    notifyListeners();
  }

  void setMotorHudPos(double x, double y) {
    _motorHudX = x.clamp(0.0, 1.0);
    _motorHudY = y.clamp(0.0, 1.0);
    _saveHudSettings();
    notifyListeners();
  }

  void setImuHudPos(double x, double y) {
    _imuHudX = x.clamp(0.0, 1.0);
    _imuHudY = y.clamp(0.0, 1.0);
    _saveHudSettings();
    notifyListeners();
  }

  void setMotorHudLocked(bool v) {
    _motorHudLocked = v;
    _saveHudSettings();
    notifyListeners();
  }

  void setMotorSpeedLimit(double v) {
    _motorSpeedLimit = v.clamp(0.1, 20.0);
    _saveMotorSettings();
    notifyListeners();
  }

  void setMotorAccelLimit(double v) {
    _motorAccelLimit = v.clamp(0.1, 50.0);
    _saveMotorSettings();
    notifyListeners();
  }

  void setPidSpeed({required double kp, required double ki, required double kd}) {
    _pidSpeed['kp'] = kp;
    _pidSpeed['ki'] = ki;
    _pidSpeed['kd'] = kd;
    _saveMotorSettings();
    notifyListeners();
  }

  void setPidPosition({required double kp, required double ki, required double kd}) {
    _pidPosition['kp'] = kp;
    _pidPosition['ki'] = ki;
    _pidPosition['kd'] = kd;
    _saveMotorSettings();
    notifyListeners();
  }

  /// Apply motor limits: save to local prefs only, do NOT send M command
  /// Limits are applied at joystick control time, not here
  Future<void> applyMotorLimits() async {
    try {
      await _saveMotorSettings();
    } catch (e) {
      debugPrint('Apply motor limits error: $e');
    }
  }

  /// Apply PID to motor and persist
  Future<void> applyPid(int motor, int pidType) async {
    try {
      final pid = pidType == 0 ? _pidSpeed : _pidPosition;
      await ApiService.setMotorPid(
        motor: motor,
        pidType: pidType,
        kp: pid['kp']!,
        ki: pid['ki']!,
        kd: pid['kd']!,
      );
    } catch (e) {
      debugPrint('Apply PID error: $e');
    }
  }

  void setImuHudLocked(bool v) {
    _imuHudLocked = v;
    _saveHudSettings();
    notifyListeners();
  }

  Future<void> loadCameraInfo() async {
    try {
      final info = await ApiService.getCameraInfo();
      if (info['available'] == true) {
        final current = info['current'];
        _cameraWidth = current['width'] ?? 640;
        _cameraHeight = current['height'] ?? 480;
        _cameraPresets = List<Map<String, dynamic>>.from(info['presets'] ?? []);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Camera info error: $e');
    }
  }

  Future<void> setCameraResolution(int width, int height, {int? fps}) async {
    try {
      final result = await ApiService.setCameraResolution(width, height, fps: fps);
      if (result['success'] == true) {
        _cameraWidth = result['width'] ?? width;
        _cameraHeight = result['height'] ?? height;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Camera resolution error: $e');
    }
  }

  void setServerIp(String ip) {
    _serverIp = ip;
    ApiService.setServerIp(ip);
    _saveServerIp(ip);
    notifyListeners();
  }

  Future<void> _saveServerIp(String ip) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefServerIp, ip);
    } catch (e) {
      debugPrint('Save server IP error: $e');
    }
  }

  Future<void> connect() async {
    ApiService.setServerIp(_serverIp);
    try {
      final status = await ApiService.getStatus();
      _state = status;
      _connected = true;
      notifyListeners();
      _startTelemetry();
    } catch (e) {
      _connected = false;
      notifyListeners();
    }
  }

  void _startTelemetry() {
    _telemetrySub?.cancel();
    _telemetrySub = ApiService.getTelemetryStream().listen(
      (data) {
        _state = data;
        notifyListeners();
      },
      onError: (_) {
        _connected = false;
        notifyListeners();
      },
    );
  }

  Future<void> sendControl(String action, {int speed = 50}) async {
    try {
      await ApiService.sendControl(action, speed: speed);
    } catch (e) {
      _connected = false;
      notifyListeners();
    }
  }

  Future<void> setMode(String mode) async {
    try {
      await ApiService.setMode(mode);
      _state['mode'] = mode;
      notifyListeners();
    } catch (e) {
      _connected = false;
      notifyListeners();
    }
  }

  Future<void> setLight(String color, String pattern) async {
    try {
      await ApiService.setLight(color, pattern);
    } catch (e) {
      debugPrint('Light control error: $e');
    }
  }

  Future<void> setEmotion(String emotion) async {
    try {
      await ApiService.setEmotion(emotion);
      _state['emotion'] = emotion;
      notifyListeners();
    } catch (e) {
      debugPrint('Emotion control error: $e');
    }
  }

  Future<void> motorEnable() async {
    try { await ApiService.motorEnable(); } catch (e) { debugPrint('Enable error: $e'); }
  }

  Future<void> motorDisable() async {
    try { await ApiService.motorDisable(); } catch (e) { debugPrint('Disable error: $e'); }
  }

  Future<void> motorStop() async {
    try { await ApiService.motorStop(); } catch (e) { debugPrint('Stop error: $e'); }
  }

  /// Soft stop: speed=0 with high accel/decel for instant braking (no emergency stop)
  Future<void> setMotorStopAndLock() async {
    try {
      await ApiService.setMotorTarget(
        motor: 255, mode: 0, speed: 0, angle: 0,
        accel: 50, decel: 50,
      );
    } catch (e) {
      debugPrint('Soft stop error: $e');
    }
  }

  /// Direct motor target control
  Future<void> setMotorTarget({
    required int motor,
    required int mode,
    required double speed,
    double angle = 0,
    double accel = 10,
    double decel = 10,
  }) async {
    try {
      await ApiService.setMotorTarget(
        motor: motor,
        mode: mode,
        speed: speed,
        angle: angle,
        accel: accel,
        decel: decel,
      );
    } catch (e) {
      debugPrint('Motor target error: $e');
    }
  }

  /// Set PID parameters for a single motor (use twice for both)
  Future<void> setMotorPid({
    required int motor,
    required int pidType,
    required double kp,
    required double ki,
    required double kd,
  }) async {
    try {
      await ApiService.setMotorPid(
        motor: motor,
        pidType: pidType,
        kp: kp,
        ki: ki,
        kd: kd,
      );
    } catch (e) {
      debugPrint('Motor PID error: $e');
    }
  }

  Future<void> setServo(double angle) async {
    try {
      await ApiService.setServo(angle);
      _state['servo']['angle_percent'] = angle;
      notifyListeners();
    } catch (e) {
      debugPrint('Servo error: $e');
    }
  }

  Future<void> centerServo() async {
    try {
      await ApiService.centerServo();
      _state['servo']['angle_percent'] = 0;
      notifyListeners();
    } catch (e) {
      debugPrint('Servo center error: $e');
    }
  }

  Future<void> startTracking() async {
    try {
      await ApiService.startTrackingMode();
      _state['mode'] = 'track';
      notifyListeners();
    } catch (e) {
      debugPrint('Tracking start error: $e');
    }
  }

  Future<void> stopTracking() async {
    try {
      await ApiService.stopTrackingMode();
      _state['mode'] = 'manual';
      notifyListeners();
    } catch (e) {
      debugPrint('Tracking stop error: $e');
    }
  }

  Future<void> setDisplayEmotion(String emotion) async {
    try {
      await ApiService.setDisplayEmotion(emotion);
      _state['emotion'] = emotion;
      notifyListeners();
    } catch (e) {
      debugPrint('Display emotion error: $e');
    }
  }

  Future<Map<String, dynamic>> getImu() async {
    try {
      return await ApiService.getImu();
    } catch (e) {
      debugPrint('IMU error: $e');
      return {'success': false};
    }
  }

  Future<Map<String, dynamic>> getTracking() async {
    try {
      return await ApiService.getTracking();
    } catch (e) {
      debugPrint('Tracking error: $e');
      return {'success': false};
    }
  }

  Future<Map<String, dynamic>> startServer() async {
    try {
      return await ApiService.startServer();
    } catch (e) {
      debugPrint('Server start error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> getServerStatus() async {
    try {
      return await ApiService.getServerStatus();
    } catch (e) {
      debugPrint('Server status error: $e');
      return {'success': false, 'running': false};
    }
  }

  Future<void> motorHome() async {
    try { await ApiService.motorHome(); } catch (e) { debugPrint('Home error: $e'); }
  }

  @override
  void dispose() {
    _telemetrySub?.cancel();
    super.dispose();
  }
}
