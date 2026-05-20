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

  // Motor max speed / accel settings
  final _maxSpeedController = TextEditingController(text: '100');
  final _maxAccelController = TextEditingController(text: '10');

  // IMU live data cache
  Map<String, dynamic> _imuData = {};
  bool _imuLoading = false;
  String _imuVersion = '未知';

  // Calibration state
  bool _calibrating = false;
  String _calibrationStatus = '';

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
    _fetchImuData();
    _fetchImuVersion();
  }

  @override
  void dispose() {
    _commandController.dispose();
    _maxSpeedController.dispose();
    _maxAccelController.dispose();
    for (final c in _pidKp.values) c.dispose();
    for (final c in _pidKi.values) c.dispose();
    for (final c in _pidKd.values) c.dispose();
    super.dispose();
  }

  Future<void> _fetchImuData() async {
    setState(() => _imuLoading = true);
    try {
      final result = await ApiService.getImu();
      if (result['success'] == true && result['data'] != null) {
        setState(() => _imuData = result['data'] as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('Fetch IMU error: $e');
    } finally {
      setState(() => _imuLoading = false);
    }
  }

  Future<void> _fetchImuVersion() async {
    try {
      final result = await ApiService.getImuVersion();
      if (result['success'] == true) {
        setState(() => _imuVersion = result['version']?.toString() ?? '未知');
      }
    } catch (e) {
      debugPrint('Fetch IMU version error: $e');
    }
  }

  Future<void> _startCalibration(String type, {double? temperature}) async {
    setState(() {
      _calibrating = true;
      _calibrationStatus = '正在校准 $type...';
    });
    try {
      final result = await ApiService.calibrateImu(type, temperature: temperature);
      if (result['success'] == true) {
        setState(() => _calibrationStatus = '$type 校准已启动');
        // Poll status every 1s for up to 10s
        for (var i = 0; i < 10; i++) {
          await Future.delayed(Duration(seconds: 1));
          final status = await ApiService.getImuCalibrationStatus();
          if (status['running'] == false && status['result'] != null) {
            final res = status['result'] as Map<String, dynamic>;
            setState(() => _calibrationStatus = res['success'] == true
                ? '$type 校准成功 ✅'
                : '$type 校准失败 ❌ (${res['error'] ?? 'unknown'})');
            break;
          }
        }
      } else {
        setState(() => _calibrationStatus = '校准启动失败: ${result['error'] ?? 'unknown'}');
      }
    } catch (e) {
      setState(() => _calibrationStatus = '校准异常: $e');
    } finally {
      setState(() => _calibrating = false);
    }
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

            // ── Motor Max Speed / Accel ──
            _buildSectionTitle('电机限制设置', Icons.speed),
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
                      '全局限制值，应用到两个电机',
                      style: TextStyle(color: Colors.grey.withOpacity(0.8), fontSize: 11),
                    ),
                    SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildNumberField(_maxSpeedController, '最大速度', 'cm/s'),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: _buildNumberField(_maxAccelController, '最大加速度', 'cm/s²'),
                        ),
                      ],
                    ),
                    SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final maxSpeed = double.tryParse(_maxSpeedController.text) ?? 100;
                          final maxAccel = double.tryParse(_maxAccelController.text) ?? 10;
                          // Apply to both motors: speed mode (0) with max limits
                          await ApiService.setMotorTarget(motor: 0, mode: 0, speed: maxSpeed, accel: maxAccel, decel: maxAccel);
                          await ApiService.setMotorTarget(motor: 1, mode: 0, speed: maxSpeed, accel: maxAccel, decel: maxAccel);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('电机限制已应用: 速度 ${maxSpeed.toStringAsFixed(0)} cm/s, 加速度 ${maxAccel.toStringAsFixed(0)} cm/s²', style: TextStyle(color: Colors.white)),
                                backgroundColor: Colors.cyanAccent.withOpacity(0.8),
                                duration: Duration(seconds: 1),
                              ),
                            );
                          }
                        },
                        icon: Icon(Icons.send, size: 16),
                        label: Text('应用限制'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.cyanAccent,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            SizedBox(height: 24),

            // ── IMU Data & Calibration ──
            _buildSectionTitle('IMU 数据与校准', Icons.sensors),
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('固件版本: $_imuVersion', style: TextStyle(color: Colors.white70, fontSize: 12)),
                        SizedBox(
                          height: 28,
                          child: ElevatedButton.icon(
                            onPressed: _imuLoading ? null : _fetchImuData,
                            icon: _imuLoading
                                ? SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.cyanAccent))
                                : Icon(Icons.refresh, size: 14),
                            label: Text('刷新', style: TextStyle(fontSize: 11)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.cyanAccent.withOpacity(0.15),
                              foregroundColor: Colors.cyanAccent,
                              padding: EdgeInsets.symmetric(horizontal: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 12),
                    _buildImuDataPanel(),
                    SizedBox(height: 16),
                    if (_calibrationStatus.isNotEmpty)
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.cyanAccent.withOpacity(0.3)),
                        ),
                        child: Text(
                          _calibrationStatus,
                          style: TextStyle(color: Colors.cyanAccent, fontSize: 12),
                        ),
                      ),
                    SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildCalibButton('IMU 校准', 'imu', Icons.sensors, Colors.orangeAccent),
                        _buildCalibButton('磁力计', 'mag', Icons.explore, Colors.purpleAccent),
                        _buildCalibButton('温度校准', 'temp', Icons.thermostat, Colors.redAccent),
                        _buildCalibButton('重置数据', 'reset', Icons.restore, Colors.grey),
                      ],
                    ),
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

  Widget _buildNumberField(TextEditingController controller, String label, String unit) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.numberWithOptions(decimal: true),
      style: TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        labelText: '$label ($unit)',
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

  Widget _buildImuDataPanel() {
    if (_imuData.isEmpty) {
      return Text(
        '暂无 IMU 数据，点击刷新获取',
        style: TextStyle(color: Colors.grey.withOpacity(0.7), fontSize: 12),
      );
    }
    final euler = _imuData['euler'] as Map<String, dynamic>? ?? {};
    final accel = _imuData['accelerometer'] as Map<String, dynamic>? ?? {};
    final gyro = _imuData['gyroscope'] as Map<String, dynamic>? ?? {};
    final mag = _imuData['magnetometer'] as Map<String, dynamic>? ?? {};
    final quat = _imuData['quaternion'] as Map<String, dynamic>? ?? {};
    final baro = _imuData['barometer'] as Map<String, dynamic>? ?? {};
    return Container(
      padding: EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (euler.isNotEmpty)
            _buildImuRow('欧拉角', 'Pitch ${euler['pitch']?.toStringAsFixed(1) ?? '-'}°  '
                'Roll ${euler['roll']?.toStringAsFixed(1) ?? '-'}°  '
                'Yaw ${euler['yaw']?.toStringAsFixed(1) ?? '-'}°'),
          if (accel.isNotEmpty)
            _buildImuRow('加速度', 'X ${accel['x']?.toStringAsFixed(2) ?? '-'}  Y ${accel['y']?.toStringAsFixed(2) ?? '-'}  Z ${accel['z']?.toStringAsFixed(2) ?? '-'}'),
          if (gyro.isNotEmpty)
            _buildImuRow('陀螺仪', 'X ${gyro['x']?.toStringAsFixed(2) ?? '-'}  Y ${gyro['y']?.toStringAsFixed(2) ?? '-'}  Z ${gyro['z']?.toStringAsFixed(2) ?? '-'}'),
          if (mag.isNotEmpty)
            _buildImuRow('磁力计', 'X ${mag['x']?.toStringAsFixed(0) ?? '-'}  Y ${mag['y']?.toStringAsFixed(0) ?? '-'}  Z ${mag['z']?.toStringAsFixed(0) ?? '-'}'),
          if (quat.isNotEmpty)
            _buildImuRow('四元数', 'W ${quat['w']?.toStringAsFixed(3) ?? '-'}  X ${quat['x']?.toStringAsFixed(3) ?? '-'}  Y ${quat['y']?.toStringAsFixed(3) ?? '-'}  Z ${quat['z']?.toStringAsFixed(3) ?? '-'}'),
          if (baro.isNotEmpty)
            _buildImuRow('气压', '${baro['pressure']?.toStringAsFixed(1) ?? '-'} hPa  ${baro['temperature']?.toStringAsFixed(1) ?? '-'} °C'),
        ],
      ),
    );
  }

  Widget _buildImuRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 56,
            child: Text(label, style: TextStyle(color: Colors.cyanAccent, fontSize: 11, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(value, style: TextStyle(color: Colors.white70, fontSize: 11, fontFamily: 'monospace')),
          ),
        ],
      ),
    );
  }

  Widget _buildCalibButton(String label, String type, IconData icon, Color color) {
    return ElevatedButton.icon(
      onPressed: _calibrating ? null : () => _startCalibration(type),
      icon: Icon(icon, size: 14),
      label: Text(label, style: TextStyle(fontSize: 11)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color.withOpacity(0.15),
        foregroundColor: color,
        disabledBackgroundColor: Colors.grey.withOpacity(0.1),
        disabledForegroundColor: Colors.grey,
        side: BorderSide(color: _calibrating ? Colors.grey.withOpacity(0.2) : color.withOpacity(0.4)),
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        elevation: 0,
      ),
    );
  }
}
