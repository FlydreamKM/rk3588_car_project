import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class SshService {
  static SSHClient? _client;
  static SSHSession? _session;
  static StreamController<String>? _terminalOutput;
  static final ListQueue<String> _outputHistory = ListQueue<String>(2000);
  static String _host = '';
  static int _port = 22;
  static String _username = '';
  static String _password = '';

  // Developer mode
  static bool _developerMode = false;
  static String _customStartCommand = '';

  // SharedPreferences keys
  static const String _prefSshHost = 'ssh_host';
  static const String _prefSshPort = 'ssh_port';
  static const String _prefSshUser = 'ssh_username';
  static const String _prefSshPass = 'ssh_password';
  static const String _prefDevMode = 'developer_mode';
  static const String _prefCustomCmd = 'custom_start_command';

  static String get host => _host;
  static int get port => _port;
  static String get username => _username;
  static bool get developerMode => _developerMode;
  static String get customStartCommand => _customStartCommand;
  static List<String> get outputHistory => List<String>.from(_outputHistory);

  static Stream<String>? get terminalOutput => _terminalOutput?.stream;

  /// Load last saved SSH credentials and settings from SharedPreferences
  static Future<Map<String, dynamic>> loadSavedCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _developerMode = prefs.getBool(_prefDevMode) ?? false;
      _customStartCommand = prefs.getString(_prefCustomCmd) ?? '';
      return {
        'host': prefs.getString(_prefSshHost) ?? '',
        'port': int.tryParse(prefs.getString(_prefSshPort) ?? '') ?? 22,
        'username': prefs.getString(_prefSshUser) ?? '',
        'password': prefs.getString(_prefSshPass) ?? '',
        'developerMode': _developerMode,
        'customStartCommand': _customStartCommand,
      };
    } catch (e) {
      print('SSH load credentials error: $e');
      return {
        'host': '',
        'port': 22,
        'username': '',
        'password': '',
        'developerMode': false,
        'customStartCommand': '',
      };
    }
  }

  /// Save SSH credentials to SharedPreferences
  static Future<void> saveCredentials({
    required String host,
    int port = 22,
    required String username,
    required String password,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefSshHost, host);
      await prefs.setString(_prefSshPort, port.toString());
      await prefs.setString(_prefSshUser, username);
      await prefs.setString(_prefSshPass, password);
    } catch (e) {
      print('SSH save credentials error: $e');
    }
  }

  /// Save developer mode setting
  static Future<void> setDeveloperMode(bool enabled) async {
    _developerMode = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefDevMode, enabled);
    } catch (e) {
      print('Save dev mode error: $e');
    }
  }

  /// Save custom start command
  static Future<void> setCustomStartCommand(String command) async {
    _customStartCommand = command.trim();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefCustomCmd, _customStartCommand);
    } catch (e) {
      print('Save custom command error: $e');
    }
  }

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

      // Save successful connection data
      await saveCredentials(
        host: host,
        port: port,
        username: username,
        password: password,
      );

      _terminalOutput = StreamController<String>.broadcast();
      return true;
    } catch (e) {
      print('SSH connect error: $e');
      disconnect();
      return false;
    }
  }

  static Future<Map<String, dynamic>> startRemoteServer() async {
    if (_client == null) return {'success': false, 'error': 'SSH not connected'};
    try {
      final command = _customStartCommand.isNotEmpty && _developerMode
          ? _customStartCommand
          : 'cd ~/rk3588_car_project/rk3588_backend && setsid bash -c "nohup bash start.sh > /tmp/car_backend.log 2>&1" \u003e/dev/null 2\u003e\u00261 \u0026';
      await _client!.run(command);

      // Wait for backend to boot
      await Future.delayed(Duration(seconds: 3));

      // Check if port 5000 is actually listening
      final check = await _client!.run('ss -tlnp | grep -q ":5000" \u0026\u0026 echo "OK" || echo "FAIL"');
      final status = utf8.decode(check).trim();

      if (status == "OK") {
        return {'success': true};
      }

      // Port not open — fetch recent log for diagnosis
      final logBytes = await _client!.run('tail -n 30 /tmp/car_backend.log 2\u003e/dev/null || echo "No log"');
      final logs = utf8.decode(logBytes).trim();
      return {'success': false, 'error': 'Backend did not start on port 5000', 'logs': logs};
    } catch (e) {
      print('SSH start server error: $e');
      return {'success': false, 'error': e.toString()};
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
        _addToHistory(data);
        _terminalOutput?.add(data);
      });

      _session!.stderr
          .cast<List<int>>()
          .transform(utf8.decoder)
          .listen((data) {
        final line = '[stderr] $data';
        _addToHistory(line);
        _terminalOutput?.add(line);
      });

      return true;
    } catch (e) {
      print('SSH terminal error: $e');
      return false;
    }
  }

  static void _addToHistory(String data) {
    // Split by newlines and add each line
    final lines = data.split('\n');
    for (final line in lines) {
      if (line.isNotEmpty) {
        _outputHistory.add(line);
        if (_outputHistory.length > 2000) {
          _outputHistory.removeFirst();
        }
      }
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
    _outputHistory.clear();
  }

  static bool get isConnected => _client != null;
}
