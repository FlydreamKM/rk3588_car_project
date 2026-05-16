import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/robot_provider.dart';

class ModeButtons extends StatelessWidget {
  const ModeButtons({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final currentMode = context.watch<RobotProvider>().mode;

    final modes = [
      {'name': '手动', 'icon': Icons.gamepad, 'value': 'manual', 'color': Colors.blue},
      {'name': '跟随', 'icon': Icons.person_search, 'value': 'follow', 'color': Colors.purple},
      {'name': '泊车', 'icon': Icons.local_parking, 'value': 'park', 'color': Colors.orange},
      {'name': '手势', 'icon': Icons.back_hand, 'value': 'gesture', 'color': Colors.teal},
      {'name': '语音', 'icon': Icons.mic, 'value': 'voice', 'color': Colors.green},
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: modes.map((mode) {
        final isActive = currentMode == mode['value'];
        final color = mode['color'] as Color;

        return GestureDetector(
          onTap: () => context.read<RobotProvider>().setMode(mode['value'] as String),
          child: AnimatedContainer(
            duration: Duration(milliseconds: 200),
            padding: EdgeInsets.symmetric(vertical: 10, horizontal: 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isActive
                    ? [color.withOpacity(0.6), color.withOpacity(0.3)]
                    : [color.withOpacity(0.15), color.withOpacity(0.05)],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isActive ? color : color.withOpacity(0.2),
                width: isActive ? 2 : 1,
              ),
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: color.withOpacity(0.4),
                        blurRadius: 12,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  mode['icon'] as IconData,
                  color: isActive ? Colors.white : color.withOpacity(0.7),
                  size: 18,
                ),
                SizedBox(width: 6),
                Text(
                  mode['name'] as String,
                  style: TextStyle(
                    color: isActive ? Colors.white : color.withOpacity(0.7),
                    fontSize: 13,
                    fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
