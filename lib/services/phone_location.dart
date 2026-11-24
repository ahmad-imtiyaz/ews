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

/// Posisi berhenti dipertajam di sini. GPS HP di tempat terbuka paling bagus
/// ±3–5 m; ±1 m butuh alat GPS khusus (RTK), jadi menunggu lebih kecil dari
/// ini hanya menghabiskan waktu warga.
const targetAccuracy = 10.0;

/// Android 12+ membolehkan izin lokasi "Perkiraan". Posisinya sengaja
/// digeser sampai ±2 km dan GPS tidak dipakai, jadi petugas bisa salah
/// tempat.
Future<bool> isLocationApproximate() async {
  try {
    return await Geolocator.getLocationAccuracy() ==
        LocationAccuracyStatus.reduced;
  } catch (_) {
    return false;
  }
}

/// Memunculkan dialog Android "Ubah ke lokasi tepat". Bila warga sudah
/// beberapa kali menolak, Android tidak memunculkannya lagi; pakai
/// [openLocationSettings].
Future<void> askPreciseLocation() async {
  try {
    await Geolocator.requestPermission();
  } catch (_) {}
}

/// Halaman izin aplikasi di pengaturan HP, tempat "Gunakan lokasi tepat".
Future<void> openLocationSettings() async {
  try {
    await Geolocator.openAppSettings();
  } catch (_) {}
}

bool _askedPrecise = false;

/// Posisi GPS selama ini masih dianggap posisi sekarang: berjalan semenit
/// paling jauh puluhan meter.
const recentFixAge = Duration(minutes: 1);

/// Posisi terbaik terakhir dari [watchPhoneLocation], mis. dari peta Beranda.
({PhoneFix fix, DateTime at})? _recent;

/// Posisi GPS yang masih baru, dari aplikasi ini atau aplikasi lain (mis.
/// Google Maps), supaya Lapor tidak mulai dari posisi kasar ±80 m.
Future<PhoneFix?> _recentGpsFix() async {
  final now = DateTime.now();
  if (_recent case (:final fix, :final at)
      when now.difference(at) <= recentFixAge && fix.accuracy <= gpsAccuracy) {
    return fix;
  }
  try {
    final last = await Geolocator.getLastKnownPosition();
    if (last != null &&
        now.difference(last.timestamp) <= recentFixAge &&
        last.accuracy <= gpsAccuracy) {
      return _toFix(last);
    }
  } catch (_) {}
  return null;
}

/// Posisi HP yang makin tajam, akurasinya dalam meter. Bila HP baru saja
/// punya posisi GPS (lihat [recentFixAge]), posisi itu dikirim duluan, lalu
/// diganti posisi baru dari GPS begitu ada. Selain itu tiap posisi yang
/// dikirim lebih akurat dari sebelumnya. Selesai begitu akurasi sampai
/// [targetAccuracy] atau [timeLimit] habis. Bila sampai waktunya habis belum ada
/// posisi sama sekali, misalnya di dalam rumah, dipakai lokasi terakhir yang
/// diketahui HP. Gagal dilempar sebagai [LocationUnavailable].
Stream<PhoneFix> watchPhoneLocation({
  Duration timeLimit = const Duration(seconds: 45),
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
  // Sekali per buka aplikasi, supaya warga yang dulu memilih "Perkiraan"
  // ditawari lokasi tepat tanpa terus-menerus ditanya.
  if (!_askedPrecise && await isLocationApproximate()) {
    _askedPrecise = true;
    await askPreciseLocation();
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
  // Posisi lama yang masih baru hanya sementara: posisi baru dari GPS
  // menggantikannya walau angka akurasinya sedikit lebih besar, karena
  // pelapor mungkin sudah pindah.
  var provisional = await _recentGpsFix();
  PhoneFix? best = provisional;
  if (provisional != null) yield provisional;
  try {
    while (true) {
      final left = timeLimit - stopwatch.elapsed;
      if (left <= Duration.zero || !await positions.moveNext().timeout(left)) {
        break;
      }
      final fix = _toFix(positions.current);
      if (provisional != null) {
        if (fix.accuracy > gpsAccuracy &&
            fix.accuracy >= provisional.accuracy) {
          continue;
        }
        provisional = null;
      } else if (best != null && fix.accuracy >= best.accuracy) {
        continue;
      }
      best = fix;
      _recent = (fix: fix, at: DateTime.now());
      yield fix;
      if (fix.accuracy <= targetAccuracy) break;
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
