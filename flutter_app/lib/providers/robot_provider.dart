import 'dart:async';
import 'package:flutter/material.dart';
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
  
  Map<String, dynamic> get state => _state;
  bool get connected => _connected;
  String get serverIp => _serverIp;
  
  double get speed => (_state['speed'] as num?)?.toDouble() ?? 0;
  double get battery => (_state['battery'] as num?)?.toDouble() ?? 0;
  double get heading => (_state['heading'] as num?)?.toDouble() ?? 0;
  String get mode => _state['mode'] as String? ?? 'manual';
  String get status => _state['status'] as String? ?? 'idle';
  
  void setServerIp(String ip) {
    _serverIp = ip;
    ApiService.setServerIp(ip);
    notifyListeners();
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
