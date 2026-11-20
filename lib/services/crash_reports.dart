import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Laporan galat ke Firebase Crashlytics, supaya kerusakan di HP warga
/// terlihat oleh pengembang walau warga tidak melapor.
///
/// Sebelum [start] (tes, atau Firebase gagal dimulai) galat hanya dicetak.
abstract final class CrashReports {
  static bool _started = false;

  static Future<void> start() async {
    // Saat pengembangan galat sudah terlihat di konsol, jadi tidak dikirim.
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
      !kDebugMode,
    );
    _started = true;
  }

  /// [reason] menjelaskan apa yang sedang dikerjakan, mis. "menampilkan
  /// peringatan".
  static void record(
    Object error,
    StackTrace? stack, {
    String? reason,
    bool fatal = false,
  }) {
    if (!_started) {
      debugPrint('Galat${reason == null ? '' : ' saat $reason'}: $error');
      return;
    }
    FirebaseCrashlytics.instance
        .recordError(error, stack, reason: reason, fatal: fatal)
        .catchError((Object _) {});
  }
}
