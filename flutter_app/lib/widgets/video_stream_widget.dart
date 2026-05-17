import 'package:flutter/material.dart';
import 'package:mjpeg_stream/mjpeg_stream.dart';
import 'package:provider/provider.dart';
import '../providers/robot_provider.dart';

class VideoStreamWidget extends StatelessWidget {
  final BoxFit fit;
  final bool fullscreen;

  const VideoStreamWidget({
    Key? key,
    this.fit = BoxFit.contain,
    this.fullscreen = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RobotProvider>();
    final streamUrl = 'http://${provider.serverIp}:5000/video_feed';

    if (fullscreen) {
      return Stack(
        fit: StackFit.expand,
        children: [
          MJPEGStreamScreen(
            streamUrl: streamUrl,
            fit: fit,
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
                fit: fit,
                showLiveIcon: true,
                watermarkText: "AI VISION FEED",
                showWatermark: true,
              ),
              // Live indicator overlay (if package doesn't provide)
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
