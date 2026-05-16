import 'package:flutter/material.dart';
import 'package:glassmorphism_ui/glassmorphism_ui.dart';
import 'package:provider/provider.dart';
import '../providers/robot_provider.dart';
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
                  ? Colors.green.withValues(alpha:0.2)
                  : Colors.red.withValues(alpha:0.2),
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

            // === 灯光控制 ===
            _buildSection(
              icon: Icons.lightbulb,
              title: '情感灯光系统',
              child: LightControl(),
            ),
            SizedBox(height: 16),

            // === 电机状态 ===
            _buildSection(
              icon: Icons.electrical_services,
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
          Colors.white.withValues(alpha:0.1),
          Colors.white.withValues(alpha:0.05),
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
            colors: [color.withValues(alpha:0.3), color.withValues(alpha:0.1)],
          ),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha:0.5)),
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
        Divider(color: Colors.white.withValues(alpha:0.1)),
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
                  borderSide: BorderSide(color: Colors.cyanAccent.withValues(alpha:0.3)),
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
