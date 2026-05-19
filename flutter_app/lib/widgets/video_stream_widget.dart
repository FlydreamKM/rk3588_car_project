import 'package:flutter/material.dart';
import 'package:mjpeg_stream/mjpeg_stream.dart';
import 'package:provider/provider.dart';
import '../providers/robot_provider.dart';

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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = context.watch<RobotProvider>();
    final ip = provider.serverIp;
    final w = provider.cameraWidth;
    final h = provider.cameraHeight;
    _streamUrl = 'http://$ip:5000/video_feed?w=$w&h=$h';
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RobotProvider>();
    final fps = ((provider.state['camera'] as Map<String, dynamic>?) ?? {})['fps'] as num? ?? 0;
    final ip = provider.serverIp;
    final w = provider.cameraWidth;
    final h = provider.cameraHeight;
    final streamUrl = 'http://$ip:5000/video_feed?w=$w&h=$h';

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
            ],
          ),
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

    return GestureDetector(
      onTap: () => _showResolutionSheet(context, provider, presets),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.6),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.cyanAccent.withOpacity(0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam, color: Colors.cyanAccent, size: 12),
            SizedBox(width: 4),
            Text(
              '$currentW×$currentH',
              style: TextStyle(color: Colors.white, fontSize: 11),
            ),
            Icon(Icons.arrow_drop_down, color: Colors.white70, size: 14),
          ],
        ),
      ),
    );
  }

  void _showResolutionSheet(BuildContext context, RobotProvider provider,
      List<Map<String, dynamic>> presets) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black.withOpacity(0.92),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: false,
      builder: (_) => SafeArea(
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(24, 20, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                '视频分辨率',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 16),
              ...presets.map((p) {
                final w = p['width'] as int;
                final h = p['height'] as int;
                final fps = p['fps'] as int? ?? 0;
                final isCurrent = w == provider.cameraWidth && h == provider.cameraHeight;
                return InkWell(
                  onTap: () {
                    provider.setCameraResolution(w, h, fps: fps > 0 ? fps : null);
                    Navigator.pop(context);
                  },
                  child: Container(
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                    margin: EdgeInsets.only(bottom: 4),
                    decoration: BoxDecoration(
                      color: isCurrent ? Colors.cyanAccent.withOpacity(0.15) : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (isCurrent)
                          Icon(Icons.check, color: Colors.cyanAccent, size: 18)
                        else
                          SizedBox(width: 18),
                        SizedBox(width: 8),
                        Text(
                          '$w × $h ${fps > 0 ? "@${fps}FPS" : ""}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: isCurrent ? Colors.cyanAccent : Colors.white70,
                            fontSize: 15,
                            fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
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

    // Horizontal line
    canvas.drawLine(Offset(cx - 20, cy), Offset(cx + 20, cy), paint);
    // Vertical line
    canvas.drawLine(Offset(cx, cy - 20), Offset(cx, cy + 20), paint);
    // Circle
    canvas.drawCircle(Offset(cx, cy), 10, paint..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
