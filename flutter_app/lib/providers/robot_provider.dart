import 'dart:async';
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

  // HUD settings (persisted)
  double _hudOpacity = 0.85;
  double _hudScale = 1.0;

  // Camera settings
  int _cameraWidth = 640;
  int _cameraHeight = 480;
  List<Map<String, dynamic>> _cameraPresets = [];

  static const String _prefServerIp = 'last_server_ip';
  static const String _prefHudOpacity = 'hud_opacity';
  static const String _prefHudScale = 'hud_scale';

  Map<String, dynamic> get state => _state;
  bool get connected => _connected;
  String get serverIp => _serverIp;
  double get hudOpacity => _hudOpacity;
  double get hudScale => _hudScale;
  int get cameraWidth => _cameraWidth;
  int get cameraHeight => _cameraHeight;
  List<Map<String, dynamic>> get cameraPresets => _cameraPresets;
  
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
    } catch (e) {
      debugPrint('Save HUD settings error: $e');
    }
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
  
  Future<void> setCameraResolution(int width, int height) async {
    try {
      final result = await ApiService.setCameraResolution(width, height);
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
