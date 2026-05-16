import 'package:flutter/material.dart';
import 'package:glassmorphism_ui/glassmorphism_ui.dart';
import 'package:provider/provider.dart';
import '../providers/robot_provider.dart';
import '../screens/connection_screen.dart';
import '../widgets/video_stream_widget.dart';
import '../widgets/dashboard_widget.dart';
import '../widgets/joystick_control.dart';
import '../widgets/mode_buttons.dart';
import '../widgets/light_control.dart';

class MainScreen extends StatelessWidget {
  const MainScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RobotProvider>();

    return Scaffold(
      backgroundColor: Color(0xFF0A0E21),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.white70),
          onPressed: () {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => ConnectionScreen()),
            );
          },
        ),
        title: Row(
          children: [
            Icon(Icons.memory, color: Colors.cyanAccent),
            SizedBox(width: 8),
            Text(
              '智能小车控制中枢',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          // Connection status
          Container(
            margin: EdgeInsets.only(right: 8),
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: provider.connected
                  ? Colors.green.withOpacity(0.2)
                  : Colors.red.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: provider.connected ? Colors.green : Colors.red,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: provider.connected ? Colors.green : Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
                SizedBox(width: 6),
                Text(
                  provider.connected ? '已连接' : '未连接',
                  style: TextStyle(
                    color: provider.connected ? Colors.green : Colors.red,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          // Settings
          IconButton(
            icon: Icon(Icons.settings, color: Colors.white70),
            onPressed: () => _showSettings(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // === 视频流区域 ===
            _buildSection(
              icon: Icons.videocam,
              title: 'AI视觉实时流',
              child: VideoStreamWidget(),
            ),
            SizedBox(height: 16),

            // === 仪表盘区域 ===
            _buildSection(
              icon: Icons.speed,
              title: '数字孪生仪表盘',
              child: DashboardWidget(),
            ),
            SizedBox(height: 16),

            // === 控制区域 ===
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 摇杆
                Expanded(
                  child: _buildSection(
                    icon: Icons.gamepad,
                    title: '运动控制',
                    child: Center(child: JoystickControl()),
                  ),
                ),
                SizedBox(width: 16),
                // 快捷按钮
                Expanded(
                  child: _buildSection(
                    icon: Icons.touch_app,
                    title: '快捷操作',
                    child: _buildQuickActions(context),
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),

            // === 模式切换 ===
            _buildSection(
              icon: Icons.auto_mode,
              title: '智能模式',
              child: ModeButtons(),
            ),
            SizedBox(height: 16),

            // === 舵机控制 ===
            _buildSection(
              icon: Icons.rotate_right,
              title: '舵机转向控制',
              child: _buildServoControl(context),
            ),
            SizedBox(height: 16),

            // === 表情显示 ===
            _buildSection(
              icon: Icons.emoji_emotions,
              title: '表情显示控制',
              child: _buildEmotionControl(context),
            ),
            SizedBox(height: 16),

            // === 巡线模式 ===
            _buildSection(
              icon: Icons.route,
              title: '8路巡线模块',
              child: _buildTrackingControl(context),
            ),
            SizedBox(height: 16),

            // === 灯光控制 ===
            _buildSection(
              icon: Icons.lightbulb,
              title: '情感灯光系统',
              child: LightControl(),
            ),
            SizedBox(height: 16),

            // === 电机状态 ===
            _buildSection(
              icon: Icons.electric_motor,
              title: '电机状态',
              child: _buildMotorStatus(context),
            ),
            SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    return GlassContainer(
      gradient: LinearGradient(
        colors: [
          Colors.white.withOpacity(0.1),
          Colors.white.withOpacity(0.05),
        ],
      ),
      blur: 20,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
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
            ),
            SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    return Column(
      children: [
        _buildActionButton(
          context,
          icon: Icons.play_arrow,
          label: '使能',
          color: Colors.green,
          onTap: () => context.read<RobotProvider>().motorEnable(),
        ),
        SizedBox(height: 8),
        _buildActionButton(
          context,
          icon: Icons.stop,
          label: '急停',
          color: Colors.red,
          onTap: () => context.read<RobotProvider>().motorStop(),
        ),
        SizedBox(height: 8),
        _buildActionButton(
          context,
          icon: Icons.home,
          label: '回零',
          color: Colors.orange,
          onTap: () => context.read<RobotProvider>().motorHome(),
        ),
        SizedBox(height: 8),
        _buildActionButton(
          context,
          icon: Icons.power_settings_new,
          label: '失能',
          color: Colors.grey,
          onTap: () => context.read<RobotProvider>().motorDisable(),
        ),
      ],
    );
  }

  Widget _buildActionButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color.withOpacity(0.3), color.withOpacity(0.1)],
          ),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.5)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 18),
            SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMotorStatus(BuildContext context) {
    final state = context.watch<RobotProvider>().state;
    final motor1 = state['motor1'] as Map<String, dynamic>? ?? {};
    final motor2 = state['motor2'] as Map<String, dynamic>? ?? {};

    return Column(
      children: [
        _buildMotorRow('电机1', motor1),
        SizedBox(height: 8),
        Divider(color: Colors.white.withOpacity(0.1)),
        SizedBox(height: 8),
        _buildMotorRow('电机2', motor2),
      ],
    );
  }

  Widget _buildMotorRow(String name, Map<String, dynamic> data) {
    final speed = (data['speed'] as num?)?.toDouble() ?? 0;
    final angle = (data['angle'] as num?)?.toDouble() ?? 0;
    final pwm = (data['pwm'] as num?)?.toDouble() ?? 0;

    return Row(
      children: [
        Expanded(
          child: Text(
            name,
            style: TextStyle(
              color: Colors.white70,
              fontSize: 13,
            ),
          ),
        ),
        _buildMotorStat('速度', '${speed.toStringAsFixed(1)} rad/s'),
        SizedBox(width: 12),
        _buildMotorStat('角度', '${angle.toStringAsFixed(1)} rad'),
        SizedBox(width: 12),
        _buildMotorStat('PWM', '${pwm.toStringAsFixed(0)}'),
      ],
    );
  }

  Widget _buildMotorStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          value,
          style: TextStyle(
            color: Colors.cyanAccent,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.grey,
            fontSize: 9,
          ),
        ),
      ],
    );
  }

  Widget _buildServoControl(BuildContext context) {
    final servoAngle = (context.watch<RobotProvider>().state['servo']?['angle_percent'] as num?)?.toDouble() ?? 0;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('左', style: TextStyle(color: Colors.grey, fontSize: 12)),
            Text('${servoAngle.toStringAsFixed(0)}%', style: TextStyle(color: Colors.cyanAccent, fontSize: 14, fontWeight: FontWeight.bold)),
            Text('右', style: TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
        SizedBox(height: 8),
        Slider(
          value: servoAngle,
          min: -100,
          max: 100,
          divisions: 20,
          activeColor: Colors.cyanAccent,
          inactiveColor: Colors.cyanAccent.withOpacity(0.2),
          onChanged: (v) => context.read<RobotProvider>().setServo(v),
          onChangeEnd: (_) => context.read<RobotProvider>().centerServo(),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildMiniActionButton('左转45°', Colors.orange, () => context.read<RobotProvider>().setServo(-45)),
            _buildMiniActionButton('回中', Colors.green, () => context.read<RobotProvider>().centerServo()),
            _buildMiniActionButton('右转45°', Colors.orange, () => context.read<RobotProvider>().setServo(45)),
          ],
        ),
      ],
    );
  }

  Widget _buildEmotionControl(BuildContext context) {
    final emotions = [
      {'name': ' neutral', 'value': 'neutral', 'icon': Icons.sentiment_neutral},
      {'name': '开心', 'value': 'happy', 'icon': Icons.sentiment_very_satisfied},
      {'name': '困', 'value': 'sleepy', 'icon': Icons.bedtime},
      {'name': '惊讶', 'value': 'surprised', 'icon': Icons.sentiment_very_dissatisfied},
      {'name': '酷', 'value': 'cool', 'icon': Icons.sentiment_cool},
      {'name': '爱心', 'value': 'love', 'icon': Icons.favorite},
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: emotions.map((e) {
        return GestureDetector(
          onTap: () => context.read<RobotProvider>().setDisplayEmotion(e['value'] as String),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.purpleAccent.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.purpleAccent.withOpacity(0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(e['icon'] as IconData, color: Colors.purpleAccent, size: 16),
                SizedBox(width: 4),
                Text(e['name'] as String, style: TextStyle(color: Colors.white, fontSize: 12)),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTrackingControl(BuildContext context) {
    final trackData = context.watch<RobotProvider>().state['tracking'] as Map<String, dynamic>?;
    final irData = trackData?['ir_data'] as List<dynamic>?;
    final error = (trackData?['error'] as num?)?.toInt() ?? 0;
    final connected = trackData?['connected'] == true;
    final isTrackMode = context.watch<RobotProvider>().mode == 'track';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (irData != null && irData.length == 8)
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: irData.asMap().entries.map((entry) {
                final active = entry.value == 0; // 0 = line detected
                return Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: active ? Colors.green : Colors.grey.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: active ? Colors.greenAccent : Colors.grey,
                      width: active ? 2 : 1,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      '${entry.key + 1}',
                      style: TextStyle(
                        color: active ? Colors.black : Colors.white70,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Text(
                connected ? '模块在线 | 偏差: $error' : '模块离线',
                style: TextStyle(color: connected ? Colors.green : Colors.grey, fontSize: 12),
              ),
            ),
            GestureDetector(
              onTap: () {
                if (isTrackMode) {
                  context.read<RobotProvider>().stopTracking();
                } else {
                  context.read<RobotProvider>().startTracking();
                }
              },
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isTrackMode
                        ? [Colors.red.withOpacity(0.6), Colors.red.withOpacity(0.3)]
                        : [Colors.green.withOpacity(0.6), Colors.green.withOpacity(0.3)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: isTrackMode ? Colors.red : Colors.green),
                ),
                child: Text(
                  isTrackMode ? '停止巡线' : '开始巡线',
                  style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMiniActionButton(String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.2),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.5)),
        ),
        child: Text(
          label,
          style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }

  void _showSettings(BuildContext context) {
    final provider = context.read<RobotProvider>();
    final controller = TextEditingController(text: provider.serverIp);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Color(0xFF1A1E2E),
        title: Text('设置', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              style: TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'RK3588S IP 地址',
                labelStyle: TextStyle(color: Colors.grey),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.cyanAccent.withOpacity(0.3)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.cyanAccent),
                ),
              ),
            ),
            SizedBox(height: 16),
            Text(
              '默认: 192.168.1.100',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              provider.setServerIp(controller.text);
              provider.connect();
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.cyanAccent,
            ),
            child: Text('保存并连接', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }
}
