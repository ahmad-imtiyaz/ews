import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import 'app_theme.dart';
import 'screens/splash_screen.dart';
import 'services/crash_reports.dart';
import 'services/report_contact.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  try {
    await Firebase.initializeApp();
    await CrashReports.start();
  } catch (error) {
    // Aplikasi tetap bisa dipakai tanpa kiriman notifikasi dari server, tapi
    // saat pengembangan ini harus kelihatan.
    debugPrint('Firebase gagal dimulai: $error');
  }

  // Galat yang lolos tetap dicatat. Aplikasi jalan terus: layar yang rusak
  // lebih baik daripada aplikasi tertutup saat warga butuh informasi.
  final showError = FlutterError.onError;
  FlutterError.onError = (details) {
    showError?.call(details);
    CrashReports.record(details.exception, details.stack, fatal: true);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    CrashReports.record(error, stack, fatal: true);
    return true;
  };

  // Nomor WhatsApp laporan bisa diganti dari web Laravel kapan saja, jadi
  // diambil lagi setiap aplikasi dibuka atau kembali ke depan.
  reportContact.refresh();
  AppLifecycleListener(onResume: reportContact.refresh);

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
