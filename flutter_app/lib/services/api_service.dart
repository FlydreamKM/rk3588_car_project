import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  static String baseUrl = 'http://192.168.1.100:5000';
  
  static void setServerIp(String ip) {
    baseUrl = 'http://$ip:5000';
  }
  
  // ===================== Control =====================
  static Future<Map<String, dynamic>> sendControl(String action, {int speed = 50}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/control'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'action': action, 'speed': speed}),
    );
    return jsonDecode(response.body);
  }
  
  static Future<Map<String, dynamic>> setMode(String mode) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/mode'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'mode': mode}),
    );
    return jsonDecode(response.body);
  }
  
  // ===================== Motor Direct Control =====================
  static Future<Map<String, dynamic>> setMotorTarget({
    required int motor,
    required int mode,
    required double speed,
    double angle = 0,
    double accel = 10,
    double decel = 10,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/motor/target'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'motor': motor,
        'mode': mode,
        'speed': speed,
        'angle': angle,
        'accel': accel,
        'decel': decel,
      }),
    );
    return jsonDecode(response.body);
  }
  
  static Future<Map<String, dynamic>> setMotorPid({
    required int motor,
    required int pidType,
    required double kp,
    required double ki,
    required double kd,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/motor/pid'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'motor': motor,
        'pid_type': pidType,
        'kp': kp,
        'ki': ki,
        'kd': kd,
      }),
    );
    return jsonDecode(response.body);
  }
  
  static Future<Map<String, dynamic>> motorEnable([int motor = 255]) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/motor/enable'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'motor': motor}),
    );
    return jsonDecode(response.body);
  }
  
  static Future<Map<String, dynamic>> motorDisable([int motor = 255]) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/motor/disable'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'motor': motor}),
    );
    return jsonDecode(response.body);
  }
  
  static Future<Map<String, dynamic>> motorStop([int motor = 255]) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/motor/stop'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'motor': motor}),
    );
    return jsonDecode(response.body);
  }
  
  static Future<Map<String, dynamic>> motorHome([int motor = 255]) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/motor/home'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'motor': motor}),
    );
    return jsonDecode(response.body);
  }
  
  // ===================== Status =====================
  static Future<Map<String, dynamic>> getStatus() async {
    final response = await http.get(Uri.parse('$baseUrl/api/status'));
    return jsonDecode(response.body);
  }
  
  // ===================== Light =====================
  static Future<Map<String, dynamic>> setLight(String color, String pattern) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/light'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'color': color, 'pattern': pattern}),
    );
    return jsonDecode(response.body);
  }
  
  // ===================== Speak =====================
  static Future<Map<String, dynamic>> speak(String text) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/speak'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'text': text}),
    );
    return jsonDecode(response.body);
  }
  
  // ===================== Emotion =====================
  static Future<Map<String, dynamic>> setEmotion(String emotion) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/emotion'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'emotion': emotion}),
    );
    return jsonDecode(response.body);
  }
  
  // ===================== Servo =====================
  static Future<Map<String, dynamic>> setServo(double angle) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/servo'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'angle': angle}),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> centerServo() async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/servo/center'),
      headers: {'Content-Type': 'application/json'},
    );
    return jsonDecode(response.body);
  }

  // ===================== IMU =====================
  static Future<Map<String, dynamic>> getImu() async {
    final response = await http.get(Uri.parse('$baseUrl/api/imu'));
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> calibrateImu(String type, {double? temperature}) async {
    final body = <String, dynamic>{'type': type};
    if (temperature != null) body['temperature'] = temperature;
    final response = await http.post(
      Uri.parse('$baseUrl/api/imu/calibrate'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> getImuCalibrationStatus() async {
    final response = await http.get(Uri.parse('$baseUrl/api/imu/calibrate/status'));
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> getImuVersion() async {
    final response = await http.get(Uri.parse('$baseUrl/api/imu/version'));
    return jsonDecode(response.body);
  }

  // ===================== Tracking =====================
  static Future<Map<String, dynamic>> getTracking() async {
    final response = await http.get(Uri.parse('$baseUrl/api/tracking'));
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> startTrackingMode() async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/tracking/start'),
      headers: {'Content-Type': 'application/json'},
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> stopTrackingMode() async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/tracking/stop'),
      headers: {'Content-Type': 'application/json'},
    );
    return jsonDecode(response.body);
  }

  // ===================== Display =====================
  static Future<Map<String, dynamic>> setDisplayEmotion(String emotion) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/display/emotion'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'emotion': emotion}),
    );
    return jsonDecode(response.body);
  }

  // ===================== Camera =====================
  static Future<Map<String, dynamic>> getCameraInfo() async {
    final response = await http.get(Uri.parse('$baseUrl/api/camera/info'));
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> setCameraResolution(int width, int height, {int? fps}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/camera/resolution'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'width': width, 'height': height, if (fps != null) 'fps': fps}),
    );
    return jsonDecode(response.body);
  }
  static Future<Map<String, dynamic>> startServer() async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/ssh/start'),
      headers: {'Content-Type': 'application/json'},
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> getServerStatus() async {
    final response = await http.get(Uri.parse('$baseUrl/api/ssh/status'));
    return jsonDecode(response.body);
  }
  static Stream<Map<String, dynamic>> getTelemetryStream() async* {
    final client = http.Client();
    final request = http.Request('GET', Uri.parse('$baseUrl/api/telemetry'));
    request.headers['Accept'] = 'text/event-stream';
    
    final response = await client.send(request);
    
    await for (final chunk in response.stream.transform(utf8.decoder)) {
      for (final line in chunk.split('\n')) {
        if (line.startsWith('data: ')) {
          try {
            final data = jsonDecode(line.substring(6));
            yield data;
          } catch (_) {
            // Skip invalid JSON
          }
        }
      }
    }
  }
}
