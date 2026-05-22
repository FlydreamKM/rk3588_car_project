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
  bool _showHudSettings = false;
  bool _showEmotions = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    // Load camera presets after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RobotProvider>().loadCameraInfo();
    });
  }

  @override
  void dispose() {
    try {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } catch (e) {
      debugPrint('SystemChrome restore error: $e');
    }
    super.dispose();
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
      _showHudSettings = false;
    });
  }

  void _toggleHudSettings() {
    setState(() {
      _showHudSettings = !_showHudSettings;
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RobotProvider>();
    final state = provider.state;
    final hudOpacity = provider.hudOpacity;
    final hudScale = provider.hudScale;
    final screenW = MediaQuery.of(context).size.width;
    final screenH = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
  // === Full-screen video stream (wrapped with tap toggle) ===
          GestureDetector(
            onTap: () {
              if (_showHudSettings) {
                setState(() => _showHudSettings = false);
              } else {
                _toggleControls();
              }
            },
            child: VideoStreamWidget(fit: BoxFit.cover, fullscreen: true),
          ),

          // === Top HUD Bar ===
          if (_showControls) _buildTopHud(provider, state, hudOpacity, hudScale),

          // === Resolution picker (above video, avoids tap conflict) ===
          if (_showControls)
            Positioned(
              top: 56,
              left: 16,
              child: ResolutionPicker(),
            ),

          // === Bottom-left: Joystick overlay ===
          if (_showControls)
            Positioned(
              left: 20,
              bottom: 20,
              child: Transform.scale(
                scale: hudScale,
                alignment: Alignment.bottomLeft,
                child: _buildJoystickOverlay(),
              ),
            ),

          // === Bottom-right: Quick actions ===
          if (_showControls)
            Positioned(
              right: 20,
              bottom: 20,
              child: Transform.scale(
                scale: hudScale,
                alignment: Alignment.bottomRight,
                child: _buildQuickActionsOverlay(context),
              ),
            ),

          // === Right side: Mode & Servo ===
          if (_showControls)
            Positioned(
              right: 20,
              top: 80,
              child: Transform.scale(
                scale: hudScale,
                alignment: Alignment.topRight,
                child: _buildRightPanel(context, provider),
              ),
            ),

          // === Connection indicator (always visible) ===
          Positioned(
            top: 12,
            left: 12,
            child: _buildConnectionBadge(provider.connected),
          ),

          // === HUD Settings overlay (LAST = true topmost layer) ===
          if (_showControls && _showHudSettings)
            Positioned(
              top: 56,
              right: 12,
              child: Transform.scale(
                scale: provider.hudScale,
                alignment: Alignment.topRight,
                child: _buildHudSettingsPanel(provider, screenW, screenH),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTopHud(RobotProvider provider, Map<String, dynamic> state, double opacity, double scale) {
    final speed = (state['speed'] as num?)?.toDouble() ?? 0;
    final battery = (state['battery'] as num?)?.toDouble() ?? 0;
    final mode = state['mode'] as String? ?? 'manual';
    final yaw = ((state['imu'] as Map<String, dynamic>?)?['yaw'] as num?)?.toDouble() ?? 0;
    final fps = ((state['camera'] as Map<String, dynamic>?)?['fps'] as num?)?.toDouble() ?? 0;

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
                Colors.black.withOpacity(opacity),
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
              _buildHudItem(Icons.speed, '${speed.toStringAsFixed(1)} cm/s', Colors.cyanAccent, scale),
              SizedBox(width: 12),
              // Battery
              _buildHudItem(
                battery > 30 ? Icons.battery_full : Icons.battery_alert,
                '${battery.toStringAsFixed(0)}%',
                battery > 30 ? Colors.green : Colors.red,
                scale,
              ),
              SizedBox(width: 12),
              // FPS
              _buildHudItem(Icons.videocam, '${fps.toStringAsFixed(0)} FPS', Colors.orangeAccent, scale),
              SizedBox(width: 12),
              // Mode
              _buildHudItem(Icons.auto_mode, mode.toUpperCase(), Colors.purpleAccent, scale),
              SizedBox(width: 12),
              // Yaw
              _buildHudItem(Icons.compass_calibration, '${yaw.toStringAsFixed(1)}°', Colors.orangeAccent, scale),
              Spacer(),
              // HUD settings button
              GestureDetector(
                onTap: _toggleHudSettings,
                child: Container(
                  padding: EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: _showHudSettings ? Colors.cyanAccent.withOpacity(0.3) : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    _showHudSettings ? Icons.settings : Icons.settings_outlined,
                    color: Colors.white70,
                    size: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHudItem(IconData icon, String text, Color color, double scale) {
    return Transform.scale(
      scale: scale,
      child: Row(
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
      ),
    );
  }

  Widget _buildHudSettingsPanel(RobotProvider provider, double screenW, double screenH) {
    final panelW = (screenW > 0 && screenW < 500) ? screenW * 0.85 : 260.0;
    final maxH = screenH > 0 ? screenH * 0.75 : 300.0;

    return Container(
      width: panelW,
      height: maxH,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.90),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.cyanAccent.withOpacity(0.5), width: 2),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('HUD 设置', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
              SizedBox(height: 12),
              _buildHudToggle('电机数据', provider.showMotorHud, provider.setShowMotorHud),
              SizedBox(height: 6),
              _buildHudToggle('IMU 数据', provider.showImuHud, provider.setShowImuHud),
              SizedBox(height: 6),
              _buildHudToggle('3D 方块', provider.showCube3D, provider.setShowCube3D),
              if (provider.showCube3D) ...[
                Text('方块透明度 ${(provider.cubeOpacity * 100).toInt()}%', style: TextStyle(color: Colors.white70, fontSize: 10)),
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
              Divider(color: Colors.white.withOpacity(0.1), height: 16),
              Text('不透明度 ${(provider.hudOpacity * 100).toInt()}%', style: TextStyle(color: Colors.white70, fontSize: 11)),
              Slider(
                value: provider.hudOpacity,
                min: 0.3,
                max: 1.0,
                divisions: 14,
                activeColor: Colors.cyanAccent,
                inactiveColor: Colors.cyanAccent.withOpacity(0.2),
                onChanged: (v) => provider.setHudOpacity(v),
              ),
              SizedBox(height: 4),
              Text('缩放 ${(provider.hudScale * 100).toInt()}%', style: TextStyle(color: Colors.white70, fontSize: 11)),
              Slider(
                value: provider.hudScale,
                min: 0.5,
                max: 1.5,
                divisions: 20,
                activeColor: Colors.purpleAccent,
                inactiveColor: Colors.purpleAccent.withOpacity(0.2),
                onChanged: (v) => provider.setHudScale(v),
              ),
              Divider(color: Colors.white.withOpacity(0.1), height: 16),
              // Motor Limits
              Text('电机限制', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('速度限制 ${provider.motorSpeedLimit.toStringAsFixed(1)} rad/s', style: TextStyle(color: Colors.white70, fontSize: 10)),
              Slider(
                value: provider.motorSpeedLimit.clamp(0.0, 200.0),
                min: 0.0,
                max: 200.0,
                divisions: 200,
                activeColor: Colors.orangeAccent,
                inactiveColor: Colors.orangeAccent.withOpacity(0.2),
                onChanged: (v) => provider.setMotorSpeedLimit(v),
              ),
              Text('加速度限制 ${provider.motorAccelLimit.toStringAsFixed(1)} rad/s²', style: TextStyle(color: Colors.white70, fontSize: 10)),
              Slider(
                value: provider.motorAccelLimit.clamp(0.0, 200.0),
                min: 0.0,
                max: 200.0,
                divisions: 200,
                activeColor: Colors.orangeAccent,
                inactiveColor: Colors.orangeAccent.withOpacity(0.2),
                onChanged: (v) => provider.setMotorAccelLimit(v),
              ),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    // 仅保存到本地，不发送电机M指令
                    // 限制值由摇杆控制时自动应用
                    provider.setMotorSpeedLimit(provider.motorSpeedLimit);
                    provider.setMotorAccelLimit(provider.motorAccelLimit);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('电机限制已保存', style: TextStyle(color: Colors.white, fontSize: 12)),
                        backgroundColor: Colors.orangeAccent.withOpacity(0.8),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orangeAccent.withOpacity(0.3),
                    foregroundColor: Colors.orangeAccent,
                    padding: EdgeInsets.symmetric(vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text('应用限制', style: TextStyle(fontSize: 11)),
                ),
              ),
              Divider(color: Colors.white.withOpacity(0.1), height: 16),
              // PID
              Text('速度环 PID', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
              SizedBox(height: 4),
              _buildPidRow('Kp', provider.pidSpeed['kp']!, 0, 10, (v) => provider.setPidSpeed(kp: v, ki: provider.pidSpeed['ki']!, kd: provider.pidSpeed['kd']!)),
              _buildPidRow('Ki', provider.pidSpeed['ki']!, 0, 5, (v) => provider.setPidSpeed(kp: provider.pidSpeed['kp']!, ki: v, kd: provider.pidSpeed['kd']!)),
              _buildPidRow('Kd', provider.pidSpeed['kd']!, 0, 2, (v) => provider.setPidSpeed(kp: provider.pidSpeed['kp']!, ki: provider.pidSpeed['ki']!, kd: v)),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => provider.applyPid(255, 0),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.greenAccent.withOpacity(0.3),
                    foregroundColor: Colors.greenAccent,
                    padding: EdgeInsets.symmetric(vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text('应用速度环 PID', style: TextStyle(fontSize: 11)),
                ),
              ),
              SizedBox(height: 12),
              Text('位置环 PID', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
              SizedBox(height: 4),
              _buildPidRow('Kp', provider.pidPosition['kp']!, 0, 10, (v) => provider.setPidPosition(kp: v, ki: provider.pidPosition['ki']!, kd: provider.pidPosition['kd']!)),
              _buildPidRow('Ki', provider.pidPosition['ki']!, 0, 5, (v) => provider.setPidPosition(kp: provider.pidPosition['kp']!, ki: v, kd: provider.pidPosition['kd']!)),
              _buildPidRow('Kd', provider.pidPosition['kd']!, 0, 2, (v) => provider.setPidPosition(kp: provider.pidPosition['kp']!, ki: provider.pidPosition['ki']!, kd: v)),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => provider.applyPid(255, 1),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.greenAccent.withOpacity(0.3),
                    foregroundColor: Colors.greenAccent,
                    padding: EdgeInsets.symmetric(vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text('应用位置环 PID', style: TextStyle(fontSize: 11)),
                ),
              ),
              SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHudToggle(String label, bool value, ValueChanged<bool> onChanged) {
    return Row(
      children: [
        Expanded(
          child: Text(label, style: TextStyle(color: Colors.white70, fontSize: 12)),
        ),
        SizedBox(
          height: 28,
          child: Switch(
            value: value,
            onChanged: onChanged,
            activeColor: Colors.cyanAccent,
            activeTrackColor: Colors.cyanAccent.withOpacity(0.3),
          ),
        ),
      ],
    );
  }

  Widget _buildPidRow(String label, double value, double min, double max, ValueChanged<double> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label ${value.toStringAsFixed(2)}', style: TextStyle(color: Colors.white70, fontSize: 10)),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: ((max - min) * 100).toInt(),
          activeColor: Colors.greenAccent,
          inactiveColor: Colors.greenAccent.withOpacity(0.2),
          onChanged: onChanged,
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
    final emotions = [
      (Icons.sentiment_neutral, 'neutral', Colors.purpleAccent),
      (Icons.sentiment_very_satisfied, 'happy', Colors.greenAccent),
      (Icons.sentiment_dissatisfied, 'sad', Colors.blueAccent),
      (Icons.sentiment_very_dissatisfied, 'angry', Colors.redAccent),
      (Icons.sentiment_satisfied, 'surprised', Colors.orangeAccent),
      (Icons.bedtime, 'sleepy', Colors.indigoAccent),
      (Icons.favorite, 'love', Colors.pinkAccent),
      (Icons.sentiment_satisfied_alt, 'cool', Colors.cyanAccent),
    ];

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
            // Emotion toggle button
            GestureDetector(
              onTap: () => setState(() => _showEmotions = !_showEmotions),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.purpleAccent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.purpleAccent.withOpacity(0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.emoji_emotions, color: Colors.purpleAccent, size: 14),
                    SizedBox(width: 4),
                    Text(
                      _showEmotions ? '收起' : '表情',
                      style: TextStyle(color: Colors.white70, fontSize: 10),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 6),
            // Animated emotion selector
            AnimatedCrossFade(
              duration: Duration(milliseconds: 300),
              firstChild: SizedBox.shrink(),
              secondChild: Wrap(
                spacing: 6,
                runSpacing: 6,
                alignment: WrapAlignment.end,
                children: emotions.map((e) => _buildMiniIcon(e.$1, e.$2, provider, e.$3)).toList(),
              ),
              crossFadeState: _showEmotions ? CrossFadeState.showSecond : CrossFadeState.showFirst,
              sizeCurve: Curves.easeInOut,
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
            // Servo integrated hint
            Text(
              '舵机：摇杆左右控制',
              style: TextStyle(color: Colors.cyanAccent.withOpacity(0.7), fontSize: 9),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniIcon(IconData icon, String emotion, RobotProvider provider, Color color) {
    return GestureDetector(
      onTap: () => provider.setDisplayEmotion(emotion),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Icon(icon, color: color, size: 16),
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
