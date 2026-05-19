import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/robot_provider.dart';

/// A 3D wireframe cube that rotates according to IMU pitch/roll/yaw.
/// Uses simple perspective projection on a CustomPainter.
class Cube3DWidget extends StatelessWidget {
  final double size;

  const Cube3DWidget({Key? key, this.size = 120}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RobotProvider>();
    final imu = provider.state['imu'] as Map<String, dynamic>? ?? {};
    final pitch = (imu['pitch'] as num?)?.toDouble() ?? 0;
    final roll = (imu['roll'] as num?)?.toDouble() ?? 0;
    final yaw = (imu['yaw'] as num?)?.toDouble() ?? 0;

    return CustomPaint(
      size: Size(size, size),
      painter: _Cube3DPainter(
        pitch: pitch * pi / 180,
        roll: roll * pi / 180,
        yaw: yaw * pi / 180,
        opacity: provider.cubeOpacity,
      ),
    );
  }
}

class _Cube3DPainter extends CustomPainter {
  final double pitch; // rotation around X
  final double roll;  // rotation around Y
  final double yaw;   // rotation around Z
  final double opacity;

  _Cube3DPainter({
    required this.pitch,
    required this.roll,
    required this.yaw,
    required this.opacity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final scale = size.width * 0.35;

    // Cube vertices in local space (edge length = 1, centered at origin)
    final vertices = [
      [-0.5, -0.5, -0.5],
      [0.5, -0.5, -0.5],
      [0.5, 0.5, -0.5],
      [-0.5, 0.5, -0.5],
      [-0.5, -0.5, 0.5],
      [0.5, -0.5, 0.5],
      [0.5, 0.5, 0.5],
      [-0.5, 0.5, 0.5],
    ];

    // Edges (pairs of vertex indices)
    final edges = [
      [0, 1], [1, 2], [2, 3], [3, 0], // back face
      [4, 5], [5, 6], [6, 7], [7, 4], // front face
      [0, 4], [1, 5], [2, 6], [3, 7], // connecting edges
    ];

    // Rotate and project each vertex
    List<Offset> projected = [];
    for (final v in vertices) {
      // Apply rotations: yaw (Z) → roll (Y) → pitch (X)
      var x = v[0], y = v[1], z = v[2];

      // Yaw around Z
      var nx = x * cos(yaw) - y * sin(yaw);
      var ny = x * sin(yaw) + y * cos(yaw);
      x = nx; y = ny;

      // Roll around Y
      nx = x * cos(roll) + z * sin(roll);
      var nz = -x * sin(roll) + z * cos(roll);
      x = nx; z = nz;

      // Pitch around X
      ny = y * cos(pitch) - z * sin(pitch);
      nz = y * sin(pitch) + z * cos(pitch);
      y = ny; z = nz;

      // Simple perspective projection
      final fov = 2.5;
      final factor = fov / (fov + z);
      projected.add(Offset(
        cx + x * scale * factor,
        cy - y * scale * factor, // flip Y for screen coords
      ));
    }

    // Paint edges with front/back depth cue
    final backPaint = Paint()
      ..color = Colors.cyanAccent.withOpacity(0.2 * opacity)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final frontPaint = Paint()
      ..color = Colors.cyanAccent.withOpacity(0.7 * opacity)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    // Draw back edges first (lower Z on average)
    for (final e in edges) {
      final avgZ = (vertices[e[0]][2] + vertices[e[1]][2]) / 2;
      final paint = avgZ > 0 ? frontPaint : backPaint;
      canvas.drawLine(projected[e[0]], projected[e[1]], paint);
    }

    // Draw axes indicator at cube center
    final axisLen = scale * 0.5;
    final axisOrigin = Offset(cx, cy);

    // X axis (red) — points right after yaw
    final axX = Offset(
      cx + cos(yaw) * axisLen,
      cy - sin(yaw) * axisLen,
    );
    canvas.drawLine(axisOrigin, axX, Paint()
      ..color = Colors.redAccent.withOpacity(0.8 * opacity)
      ..strokeWidth = 2);

    // Y axis (green) — points up
    final axY = Offset(
      cx + sin(yaw) * axisLen,
      cy + cos(yaw) * axisLen,
    );
    canvas.drawLine(axisOrigin, axY, Paint()
      ..color = Colors.greenAccent.withOpacity(0.8 * opacity)
      ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(covariant _Cube3DPainter old) {
    return old.pitch != pitch || old.roll != roll || old.yaw != yaw || old.opacity != opacity;
  }
}
