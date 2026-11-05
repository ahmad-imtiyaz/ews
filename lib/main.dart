import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_theme.dart';
import 'screens/splash_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const EwsApp());
}

class EwsApp extends StatelessWidget {
  const EwsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EWS Lumeneng',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const SplashScreen(),
    );
  }
}
