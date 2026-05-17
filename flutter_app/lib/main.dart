import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'providers/robot_provider.dart';
import 'screens/connection_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SmartCarApp());
}

class SmartCarApp extends StatelessWidget {
  const SmartCarApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => RobotProvider(),
      child: MaterialApp(
        title: '智能小车控制中枢',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: Color(0xFF0A0E21),
          primaryColor: Colors.cyanAccent,
          colorScheme: ColorScheme.dark(
            primary: Colors.cyanAccent,
            secondary: Colors.purpleAccent,
          ),
          appBarTheme: AppBarTheme(
            backgroundColor: Colors.transparent,
            elevation: 0,
          ),
        ),
        home: ConnectionScreen(),
      ),
    );
  }
}
