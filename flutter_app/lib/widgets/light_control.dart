import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/robot_provider.dart';

class LightControl extends StatelessWidget {
  const LightControl({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final lights = [
      {'name': '冷静蓝', 'color': Colors.blue, 'value': 'blue'},
      {'name': '警戒红', 'color': Colors.red, 'value': 'red'},
      {'name': '活力绿', 'color': Colors.green, 'value': 'green'},
      {'name': '彩虹流', 'color': Colors.purple, 'value': 'rainbow'},
      {'name': '金色', 'color': Colors.amber, 'value': 'gold'},
      {'name': '关闭', 'color': Colors.grey, 'value': 'off'},
    ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: lights.map((light) {
        final color = light['color'] as Color;
        return GestureDetector(
          onTap: () => context.read<RobotProvider>().setLight(
            light['value'] as String,
            'breath',
          ),
          child: Column(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: color.withOpacity(0.4),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Center(
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
              SizedBox(height: 6),
              Text(
                light['name'] as String,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
