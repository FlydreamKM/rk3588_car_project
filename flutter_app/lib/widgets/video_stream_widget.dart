import 'package:flutter/material.dart';
import 'package:mjpeg_stream/mjpeg_stream.dart';
import 'package:provider/provider.dart';
import '../providers/robot_provider.dart';
import '../widgets/cube_3d_widget.dart';

class VideoStreamWidget extends StatefulWidget {
  final BoxFit fit;
  final bool fullscreen;

  const VideoStreamWidget({
    Key? key,
    this.fit = BoxFit.contain,
    this.fullscreen = false,
  }) : super(key: key);

  @override
  State<VideoStreamWidget> createState() => _VideoStreamWidgetState();
}

class _VideoStreamWidgetState extends State<VideoStreamWidget> {
  String _streamUrl = '';
  Offset _cubeOffset = Offset.zero;
  bool _cubeInitialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = context.watch<RobotProvider>();
    final ip = provider.serverIp;
    final w = provider.cameraWidth;
    final h = provider.cameraHeight;
    _streamUrl = 'http://$ip:5000/video_feed?w=$w&h=$h';
    // Reset cube centering when it was hidden and is now shown
    if (!provider.showCube3D) {
      _cubeInitialized = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RobotProvider>();
    final fps = ((provider.state['camera'] as Map<String, dynamic>?) ?? {})['fps'] as num? ?? 0;
    final ip = provider.serverIp;
    final w = provider.cameraWidth;
    final h = provider.cameraHeight;
    final streamUrl = 'http://$ip:5000/video_feed?w=$w&h=$h';
    final screenW = provider.screenWidth;
    final screenH = provider.screenHeight;

    if (widget.fullscreen) {
      return Stack(
        fit: StackFit.expand,
        children: [
          MJPEGStreamScreen(
            streamUrl: streamUrl,
            fit: widget.fit,
            showLiveIcon: false,
            watermarkText: "AI VISION FEED",
            showWatermark: false,
          ),
          // Crosshair overlay
          Center(
            child: CustomPaint(
              size: Size(80, 80),
              painter: _CrosshairPainter(),
            ),
          ),
          // FPS overlay
          Positioned(
            top: 48,
            right: 16,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${fps.toStringAsFixed(1)} FPS',
                style: TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          // ── Motor detailed HUD (bottom-left) ──
          if (provider.showMotorHud)
            _buildMotorHudOverlay(provider, context),
          // ── IMU detailed HUD (bottom-right) ──
          if (provider.showImuHud)
            _buildImuHudOverlay(provider, context),
          // ── 3D Cube overlay (center, draggable) ──
          if (provider.showCube3D)
            _buildDraggableCube(context, provider),
        ],
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.cyanAccent.withOpacity(0.5), width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.cyanAccent.withOpacity(0.2),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: AspectRatio(
          aspectRatio: 4 / 3,
          child: Stack(
            fit: StackFit.expand,
            children: [
              MJPEGStreamScreen(
                streamUrl: streamUrl,
                fit: widget.fit,
                showLiveIcon: true,
                watermarkText: "AI VISION FEED",
                showWatermark: true,
              ),
              // Live indicator overlay
              Positioned(
                top: 12,
                left: 12,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                      ),
                      SizedBox(width: 6),
                      Text(
                        'LIVE',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // FPS overlay
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${fps.toStringAsFixed(1)} FPS',
                    style: TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
              // Watermark
              Positioned(
                bottom: 12,
                right: 12,
                child: Text(
                  'AI VISION FEED',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
              ),
              // Motor HUD (small, bottom-left)
              if (provider.showMotorHud)
                Positioned(
                  bottom: 8,
                  left: 8,
                  child: _buildMotorMiniHud(provider),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMotorMiniHud(RobotProvider provider) {
    final m1 = provider.state['motor1'] as Map<String, dynamic>? ?? {};
    final m2 = provider.state['motor2'] as Map<String, dynamic>? ?? {};
    String fmt(dynamic v) {
      final d = (v as num?)?.toDouble() ?? 0;
      return d.toStringAsFixed(1);
    }

    return Container(
      padding: EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.5),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'M1 s=${fmt(m1['speed'])} a=${fmt(m1['angle'])} pwm=${fmt(m1['pwm'])}',
            style: TextStyle(color: Colors.cyanAccent, fontSize: 9, fontFamily: 'monospace'),
          ),
          Text(
            'M2 s=${fmt(m2['speed'])} a=${fmt(m2['angle'])} pwm=${fmt(m2['pwm'])}',
            style: TextStyle(color: Colors.cyanAccent, fontSize: 9, fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }

  // ── Motor detailed HUD (fullscreen, bottom-left, draggable) ──
  Widget _buildMotorHudOverlay(RobotProvider provider, BuildContext context) {
    final m1 = provider.state['motor1'] as Map<String, dynamic>? ?? {};
    final m2 = provider.state['motor2'] as Map<String, dynamic>? ?? {};
    final screenW = provider.screenWidth;
    final screenH = provider.screenHeight;
    final left = provider.motorHudX * screenW;
    final top = provider.motorHudY * screenH;
    final locked = provider.motorHudLocked;

    return Positioned(
      left: left,
      top: top,
      child: GestureDetector(
        onPanUpdate: locked
            ? null
            : (details) {
                final newX = (left + details.delta.dx) / screenW;
                final newY = (top + details.delta.dy) / screenH;
                provider.setMotorHudPos(newX.clamp(0.0, 0.9), newY.clamp(0.0, 0.9));
              },
        onLongPress: () {
          provider.setMotorHudLocked(!locked);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(locked ? '电机HUD已解锁，可拖拽' : '电机HUD已锁定'),
              duration: Duration(seconds: 1),
              backgroundColor: locked ? Colors.green : Colors.orange,
            ),
          );
        },
        child: Container(
          padding: EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.75),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: locked ? Colors.red.withOpacity(0.5) : Colors.yellow,
              width: locked ? 1 : 2,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    locked ? Icons.lock_outline : Icons.lock_open,
                    color: locked ? Colors.red : Colors.yellow,
                    size: 10,
                  ),
                  SizedBox(width: 4),
                  Text(
                    'MOTOR',
                    style: TextStyle(
                      color: Colors.cyanAccent,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                  if (!locked) ...[
                    SizedBox(width: 6),
                    Text(
                      '拖拽中',
                      style: TextStyle(color: Colors.yellow, fontSize: 9),
                    ),
                  ],
                ],
              ),
              SizedBox(height: 6),
              _buildMotorRow('M1', m1),
              SizedBox(height: 4),
              _buildMotorRow('M2', m2),
            ],
          ),
        ),
      ),
    );
  }

  // ── IMU detailed HUD (fullscreen, bottom-right, draggable) ──
  Widget _buildImuHudOverlay(RobotProvider provider, BuildContext context) {
    final imu = provider.state['imu'] as Map<String, dynamic>? ?? {};
    final pitch = (imu['pitch'] as num?)?.toDouble() ?? 0;
    final roll = (imu['roll'] as num?)?.toDouble() ?? 0;
    final yaw = (imu['yaw'] as num?)?.toDouble() ?? 0;
    final screenW = provider.screenWidth;
    final screenH = provider.screenHeight;
    final left = provider.imuHudX * screenW;
    final top = provider.imuHudY * screenH;
    final locked = provider.imuHudLocked;

    return Positioned(
      left: left,
      top: top,
      child: GestureDetector(
        onPanUpdate: locked
            ? null
            : (details) {
                final newX = (left + details.delta.dx) / screenW;
                final newY = (top + details.delta.dy) / screenH;
                provider.setImuHudPos(newX.clamp(0.0, 0.9), newY.clamp(0.0, 0.9));
              },
        onLongPress: () {
          provider.setImuHudLocked(!locked);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(locked ? 'IMU HUD已解锁，可拖拽' : 'IMU HUD已锁定'),
              duration: Duration(seconds: 1),
              backgroundColor: locked ? Colors.green : Colors.orange,
            ),
          );
        },
        child: Container(
          padding: EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.75),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: locked ? Colors.green.withOpacity(0.5) : Colors.yellow,
              width: locked ? 1 : 2,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    locked ? Icons.lock_outline : Icons.lock_open,
                    color: locked ? Colors.green : Colors.yellow,
                    size: 10,
                  ),
                  SizedBox(width: 4),
                  Text(
                    'IMU',
                    style: TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                  if (!locked) ...[
                    SizedBox(width: 6),
                    Text(
                      '拖拽中',
                      style: TextStyle(color: Colors.yellow, fontSize: 9),
                    ),
                  ],
                ],
              ),
              SizedBox(height: 6),
              _buildImuRow('Pitch', pitch, Colors.redAccent),
              SizedBox(height: 3),
              _buildImuRow('Roll', roll, Colors.greenAccent),
              SizedBox(height: 3),
              _buildImuRow('Yaw', yaw, Colors.orangeAccent),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMotorRow(String label, Map<String, dynamic> data) {
    final speed = (data['speed'] as num?)?.toDouble() ?? 0;
    final angle = (data['angle'] as num?)?.toDouble() ?? 0;
    final pwm = (data['pwm'] as num?)?.toDouble() ?? 0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 22,
          child: Text(
            label,
            style: TextStyle(color: Colors.cyanAccent, fontSize: 10, fontWeight: FontWeight.bold),
          ),
        ),
        Text(
          's=${speed.toStringAsFixed(1).padLeft(6)}  a=${angle.toStringAsFixed(1).padLeft(6)}  pwm=${pwm.toStringAsFixed(1).padLeft(6)}',
          style: TextStyle(
            color: Colors.white.withOpacity(0.8),
            fontSize: 10,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }

  Widget _buildImuRow(String label, double value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 40,
          child: Text(
            label,
            style: TextStyle(color: color.withOpacity(0.7), fontSize: 10),
          ),
        ),
        Text(
          '${value.toStringAsFixed(1).padLeft(6)}°',
          style: TextStyle(
            color: Colors.white.withOpacity(0.9),
            fontSize: 10,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }

  // ── Draggable 3D Cube (screen-bounded) ──
  Widget _buildDraggableCube(BuildContext context, RobotProvider provider) {
    final screenSize = MediaQuery.of(context).size;
    const cubeSize = 100.0;
    // Initialize center if first show
    if (!_cubeInitialized) {
      _cubeOffset = Offset(
        (screenSize.width - cubeSize) / 2,
        (screenSize.height - cubeSize) / 2,
      );
      _cubeInitialized = true;
    }
    // Clamp to keep fully on-screen
    _cubeOffset = Offset(
      _cubeOffset.dx.clamp(0.0, screenSize.width - cubeSize),
      _cubeOffset.dy.clamp(0.0, screenSize.height - cubeSize),
    );

    return Positioned(
      left: _cubeOffset.dx,
      top: _cubeOffset.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            final newX = (_cubeOffset.dx + details.delta.dx)
                .clamp(0.0, screenSize.width - cubeSize);
            final newY = (_cubeOffset.dy + details.delta.dy)
                .clamp(0.0, screenSize.height - cubeSize);
            _cubeOffset = Offset(newX, newY);
          });
        },
        child: Container(
          width: cubeSize,
          height: cubeSize,
          alignment: Alignment.center,
          child: Cube3DWidget(size: cubeSize),
        ),
      ),
    );
  }
}

class ResolutionPicker extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RobotProvider>();
    final presets = provider.cameraPresets;
    final currentW = provider.cameraWidth;
    final currentH = provider.cameraHeight;
    final screenW = provider.screenWidth;

    final currentValue = presets.firstWhere(
      (p) => p['width'] == currentW && p['height'] == currentH,
      orElse: () => {'width': currentW, 'height': currentH, 'fps': 0},
    );

    // Adaptive width: wider on large screens, 70% on small screens
    final pickerWidth = screenW > 500 ? 260.0 : screenW * 0.7;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.cyanAccent.withOpacity(0.5)),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: 140, maxWidth: pickerWidth),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<Map<String, dynamic>>(
            value: currentValue,
            isDense: true,
            icon: Icon(Icons.arrow_drop_down, color: Colors.white70, size: 14),
            dropdownColor: Colors.black.withOpacity(0.92),
            borderRadius: BorderRadius.circular(10),
            items: presets.map((p) {
              final w = p['width'] as int;
              final h = p['height'] as int;
              final fps = p['fps'] as int? ?? 0;
              final isCurrent = w == currentW && h == currentH;
              return DropdownMenuItem<Map<String, dynamic>>(
                value: p,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isCurrent)
                      Icon(Icons.check, color: Colors.cyanAccent, size: 14)
                    else
                      SizedBox(width: 14),
                    SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '$w × $h ${fps > 0 ? "@${fps}FPS" : ""}',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isCurrent ? Colors.cyanAccent : Colors.white70,
                          fontSize: 13,
                          fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
            selectedItemBuilder: (_) => presets.map((p) {
              final w = p['width'] as int;
              final h = p['height'] as int;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.videocam, color: Colors.cyanAccent, size: 12),
                  SizedBox(width: 4),
                  Text(
                    '$w×$h',
                    style: TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ],
              );
            }).toList(),
            onChanged: (p) {
              if (p != null) {
                final w = p['width'] as int;
                final h = p['height'] as int;
                final fps = p['fps'] as int? ?? 0;
                provider.setCameraResolution(w, h, fps: fps > 0 ? fps : null);
              }
            },
          ),
        ),
      ),
    );
  }
}

class _CrosshairPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.green.withOpacity(0.7)
      ..strokeWidth = 1;

    final cx = size.width / 2;
    final cy = size.height / 2;

    canvas.drawLine(Offset(cx - 20, cy), Offset(cx + 20, cy), paint);
    canvas.drawLine(Offset(cx, cy - 20), Offset(cx, cy + 20), paint);
    canvas.drawCircle(Offset(cx, cy), 10, paint..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
