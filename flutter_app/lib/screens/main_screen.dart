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
      final provider = context.read<RobotProvider>();
      provider.loadCameraInfo();
      // Record screen size for adaptive layout
      final size = MediaQuery.of(context).size;
      provider.setScreenSize(size.width, size.height);
    });
  }

  @override
  void dispose() {
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
    final screenW = provider.screenWidth;
    final screenH = provider.screenHeight;

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
          if (_showControls) _buildTopHud(provider, state, hudOpacity, hudScale, screenW),

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
            _buildHudSettingsOverlay(provider, screenW, screenH),
        ],
      ),
    );
  }

  Widget _buildTopHud(RobotProvider provider, Map<String, dynamic> state, double opacity, double scale, double screenW) {
    final speed = (state['speed'] as num?)?.toDouble() ?? 0;
    final battery = (state['battery'] as num?)?.toDouble() ?? 0;
    final mode = state['mode'] as String? ?? 'manual';
    final yaw = ((state['imu'] as Map<String, dynamic>?) ?? {})['yaw'] as num? ?? 0;
    final fps = ((state['camera'] as Map<String, dynamic>?) ?? {})['fps'] as num? ?? 0;

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

  Widget _buildHudSettingsOverlay(RobotProvider provider, double screenW, double screenH) {
    // Adaptive width: if screen is narrow (< 500), use 85% width
    final panelW = (screenW > 0 && screenW < 500) ? screenW * 0.85 : 260.0;
    // Max height to avoid overflow: 75% of screen height
    final maxH = screenH > 0 ? screenH * 0.75 : 300.0;

    return Positioned(
      top: 56,
      right: 12,
      child: GlassContainer(
        gradient: LinearGradient(
          colors: [
            Colors.black.withOpacity(0.7),
            Colors.black.withOpacity(0.5),
          ],
        ),
        blur: 12,
        borderRadius: BorderRadius.circular(16),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: panelW,
            maxHeight: maxH,
          ),
          child: Padding(
            padding: EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('HUD 设置', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                  SizedBox(height: 12),
                  // Motor HUD toggle
                  _buildHudToggle('电机数据', provider.showMotorHud, provider.setShowMotorHud),
                  SizedBox(height: 6),
                  // IMU HUD toggle
                  _buildHudToggle('IMU 数据', provider.showImuHud, provider.setShowImuHud),
                  SizedBox(height: 6),
                  // 3D Cube toggle
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
                ],
              ),
            ),
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
            // Emotions expandable panel
            _buildEmotionPanel(provider),
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

  Widget _buildEmotionPanel(RobotProvider provider) {
    final emotions = [
      {'name': 'neutral', 'icon': Icons.sentiment_neutral, 'label': '平静'},
      {'name': 'happy', 'icon': Icons.sentiment_very_satisfied, 'label': '开心'},
      {'name': 'sad', 'icon': Icons.sentiment_dissatisfied, 'label': '难过'},
      {'name': 'angry', 'icon': Icons.sentiment_very_dissatisfied, 'label': '生气'},
      {'name': 'surprised', 'icon': Icons.sentiment_neutral, 'label': '惊讶'},
      {'name': 'sleepy', 'icon': Icons.bedtime, 'label': '困倦'},
      {'name': 'love', 'icon': Icons.favorite, 'label': '爱心'},
      {'name': 'cool', 'icon': Icons.sentiment_satisfied, 'label': '酷'},
    ];

    final expanded = provider.emotionExpanded;
    final current = provider.state['emotion'] as String? ?? 'neutral';
    final currentEmotion = emotions.firstWhere(
      (e) => e['name'] == current,
      orElse: () => emotions.first,
    );

    return GestureDetector(
      onTap: () => provider.setEmotionExpanded(!expanded),
      child: AnimatedContainer(
        duration: Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.purpleAccent.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.purpleAccent.withOpacity(0.4)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Header row: current emotion + expand arrow
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  color: Colors.purpleAccent,
                  size: 14,
                ),
                SizedBox(width: 4),
                Text(
                  '表情',
                  style: TextStyle(color: Colors.purpleAccent, fontSize: 11),
                ),
                SizedBox(width: 6),
                _buildMiniIcon(
                  currentEmotion['icon'] as IconData,
                  current,
                  provider,
                  isHeader: true,
                ),
              ],
            ),
            // Expandable emotion grid
            AnimatedSize(
              duration: Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              child: expanded
                  ? Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        alignment: WrapAlignment.end,
                        children: emotions.map((e) {
                          final name = e['name'] as String;
                          final icon = e['icon'] as IconData;
                          final isCurrent = name == current;
                          return GestureDetector(
                            onTap: () {
                              provider.setDisplayEmotion(name);
                              provider.setEmotionExpanded(false);
                            },
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: isCurrent
                                    ? Colors.purpleAccent.withOpacity(0.4)
                                    : Colors.purpleAccent.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isCurrent
                                      ? Colors.purpleAccent
                                      : Colors.purpleAccent.withOpacity(0.4),
                                ),
                              ),
                              child: Icon(icon, color: Colors.purpleAccent, size: 16),
                            ),
                          );
                        }).toList(),
                      ),
                    )
                  : SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniIcon(IconData icon, String emotion, RobotProvider provider, {bool isHeader = false}) {
    return GestureDetector(
      onTap: isHeader ? null : () => provider.setDisplayEmotion(emotion),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: Colors.purpleAccent.withOpacity(0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.purpleAccent.withOpacity(0.4)),
        ),
        child: Icon(icon, color: Colors.purpleAccent, size: 14),
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
