import 'package:flutter/material.dart';
import 'package:flutter_joystick/flutter_joystick.dart';
import 'package:provider/provider.dart';
import '../providers/robot_provider.dart';

class JoystickControl extends StatefulWidget {
  const JoystickControl({Key? key}) : super(key: key);

  @override
  State<JoystickControl> createState() => _JoystickControlState();
}

class _JoystickControlState extends State<JoystickControl> {
  // ignore: unused_field
  double _x = 0;
  // ignore: unused_field
  double _y = 0;
  String _currentAction = 'stop';

  void _sendCommand(double x, double y) {
    final provider = context.read<RobotProvider>();
    
    // Map joystick to action
    String action = 'stop';
    int speed = (y.abs() * 100).toInt();
    
    if (y < -0.3) {
      action = 'forward';
    } else if (y > 0.3) {
      action = 'backward';
    } else if (x < -0.3) {
      action = 'left';
      speed = (x.abs() * 100).toInt();
    } else if (x > 0.3) {
      action = 'right';
      speed = (x.abs() * 100).toInt();
    }
    
    if (action != _currentAction || speed > 5) {
      _currentAction = action;
      provider.sendControl(action, speed: speed.clamp(0, 100));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Joystick(
          mode: JoystickMode.all,
          listener: (details) {
            setState(() {
              _x = details.x;
              _y = details.y;
            });
            _sendCommand(details.x, details.y);
          },
          onStickDragEnd: () {
            setState(() {
              _x = 0;
              _y = 0;
              _currentAction = 'stop';
            });
            context.read<RobotProvider>().sendControl('stop');
          },
          base: JoystickBase(
            size: 140,
            decoration: JoystickBaseDecoration(
              color: Colors.grey.shade900,
              drawOuterCircle: true,
              drawInnerCircle: true,
              outerCircleColor: Colors.cyanAccent.withOpacity(0.3),
              innerCircleColor: Colors.cyanAccent.withOpacity(0.1),
              drawArrows: true,
              arrowColor: Colors.cyanAccent.withOpacity(0.5),
            ),
            arrowsDecoration: JoystickArrowsDecoration(
              color: Colors.cyanAccent.withOpacity(0.5),
            ),
          ),
          stick: JoystickStick(
            size: 50,
            decoration: JoystickStickDecoration(
              color: Colors.cyanAccent,
              shadowColor: Colors.cyanAccent.withOpacity(0.5),
            ),
          ),
        ),
        SizedBox(height: 12),
        Text(
          _currentAction.toUpperCase(),
          style: TextStyle(
            color: Colors.cyanAccent,
            fontSize: 14,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
      ],
    );
  }
}
