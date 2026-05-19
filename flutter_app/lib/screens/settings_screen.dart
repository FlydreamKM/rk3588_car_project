import 'dart:math';
import 'package:flutter/material.dart';
import 'package:glassmorphism_ui/glassmorphism_ui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/robot_provider.dart';
import '../services/ssh_service.dart';
import 'terminal_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _developerMode = false;
  final _commandController = TextEditingController();
  bool _isSaving = false;

  // PID controllers
  final _pidControllers = [
    // Motor 1 Speed
    {'motor': 0, 'pid_type': 0, 'label': '电机1 — 速度环'},
    // Motor 1 Position
    {'motor': 0, 'pid_type': 1, 'label': '电机1 — 位置环'},
    // Motor 2 Speed
    {'motor': 1, 'pid_type': 0, 'label': '电机2 — 速度环'},
    // Motor 2 Position
    {'motor': 1, 'pid_type': 1, 'label': '电机2 — 位置环'},
  ];

  final Map<String, TextEditingController> _pidKp = {};
  final Map<String, TextEditingController> _pidKi = {};
  final Map<String, TextEditingController> _pidKd = {};

  @override
  void initState() {
    super.initState();
    _loadSettings();
    for (final cfg in _pidControllers) {
      final key = '${cfg['motor']}_${cfg['pid_type']}';
      _pidKp[key] = TextEditingController(text: '2.0');
      _pidKi[key] = TextEditingController(text: '0.5');
      _pidKd[key] = TextEditingController(text: '0.0');
    }
  }

  @override
  void dispose() {
    _commandController.dispose();
    for (final c in _pidKp.values) c.dispose();
    for (final c in _pidKi.values) c.dispose();
    for (final c in _pidKd.values) c.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final creds = await SshService.loadSavedCredentials();
    setState(() {
      _developerMode = creds['developerMode'] as bool? ?? false;
      _commandController.text = creds['customStartCommand'] as String? ?? '';
    });
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);
    await SshService.setDeveloperMode(_developerMode);
    await SshService.setCustomStartCommand(_commandController.text.trim());
    setState(() => _isSaving = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('设置已保存', style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.green.withOpacity(0.8),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  void _openTerminal() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TerminalScreen()),
    );
  }

  Future<void> _applyPid(Map<String, dynamic> cfg) async {
    final key = '${cfg['motor']}_${cfg['pid_type']}';
    final kp = double.tryParse(_pidKp[key]!.text) ?? 2.0;
    final ki = double.tryParse(_pidKi[key]!.text) ?? 0.5;
    final kd = double.tryParse(_pidKd[key]!.text) ?? 0.0;

    final provider = context.read<RobotProvider>();
    await provider.setMotorPid(
      motor: cfg['motor'] as int,
      pidType: cfg['pid_type'] as int,
      kp: kp,
      ki: ki,
      kd: kd,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${cfg['label']} PID 已更新', style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.cyanAccent.withOpacity(0.8),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RobotProvider>();

    return Scaffold(
      backgroundColor: Color(0xFF0A0E21),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          '设置',
          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── HUD Display Settings ──
            _buildSectionTitle('HUD 显示设置', Icons.visibility),
            SizedBox(height: 12),
            GlassContainer(
              gradient: LinearGradient(
                colors: [
                  Colors.white.withOpacity(0.1),
                  Colors.white.withOpacity(0.05),
                ],
              ),
              blur: 20,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Motor HUD toggle
                    _buildSwitchRow(
                      '电机详细数据',
                      '视频流上显示电机速度/角度/PWM',
                      provider.showMotorHud,
                      (v) => provider.setShowMotorHud(v),
                    ),
                    Divider(color: Colors.white.withOpacity(0.1), height: 20),
                    // IMU HUD toggle
                    _buildSwitchRow(
                      'IMU 详细数据',
                      '视频流上显示 IMU 姿态数值',
                      provider.showImuHud,
                      (v) => provider.setShowImuHud(v),
                    ),
                    Divider(color: Colors.white.withOpacity(0.1), height: 20),
                    // 3D Cube toggle
                    _buildSwitchRow(
                      '3D 姿态方块',
                      '视频流上叠加 3D 立方体（绑定 IMU）',
                      provider.showCube3D,
                      (v) => provider.setShowCube3D(v),
                    ),
                    if (provider.showCube3D) ...[
                      SizedBox(height: 8),
                      Text(
                        '透明度 ${(provider.cubeOpacity * 100).toInt()}%',
                        style: TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                      Slider(
                        value: provider.cubeOpacity,
                        min: 0.0,
                        max: 1.0,
                        divisions: 20,
                        activeColor: Colors.purpleAccent,
                        inactiveColor: Colors.purpleAccent.withOpacity(0.2),
                        onChanged: (v) => provider.setCubeOpacity(v),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            SizedBox(height: 24),

            // ── PID Settings ──
            _buildSectionTitle('PID 参数调节', Icons.tune),
            SizedBox(height: 12),
            GlassContainer(
              gradient: LinearGradient(
                colors: [
                  Colors.white.withOpacity(0.1),
                  Colors.white.withOpacity(0.05),
                ],
              ),
              blur: 20,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '分别设置电机1/2的速度环和位置环 PID\n逐个发送，不使用 CMD_SET_PID_BOTH',
                      style: TextStyle(
                        color: Colors.grey.withOpacity(0.8),
                        fontSize: 11,
                      ),
                    ),
                    SizedBox(height: 12),
                    ..._pidControllers.map((cfg) => _buildPidRow(cfg)),
                  ],
                ),
              ),
            ),

            SizedBox(height: 24),

            // ── Developer Options ──
            _buildSectionTitle('开发者选项', Icons.code),
            SizedBox(height: 12),
            GlassContainer(
              gradient: LinearGradient(
                colors: [
                  Colors.white.withOpacity(0.1),
                  Colors.white.withOpacity(0.05),
                ],
              ),
              blur: 20,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSwitchRow(
                      '开发者模式',
                      '启用后可自定义启动命令、查看SSH终端输出',
                      _developerMode,
                      (v) => setState(() => _developerMode = v),
                    ),
                    if (_developerMode) ...[
                      Divider(color: Colors.white.withOpacity(0.1), height: 24),
                      Text(
                        '自定义一键启动命令',
                        style: TextStyle(
                          color: Colors.cyanAccent,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        '留空则使用默认命令：cd ~/rk3588_car_project/rk3588_backend && nohup bash start.sh > /tmp/car_backend.log 2>&1 &',
                        style: TextStyle(
                          color: Colors.grey.withOpacity(0.7),
                          fontSize: 11,
                        ),
                      ),
                      SizedBox(height: 10),
                      TextField(
                        controller: _commandController,
                        maxLines: 4,
                        style: TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'monospace'),
                        decoration: InputDecoration(
                          hintText: '输入自定义命令...',
                          hintStyle: TextStyle(color: Colors.grey.withOpacity(0.5), fontSize: 12),
                          filled: true,
                          fillColor: Colors.black.withOpacity(0.3),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.cyanAccent.withOpacity(0.3)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.cyanAccent),
                          ),
                          contentPadding: EdgeInsets.all(12),
                        ),
                      ),
                      SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: SshService.isConnected ? _openTerminal : null,
                          icon: Icon(Icons.terminal, size: 18),
                          label: Text('查看 SSH 终端输出'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.purpleAccent.withOpacity(0.2),
                            foregroundColor: Colors.purpleAccent,
                            disabledBackgroundColor: Colors.grey.withOpacity(0.1),
                            disabledForegroundColor: Colors.grey,
                            side: BorderSide(
                              color: SshService.isConnected
                                  ? Colors.purpleAccent.withOpacity(0.5)
                                  : Colors.grey.withOpacity(0.2),
                            ),
                            padding: EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                      if (!SshService.isConnected)
                        Padding(
                          padding: EdgeInsets.only(top: 6),
                          child: Text(
                            '需先建立 SSH 连接',
                            style: TextStyle(color: Colors.grey.withOpacity(0.5), fontSize: 11),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),

            SizedBox(height: 24),
            _buildSectionTitle('连接信息', Icons.info_outline),
            SizedBox(height: 12),
            GlassContainer(
              gradient: LinearGradient(
                colors: [
                  Colors.white.withOpacity(0.1),
                  Colors.white.withOpacity(0.05),
                ],
              ),
              blur: 20,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInfoRow('SSH 主机', SshService.host.isEmpty ? '未连接' : SshService.host),
                    SizedBox(height: 8),
                    _buildInfoRow('SSH 端口', SshService.port.toString()),
                    SizedBox(height: 8),
                    _buildInfoRow('用户名', SshService.username.isEmpty ? '未连接' : SshService.username),
                    SizedBox(height: 8),
                    _buildInfoRow('连接状态', SshService.isConnected ? '已连接 ✅' : '未连接 ❌'),
                  ],
                ),
              ),
            ),

            SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _saveSettings,
                icon: _isSaving
                    ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                    : Icon(Icons.save, size: 18),
                label: Text(_isSaving ? '保存中...' : '保存设置'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.cyanAccent,
                  foregroundColor: Colors.black,
                  disabledBackgroundColor: Colors.grey.withOpacity(0.2),
                  padding: EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSwitchRow(String title, String subtitle, bool value, ValueChanged<bool> onChanged) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: Colors.cyanAccent,
          activeTrackColor: Colors.cyanAccent.withOpacity(0.3),
        ),
      ],
    );
  }

  Widget _buildPidRow(Map<String, dynamic> cfg) {
    final key = '${cfg['motor']}_${cfg['pid_type']}';
    return Padding(
      padding: EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            cfg['label'] as String,
            style: TextStyle(
              color: Colors.cyanAccent,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildPidField(_pidKp[key]!, 'Kp'),
              ),
              SizedBox(width: 8),
              Expanded(
                child: _buildPidField(_pidKi[key]!, 'Ki'),
              ),
              SizedBox(width: 8),
              Expanded(
                child: _buildPidField(_pidKd[key]!, 'Kd'),
              ),
              SizedBox(width: 8),
              SizedBox(
                height: 40,
                child: ElevatedButton(
                  onPressed: () => _applyPid(cfg),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.cyanAccent,
                    foregroundColor: Colors.black,
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text('应用', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPidField(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.numberWithOptions(decimal: true),
      style: TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey, fontSize: 11),
        filled: true,
        fillColor: Colors.black.withOpacity(0.2),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.cyanAccent.withOpacity(0.2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.cyanAccent),
        ),
        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Colors.cyanAccent, size: 18),
        SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            color: Colors.cyanAccent,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
        Spacer(),
        Text(
          value,
          style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}
