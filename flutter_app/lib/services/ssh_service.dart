import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';
import 'package:http/http.dart' as http;

class SshService {
  static SSHClient? _client;
  static SSHSession? _session;
  static StreamController<String>? _terminalOutput;
  static String _host = '';
  static int _port = 22;
  static String _username = '';
  static String _password = '';

  static String get host => _host;
  static int get port => _port;
  static String get username => _username;

  static Stream<String>? get terminalOutput => _terminalOutput?.stream;

  static Future<bool> connect({
    required String host,
    int port = 22,
    required String username,
    required String password,
  }) async {
    try {
      _host = host;
      _port = port;
      _username = username;
      _password = password;

      final socket = await SSHSocket.connect(host, port);
      _client = SSHClient(
        socket,
        username: username,
        onPasswordRequest: () => password,
      );

      // Verify connection
      await _client!.authenticated;
      
      _terminalOutput = StreamController<String>.broadcast();
      return true;
    } catch (e) {
      print('SSH connect error: $e');
      disconnect();
      return false;
    }
  }

  static Future<bool> startRemoteServer() async {
    if (_client == null) return false;
    try {
      final result = await _client!.run(
        'cd ~/rk3588_car_project/rk3588_backend && nohup bash start.sh > /tmp/car_backend.log 2>&1 &'
      );
      return true;
    } catch (e) {
      print('SSH start server error: $e');
      return false;
    }
  }

  static Future<bool> startServerViaApi(String apiBaseUrl) async {
    try {
      final response = await http.post(
        Uri.parse('$apiBaseUrl/api/ssh/start'),
        headers: {'Content-Type': 'application/json'},
      );
      final data = jsonDecode(response.body);
      return data['success'] == true;
    } catch (e) {
      print('API start server error: $e');
      return false;
    }
  }

  static Future<String?> execute(String command) async {
    if (_client == null) return null;
    try {
      final result = await _client!.run(command);
      return utf8.decode(result);
    } catch (e) {
      print('SSH execute error: $e');
      return null;
    }
  }

  static Future<bool> startTerminal() async {
    if (_client == null) return false;
    try {
      _session = await _client!.execute('bash');
      
      _session!.stdout
          .cast<List<int>>()
          .transform(utf8.decoder)
          .listen((data) {
        _terminalOutput?.add(data);
      });

      _session!.stderr
          .cast<List<int>>()
          .transform(utf8.decoder)
          .listen((data) {
        _terminalOutput?.add('[stderr] $data');
      });

      return true;
    } catch (e) {
      print('SSH terminal error: $e');
      return false;
    }
  }

  static void writeToTerminal(String input) {
    if (_session != null) {
      _session!.stdin.add(utf8.encode(input));
    }
  }

  static void disconnect() {
    _session?.close();
    _session = null;
    _client?.close();
    _client = null;
    _terminalOutput?.close();
    _terminalOutput = null;
  }

  static bool get isConnected => _client != null;
}
