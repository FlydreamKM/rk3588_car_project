import 'dart:async';
import 'package:flutter/material.dart';
import 'package:glassmorphism_ui/glassmorphism_ui.dart';
import 'package:provider/provider.dart';
import '../providers/robot_provider.dart';
import '../services/api_service.dart';
import '../services/ssh_service.dart';
import 'main_screen.dart';

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({Key? key}) : super(key: key);

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  final _ipController = TextEditingController(text: '192.168.1.100');
  final _sshUserController = TextEditingController(text: 'root');
  final _sshPassController = TextEditingController(text: '');
  final _sshPortController = TextEditingController(text: '22');

  bool _isConnecting = false;
  bool _isHttpConnected = false;
  bool _isSshConnected = false;
  bool _serverStarted = false;
  String _statusMessage = '请输入 RK3588S 连接信息';

  Future<void> _testHttpConnection() async {
    setState(() {
      _isConnecting = true;
      _statusMessage = '正在测试 HTTP API 连接...';
    });

    final ip = _ipController.text.trim();
    ApiService.setServerIp(ip);

    try {
      final response = await ApiService.getStatus().timeout(Duration(seconds: 5));
      setState(() {
        _isHttpConnected = true;
        _statusMessage = 'HTTP API 连接成功 ✅';
      });
    } catch (e) {
      setState(() {
        _isHttpConnected = false;
        _statusMessage = 'HTTP API 连接失败 ❌\n请确认 IP 正确且后端已启动';
      });
    } finally {
      setState(() => _isConnecting = false);
    }
  }

  Future<void> _connectSsh() async {
    setState(() {
      _isConnecting = true;
      _statusMessage = '正在建立 SSH 连接...';
    });

    final host = _ipController.text.trim();
    final port = int.tryParse(_sshPortController.text.trim()) ?? 22;
    final user = _sshUserController.text.trim();
    final pass = _sshPassController.text;

    final success = await SshService.connect(
      host: host,
      port: port,
      username: user,
      password: pass,
    );

    setState(() {
      _isSshConnected = success;
      _statusMessage = success
          ? 'SSH 连接成功 ✅\n可以远程控制服务端'
          : 'SSH 连接失败 ❌\n请检查用户名/密码/端口';
      _isConnecting = false;
    });
  }

  Future<void> _startServer() async {
    setState(() {
      _isConnecting = true;
      _statusMessage = '正在一键启动服务端...';
    });

    // Try API first (if backend partially running)
    final apiUrl = 'http://${_ipController.text.trim()}:5000';
    bool apiSuccess = await SshService.startServerViaApi(apiUrl);

    // Fallback to SSH if available
    if (!apiSuccess && _isSshConnected) {
      apiSuccess = await SshService.startRemoteServer();
    }

    setState(() {
      _serverStarted = apiSuccess;
      _statusMessage = apiSuccess
          ? '服务端启动命令已发送 ✅\n请等待 3-5 秒后进入控制面板'
          : '服务端启动失败 ❌\n请手动检查 RK3588S';
      _isConnecting = false;
    });

    if (apiSuccess) {
      await Future.delayed(Duration(seconds: 2));
      await _testHttpConnection();
    }
  }

  void _enterControlPanel() {
    final provider = context.read<RobotProvider>();
    provider.setServerIp(_ipController.text.trim());
    provider.connect();

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => MainScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF0A0E21),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(height: 40),
              // App icon / robot avatar
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.cyanAccent, Colors.purpleAccent],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.cyanAccent.withOpacity(0.4),
                      blurRadius: 30,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Icon(
                  Icons.smart_toy,
                  size: 56,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: 24),
              Text(
                '智能小车控制中枢',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 2,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'RK3588S 远程连接',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                  letterSpacing: 1,
                ),
              ),
              SizedBox(height: 32),

              // Connection settings card
              GlassContainer(
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withOpacity(0.1),
                    Colors.white.withOpacity(0.05),
                  ],
                ),
                blur: 20,
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSectionTitle(Icons.wifi, 'RK3588S IP 地址'),
                      SizedBox(height: 12),
                      _buildTextField(
                        controller: _ipController,
                        label: 'IP 地址',
                        hint: '例如: 192.168.1.100',
                        icon: Icons.computer,
                      ),
                      SizedBox(height: 20),
                      _buildSectionTitle(Icons.terminal, 'SSH 连接 (可选)'),
                      SizedBox(height: 12),
                      _buildTextField(
                        controller: _sshUserController,
                        label: '用户名',
                        hint: 'root',
                        icon: Icons.person,
                      ),
                      SizedBox(height: 10),
                      _buildTextField(
                        controller: _sshPassController,
                        label: '密码',
                        hint: 'SSH 密码',
                        icon: Icons.lock,
                        obscure: true,
                      ),
                      SizedBox(height: 10),
                      _buildTextField(
                        controller: _sshPortController,
                        label: '端口',
                        hint: '22',
                        icon: Icons.settings_ethernet,
                        keyboardType: TextInputType.number,
                      ),
                    ],
                  ),
                ),
              ),

              SizedBox(height: 24),

              // Status indicator
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _isHttpConnected
                      ? Colors.green.withOpacity(0.15)
                      : Colors.orange.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _isHttpConnected
                        ? Colors.green.withOpacity(0.5)
                        : Colors.orange.withOpacity(0.5),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: _isHttpConnected ? Colors.green : Colors.orange,
                            shape: BoxShape.circle,
                          ),
                        ),
                        SizedBox(width: 8),
                        Text(
                          _statusMessage,
                          style: TextStyle(
                            color: _isHttpConnected ? Colors.green : Colors.orange,
                            fontSize: 13,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                    if (_isHttpConnected) ...[
                      SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildStatusChip(
                            icon: Icons.http,
                            label: 'HTTP',
                            active: _isHttpConnected,
                          ),
                          SizedBox(width: 8),
                          _buildStatusChip(
                            icon: Icons.terminal,
                            label: 'SSH',
                            active: _isSshConnected,
                          ),
                          SizedBox(width: 8),
                          _buildStatusChip(
                            icon: Icons.play_circle,
                            label: '服务端',
                            active: _serverStarted,
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              SizedBox(height: 24),

              // Action buttons
              _buildActionButton(
                label: '测试 HTTP 连接',
                icon: Icons.network_check,
                color: Colors.cyanAccent,
                onPressed: _isConnecting ? null : _testHttpConnection,
              ),
              SizedBox(height: 12),
              _buildActionButton(
                label: '连接 SSH',
                icon: Icons.terminal,
                color: Colors.purpleAccent,
                onPressed: _isConnecting ? null : _connectSsh,
              ),
              SizedBox(height: 12),
              _buildActionButton(
                label: '一键启动服务端',
                icon: Icons.rocket_launch,
                color: Colors.orangeAccent,
                onPressed: _isConnecting ? null : _startServer,
              ),
              SizedBox(height: 12),
              _buildActionButton(
                label: '进入控制面板',
                icon: Icons.dashboard,
                color: Colors.greenAccent,
                onPressed: _isHttpConnected ? _enterControlPanel : null,
                filled: true,
              ),

              SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, color: Colors.cyanAccent, size: 18),
        SizedBox(width: 8),
        Text(
          text,
          style: TextStyle(
            color: Colors.cyanAccent,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool obscure = false,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType ?? TextInputType.text,
      style: TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey, fontSize: 12),
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey.withOpacity(0.5), fontSize: 12),
        prefixIcon: Icon(icon, color: Colors.cyanAccent.withOpacity(0.7), size: 20),
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Colors.cyanAccent.withOpacity(0.2)),
          borderRadius: BorderRadius.circular(12),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Colors.cyanAccent),
          borderRadius: BorderRadius.circular(12),
        ),
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  Widget _buildStatusChip({
    required IconData icon,
    required String label,
    required bool active,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: active ? Colors.green.withOpacity(0.2) : Colors.grey.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: active ? Colors.green.withOpacity(0.5) : Colors.grey.withOpacity(0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: active ? Colors.green : Colors.grey),
          SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: active ? Colors.green : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback? onPressed,
    bool filled = false,
  }) {
    final isEnabled = onPressed != null;
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: filled ? color : Colors.transparent,
          foregroundColor: filled ? Colors.black : color,
          disabledBackgroundColor: Colors.grey.withOpacity(0.1),
          disabledForegroundColor: Colors.grey,
          side: filled ? null : BorderSide(color: isEnabled ? color : Colors.grey, width: 1.5),
          padding: EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: filled ? 4 : 0,
        ),
        icon: _isConnecting && isEnabled
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: filled ? Colors.black : color,
                ),
              )
            : Icon(icon, size: 20),
        label: Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
