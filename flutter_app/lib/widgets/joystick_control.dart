import 'package:flutter/material.dart';
import 'package:flutter_joystick/flutter_joystick.dart';
import 'package:provider/provider.dart';
import '../providers/robot_provider.dart';

class JoystickControl extends StatefulWidget {
  final double size;

  const JoystickControl({Key? key, this.size = 140}) : super(key: key);

  @override
  State<JoystickControl> createState() => _JoystickControlState();
}

class _JoystickControlState extends State<JoystickControl> {
  double _x = 0;
  double _y = 0;
  String _currentAction = 'stop';
  double _lastServoX = 0;
  int _servoThrottle = 0;

  void _sendCommand(double x, double y) {
    final provider = context.read<RobotProvider>();
    final speedLimit = provider.motorSpeedLimit;
    final accelLimit = provider.motorAccelLimit;

    // Map joystick to action
    String action = 'stop';
    double actualSpeed = y.abs() * speedLimit;

    if (y < -0.3) {
      action = 'forward';
    } else if (y > 0.3) {
      action = 'backward';
      actualSpeed = -actualSpeed;
    } else if (x < -0.3) {
      action = 'left';
      actualSpeed = x.abs() * speedLimit;
    } else if (x > 0.3) {
      action = 'right';
      actualSpeed = x.abs() * speedLimit;
    } else {
      actualSpeed = 0;
    }

    if (action != _currentAction || actualSpeed.abs() > 0.05) {
      _currentAction = action;
      // Send scaled motor targets with accel/decel limits
      if (action == 'forward' || action == 'backward') {
        provider.setMotorTarget(
          motor: 255, mode: 0,
          speed: actualSpeed, angle: 0,
          accel: accelLimit, decel: accelLimit,
        );
      } else if (action == 'left') {
        provider.setMotorTarget(motor: 0, mode: 0, speed: -actualSpeed * 0.5, angle: 0, accel: accelLimit, decel: accelLimit);
        provider.setMotorTarget(motor: 1, mode: 0, speed: actualSpeed * 0.5, angle: 0, accel: accelLimit, decel: accelLimit);
      } else if (action == 'right') {
        provider.setMotorTarget(motor: 0, mode: 0, speed: actualSpeed * 0.5, angle: 0, accel: accelLimit, decel: accelLimit);
        provider.setMotorTarget(motor: 1, mode: 0, speed: -actualSpeed * 0.5, angle: 0, accel: accelLimit, decel: accelLimit);
      }
    }

    // Integrate servo steering with joystick X axis
    // Throttle: only update servo every 5th frame to avoid flooding
    if ((x.abs() > 0.05) && (++_servoThrottle % 5 == 0)) {
      final servoAngle = (x * 100).clamp(-100.0, 100.0);
      // Only send if change is significant
      if ((servoAngle - _lastServoX).abs() > 3) {
        _lastServoX = servoAngle;
        provider.setServo(servoAngle);
      }
    }
  }

  void _onDragEnd() {
    setState(() {
      _x = 0;
      _y = 0;
      _currentAction = 'stop';
      _lastServoX = 0;
    });
    // Soft stop: speed=0 + position mode lock instead of emergency stop
    context.read<RobotProvider>().setMotorStopAndLock();
    context.read<RobotProvider>().centerServo();
  }

  @override
  Widget build(BuildContext context) {
    final baseSize = widget.size;
    final stickSize = baseSize * 0.36;

    return Column(
      mainAxisSize: MainAxisSize.min,
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
          onStickDragEnd: _onDragEnd,
          base: JoystickBase(
            size: baseSize,
            decoration: JoystickBaseDecoration(
              color: Colors.grey.shade900,
              drawOuterCircle: true,
              drawInnerCircle: true,
              outerCircleColor: Colors.cyanAccent.withOpacity(0.3),
              innerCircleColor: Colors.cyanAccent.withOpacity(0.1),
              drawArrows: true,
            ),
            arrowsDecoration: JoystickArrowsDecoration(
              color: Colors.cyanAccent.withOpacity(0.5),
            ),
          ),
          stick: JoystickStick(
            size: stickSize,
            decoration: JoystickStickDecoration(
              color: Colors.cyanAccent,
              shadowColor: Colors.cyanAccent.withOpacity(0.5),
            ),
          ),
        ),
        SizedBox(height: 8),
        Text(
          _currentAction.toUpperCase(),
          style: TextStyle(
            color: Colors.cyanAccent,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
      ],
    );
  }
}
