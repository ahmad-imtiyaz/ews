import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

import '../config.dart';
import '../data/ews_data.dart';
import 'ews_api.dart';

/// Satu pengambil data EWS untuk Beranda, Sensor, dan lonceng, supaya server
/// cukup dipanggil sekali tiap 10 detik walau beberapa menu memakainya.
class EwsFeed extends ChangeNotifier {
  EwsFeed({Future<EwsData> Function()? load}) {
    if (load != null) {
      _load = load;
    } else {
      final api = _api = EwsApi(ewsBaseUrl);
      _load = api.fetch;
    }
  }

  late final Future<EwsData> Function() _load;
  EwsApi? _api;
  Timer? _timer;
  Future<void>? _pending;
  bool _disposed = false;

  EwsData? _data;
  DateTime? _checkedAt;
  bool _failed = false;

  /// Data terakhir yang berhasil diambil. Tetap ada saat sinyal putus.
  EwsData? get data => _data;
  DateTime? get checkedAt => _checkedAt;

  /// Pengambilan terakhir gagal.
  bool get failed => _failed;
  bool get busy => _pending != null;

  /// Sinyal desa bisa lambat, jadi permintaan baru menunggu yang masih jalan.
  Future<void> refresh() => _pending ??= _fetch().whenComplete(() {
    _pending = null;
    if (!_disposed) notifyListeners();
  });

  Future<void> _fetch() async {
    try {
      _data = await _load();
      _failed = false;
      _checkedAt = clock.now();
    } catch (_) {
      _failed = true;
    }
  }

  /// Dimatikan saat aplikasi ditinggal supaya kuota warga tidak terpakai di
  /// latar. Begitu dinyalakan lagi, data langsung diambil ulang, kecuali baru
  /// saja diambil (mis. oleh splash).
  set polling(bool on) {
    if (on == (_timer != null)) return;
    _timer?.cancel();
    _timer = null;
    if (!on) return;
    final checkedAt = _checkedAt;
    if (checkedAt == null ||
        clock.now().difference(checkedAt) >= ewsRefreshInterval) {
      refresh();
    }
    _timer = Timer.periodic(ewsRefreshInterval, (_) => refresh());
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _api?.close();
    super.dispose();
  }
}
