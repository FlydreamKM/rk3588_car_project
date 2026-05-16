import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';
import 'package:provider/provider.dart';
import '../providers/robot_provider.dart';

class DashboardWidget extends StatelessWidget {
  const DashboardWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final state = context.watch<RobotProvider>();

    return Row(
      children: [
        // 速度表
        Expanded(
          child: _buildSpeedGauge(state.speed),
        ),
        SizedBox(width: 16),
        // 电量环
        _buildBatteryGauge(state.battery),
        SizedBox(width: 16),
        // 航向角
        Expanded(
          child: _buildHeadingGauge(state.heading),
        ),
      ],
    );
  }

  Widget _buildSpeedGauge(double speed) {
    return SfRadialGauge(
      axes: <RadialAxis>[
        RadialAxis(
          minimum: 0,
          maximum: 100,
          startAngle: 150,
          endAngle: 30,
          radiusFactor: 0.9,
          axisLineStyle: AxisLineStyle(
            thickness: 0.1,
            color: Colors.white.withValues(alpha:0.1),
          ),
          ranges: <GaugeRange>[
            GaugeRange(
              startValue: 0,
              endValue: 30,
              color: Colors.green,
              startWidth: 0.1,
              endWidth: 0.1,
            ),
            GaugeRange(
              startValue: 30,
              endValue: 70,
              color: Colors.orange,
              startWidth: 0.1,
              endWidth: 0.1,
            ),
            GaugeRange(
              startValue: 70,
              endValue: 100,
              color: Colors.red,
              startWidth: 0.1,
              endWidth: 0.1,
            ),
          ],
          pointers: <GaugePointer>[
            NeedlePointer(
              value: speed.abs(),
              enableAnimation: true,
              animationDuration: 200,
              needleColor: Colors.cyanAccent,
              needleLength: 0.7,
              needleStartWidth: 1,
              needleEndWidth: 4,
              knobStyle: KnobStyle(
                color: Colors.cyanAccent,
                sizeUnit: GaugeSizeUnit.factor,
                knobRadius: 0.08,
              ),
            ),
          ],
          annotations: <GaugeAnnotation>[
            GaugeAnnotation(
              widget: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${speed.toStringAsFixed(1)}',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    'cm/s',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
              angle: 90,
              positionFactor: 0.6,
            ),
          ],
          majorTickStyle: MajorTickStyle(
            length: 8,
            thickness: 1,
            color: Colors.white.withValues(alpha:0.5),
          ),
          minorTickStyle: MinorTickStyle(
            length: 4,
            thickness: 1,
            color: Colors.white.withValues(alpha:0.3),
          ),
          axisLabelStyle: GaugeTextStyle(
            color: Colors.white.withValues(alpha:0.7),
            fontSize: 10,
          ),
        ),
      ],
    );
  }

  Widget _buildBatteryGauge(double battery) {
    final isLow = battery < 30;
    return SizedBox(
      width: 80,
      height: 80,
      child: SfRadialGauge(
        axes: <RadialAxis>[
          RadialAxis(
            minimum: 0,
            maximum: 100,
            startAngle: 270,
            endAngle: 270,
            showLabels: false,
            showTicks: false,
            radiusFactor: 0.9,
            axisLineStyle: AxisLineStyle(
              thickness: 0.15,
              color: Colors.white.withValues(alpha:0.1),
            ),
            pointers: <GaugePointer>[
              RangePointer(
                value: battery,
                color: isLow ? Colors.red : Colors.green,
                enableAnimation: true,
                animationDuration: 500,
                width: 0.15,
              ),
            ],
            annotations: <GaugeAnnotation>[
              GaugeAnnotation(
                widget: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      battery > 20 ? Icons.battery_full : Icons.battery_alert,
                      color: isLow ? Colors.red : Colors.green,
                      size: 28,
                    ),
                    Text(
                      '${battery.toStringAsFixed(0)}%',
                      style: TextStyle(
                        color: isLow ? Colors.red : Colors.green,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                angle: 90,
                positionFactor: 0,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeadingGauge(double heading) {
    return SfRadialGauge(
      axes: <RadialAxis>[
        RadialAxis(
          minimum: 0,
          maximum: 360,
          startAngle: 270,
          endAngle: 270,
          radiusFactor: 0.9,
          axisLineStyle: AxisLineStyle(
            thickness: 0.05,
            color: Colors.white.withValues(alpha:0.1),
          ),
          pointers: <GaugePointer>[
            MarkerPointer(
              value: heading,
              enableAnimation: true,
              animationDuration: 200,
              color: Colors.cyanAccent,
              markerType: MarkerType.triangle,
              markerHeight: 15,
              markerWidth: 15,
            ),
          ],
          annotations: <GaugeAnnotation>[
            GaugeAnnotation(
              widget: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${heading.toStringAsFixed(0)}°',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    '航向',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
              angle: 90,
              positionFactor: 0.5,
            ),
          ],
          majorTickStyle: MajorTickStyle(
            length: 6,
            thickness: 1,
            color: Colors.white.withValues(alpha:0.4),
          ),
          minorTickStyle: MinorTickStyle(
            length: 3,
            thickness: 1,
            color: Colors.white.withValues(alpha:0.2),
          ),
          axisLabelStyle: GaugeTextStyle(
            color: Colors.white.withValues(alpha:0.6),
            fontSize: 9,
          ),
        ),
      ],
    );
  }
}
