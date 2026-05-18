import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:glassmorphism_ui/glassmorphism_ui.dart';
import 'package:provider/provider.dart';
import '../providers/robot_provider.dart';
import '../widgets/video_stream_widget.dart';
import '../widgets/joystick_control.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({Key? key}) : super(key: key);

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    // Lock to landscape
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    // Hide system UI for immersive experience
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    // Restore orientations when leaving
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RobotProvider>();
    final state = provider.state;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // === Full-screen video stream ===
          VideoStreamWidget(fit: BoxFit.cover, fullscreen: true),

          // === Tap to toggle controls ===
          GestureDetector(
            onTap: _toggleControls,
            child: Container(color: Colors.transparent),
          ),

          // === Top HUD Bar ===
          if (_showControls) _buildTopHud(provider, state),

          // === Bottom-left: Joystick overlay ===
          if (_showControls)
            Positioned(
              left: 20,
              bottom: 20,
              child: _buildJoystickOverlay(),
            ),

          // === Bottom-right: Quick actions ===
          if (_showControls)
            Positioned(
              right: 20,
              bottom: 20,
              child: _buildQuickActionsOverlay(context),
            ),

          // === Right side: Mode & Servo ===
          if (_showControls)
            Positioned(
              right: 20,
              top: 80,
              child: _buildRightPanel(context, provider),
            ),

          // === Center bottom: Servo slider (when expanded) ===
          if (_showControls)
            Positioned(
              left: MediaQuery.of(context).size.width * 0.25,
              right: MediaQuery.of(context).size.width * 0.25,
              bottom: 20,
              child: _buildServoOverlay(context, provider),
            ),

          // === Connection indicator (always visible) ===
          Positioned(
            top: 12,
            left: 12,
            child: _buildConnectionBadge(provider.connected),
          ),
        ],
      ),
    );
  }

  Widget _buildTopHud(RobotProvider provider, Map<String, dynamic> state) {
    final speed = (state['speed'] as num?)?.toDouble() ?? 0;
    final battery = (state['battery'] as num?)?.toDouble() ?? 0;
    final mode = state['mode'] as String? ?? 'manual';
    final yaw = ((state['imu'] as Map<String, dynamic>?)?['yaw'] as num?)?.toDouble() ?? 0;

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withOpacity(0.7),
                Colors.transparent,
              ],
            ),
          ),
          child: Row(
            children: [
              // Back button
              IconButton(
                icon: Icon(Icons.arrow_back, color: Colors.white, size: 20),
                onPressed: () {
                  Navigator.of(context).pop();
                },
                padding: EdgeInsets.zero,
                constraints: BoxConstraints(),
              ),
              SizedBox(width: 12),
              // Speed
              _buildHudItem(Icons.speed, '${speed.toStringAsFixed(1)} cm/s', Colors.cyanAccent),
              SizedBox(width: 16),
              // Battery
              _buildHudItem(
                battery > 30 ? Icons.battery_full : Icons.battery_alert,
                '${battery.toStringAsFixed(0)}%',
                battery > 30 ? Colors.green : Colors.red,
              ),
              SizedBox(width: 16),
              // Mode
              _buildHudItem(Icons.auto_mode, mode.toUpperCase(), Colors.purpleAccent),
              SizedBox(width: 16),
              // Yaw
              _buildHudItem(Icons.compass_calibration, '${yaw.toStringAsFixed(1)}°', Colors.orangeAccent),
              Spacer(),
              // Toggle controls hint
              Text(
                '点击画面${_showControls ? '隐藏' : '显示'}控件',
                style: TextStyle(color: Colors.white54, fontSize: 10),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHudItem(IconData icon, String text, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 14),
        SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildJoystickOverlay() {
    return GlassContainer(
      gradient: LinearGradient(
        colors: [
          Colors.black.withOpacity(0.4),
          Colors.black.withOpacity(0.2),
        ],
      ),
      blur: 10,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: EdgeInsets.all(12),
        child: JoystickControl(size: 120),
      ),
    );
  }

  Widget _buildQuickActionsOverlay(BuildContext context) {
    return GlassContainer(
      gradient: LinearGradient(
        colors: [
          Colors.black.withOpacity(0.4),
          Colors.black.withOpacity(0.2),
        ],
      ),
      blur: 10,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildActionIcon(
              context,
              Icons.play_arrow,
              Colors.green,
              '使能',
              () => context.read<RobotProvider>().motorEnable(),
            ),
            SizedBox(height: 8),
            _buildActionIcon(
              context,
              Icons.stop,
              Colors.red,
              '急停',
              () => context.read<RobotProvider>().motorStop(),
            ),
            SizedBox(height: 8),
            _buildActionIcon(
              context,
              Icons.home,
              Colors.orange,
              '回零',
              () => context.read<RobotProvider>().motorHome(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionIcon(
    BuildContext context,
    IconData icon,
    Color color,
    String label,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color.withOpacity(0.2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.5)),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
    );
  }

  Widget _buildRightPanel(BuildContext context, RobotProvider provider) {
    final isTrackMode = provider.mode == 'track';
    final servoAngle = (provider.state['servo']?['angle_percent'] as num?)?.toDouble() ?? 0;

    return GlassContainer(
      gradient: LinearGradient(
        colors: [
          Colors.black.withOpacity(0.4),
          Colors.black.withOpacity(0.2),
        ],
      ),
      blur: 10,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Mode toggle
            _buildModeButton(
              context,
              isTrackMode ? Icons.stop : Icons.route,
              isTrackMode ? Colors.red : Colors.green,
              isTrackMode ? '停止巡线' : '开始巡线',
              () {
                if (isTrackMode) {
                  provider.stopTracking();
                } else {
                  provider.startTracking();
                }
              },
            ),
            SizedBox(height: 8),
            // Emotions
            Wrap(
              spacing: 6,
              runSpacing: 6,
              alignment: WrapAlignment.end,
              children: [
                _buildMiniIcon(Icons.sentiment_neutral, 'neutral', provider),
                _buildMiniIcon(Icons.sentiment_very_satisfied, 'happy', provider),
                _buildMiniIcon(Icons.sentiment_satisfied, 'cool', provider),
                _buildMiniIcon(Icons.bedtime, 'sleepy', provider),
              ],
            ),
            SizedBox(height: 8),
            // Light toggle
            _buildModeButton(
              context,
              Icons.lightbulb,
              Colors.yellow,
              '灯光',
              () => provider.setLight('blue', 'solid'),
            ),
            SizedBox(height: 8),
            // Servo angle display
            Text(
              '舵机 ${servoAngle.toStringAsFixed(0)}%',
              style: TextStyle(color: Colors.white70, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniIcon(IconData icon, String emotion, RobotProvider provider) {
    return GestureDetector(
      onTap: () => provider.setDisplayEmotion(emotion),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: Colors.purpleAccent.withOpacity(0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.purpleAccent.withOpacity(0.4)),
        ),
        child: Icon(icon, color: Colors.purpleAccent, size: 16),
      ),
    );
  }

  Widget _buildModeButton(
    BuildContext context,
    IconData icon,
    Color color,
    String label,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color.withOpacity(0.3), color.withOpacity(0.1)],
          ),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 14),
            SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(color: Colors.white, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServoOverlay(BuildContext context, RobotProvider provider) {
    final servoAngle = (provider.state['servo']?['angle_percent'] as num?)?.toDouble() ?? 0;

    return GlassContainer(
      gradient: LinearGradient(
        colors: [
          Colors.black.withOpacity(0.3),
          Colors.black.withOpacity(0.15),
        ],
      ),
      blur: 8,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Text('L', style: TextStyle(color: Colors.grey, fontSize: 10)),
            Expanded(
              child: Slider(
                value: servoAngle,
                min: -100,
                max: 100,
                divisions: 20,
                activeColor: Colors.cyanAccent,
                inactiveColor: Colors.cyanAccent.withOpacity(0.2),
                onChanged: (v) => provider.setServo(v),
                onChangeEnd: (_) => provider.centerServo(),
              ),
            ),
            Text('R', style: TextStyle(color: Colors.grey, fontSize: 10)),
            SizedBox(width: 8),
            GestureDetector(
              onTap: () => provider.centerServo(),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.green.withOpacity(0.5)),
                ),
                child: Text('回中', style: TextStyle(color: Colors.green, fontSize: 10)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionBadge(bool connected) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: connected ? Colors.green.withOpacity(0.8) : Colors.red.withOpacity(0.8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: 4),
          Text(
            connected ? '已连接' : '未连接',
            style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
