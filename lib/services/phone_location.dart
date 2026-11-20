import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

typedef PhoneFix = ({double latitude, double longitude, double accuracy});

enum LocationProblem { serviceOff, denied, notFound }

class LocationUnavailable implements Exception {
  const LocationUnavailable(this.problem);

  final LocationProblem problem;
}

/// Akurasi yang biasanya baru tercapai setelah GPS dapat sinyal satelit.
/// Lokasi pertama dari HP hampir selalu perkiraan dari Wi-Fi atau menara
/// sinyal, ±50 m sampai beberapa ratus meter.
const gpsAccuracy = 20.0;

/// Posisi HP yang makin tajam, akurasinya dalam meter. Tiap posisi yang
/// dikirim lebih akurat dari sebelumnya. Selesai begitu akurasi sampai
/// [gpsAccuracy] atau [timeLimit] habis. Bila sampai waktunya habis belum ada
/// posisi sama sekali, misalnya di dalam rumah, dipakai lokasi terakhir yang
/// diketahui HP. Gagal dilempar sebagai [LocationUnavailable].
Stream<PhoneFix> watchPhoneLocation({
  Duration timeLimit = const Duration(seconds: 30),
}) async* {
  if (!await Geolocator.isLocationServiceEnabled()) {
    throw const LocationUnavailable(LocationProblem.serviceOff);
  }
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.denied ||
      permission == LocationPermission.deniedForever) {
    throw const LocationUnavailable(LocationProblem.denied);
  }

  // getCurrentPosition berhenti di posisi pertama, yang di Android datang dari
  // jaringan sebelum GPS sempat menyala (di lapangan selalu ±80 m), jadi
  // posisinya didengarkan terus sampai GPS masuk.
  final settings = defaultTargetPlatform == TargetPlatform.android
      ? AndroidSettings(
          accuracy: LocationAccuracy.best,
          intervalDuration: const Duration(seconds: 1),
        )
      : const LocationSettings(accuracy: LocationAccuracy.best);
  final positions = StreamIterator(
    Geolocator.getPositionStream(locationSettings: settings),
  );
  final stopwatch = Stopwatch()..start();
  PhoneFix? best;
  try {
    while (true) {
      final left = timeLimit - stopwatch.elapsed;
      if (left <= Duration.zero || !await positions.moveNext().timeout(left)) {
        break;
      }
      final fix = _toFix(positions.current);
      if (best != null && fix.accuracy >= best.accuracy) continue;
      best = fix;
      yield fix;
      if (fix.accuracy <= gpsAccuracy) break;
    }
  } on TimeoutException {
    // Waktunya habis, posisi terbaik sudah dikirim.
  } catch (_) {
    // Lokasi dimatikan di tengah jalan; pakai yang sudah didapat.
  } finally {
    await positions.cancel();
  }

  if (best != null) return;
  // Lokasi terakhir bisa dari berhari-hari lalu di tempat lain, padahal
  // akurasinya tetap tertulis kecil.
  final last = await Geolocator.getLastKnownPosition();
  if (last == null ||
      DateTime.now().difference(last.timestamp) > const Duration(minutes: 10)) {
    throw const LocationUnavailable(LocationProblem.notFound);
  }
  yield _toFix(last);
}

PhoneFix _toFix(Position position) => (
  latitude: position.latitude,
  longitude: position.longitude,
  accuracy: position.accuracy,
);
