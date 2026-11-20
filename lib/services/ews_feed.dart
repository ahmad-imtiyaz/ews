import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

import '../config.dart';
import '../data/ews_data.dart';
import 'crash_reports.dart';
import 'ews_api.dart';
import 'ews_cache.dart';

/// Satu pengambil data EWS untuk Beranda, Sensor, dan lonceng, supaya server
/// cukup dipanggil sekali tiap 10 detik walau beberapa menu memakainya.
class EwsFeed extends ChangeNotifier {
  /// Tanpa [load], data diambil dari server dan disimpan ke [cache] (bawaan:
  /// simpanan HP). Tes yang mengisi [load] tidak memakai simpanan kecuali
  /// [cache] diisi.
  EwsFeed({Future<EwsData> Function()? load, EwsCache? cache})
    : _cache = cache ?? (load == null ? EwsCache() : null) {
    if (load != null) {
      _load = load;
    } else {
      final api = _api = EwsApi(
        ewsBaseUrl,
        onNewBody: (body) => _newBody = body,
      );
      _load = api.fetch;
    }
  }

  late final Future<EwsData> Function() _load;
  final EwsCache? _cache;
  EwsApi? _api;
  Timer? _timer;
  Future<void>? _pending;
  bool _disposed = false;
  String? _newBody;

  EwsData? _data;
  DateTime? _checkedAt;
  bool _failed = false;
  bool _fromCache = false;

  /// Data terakhir yang berhasil diambil. Tetap ada saat sinyal putus, dan
  /// sejak [restore] juga saat aplikasi baru dibuka tanpa sinyal.
  EwsData? get data => _data;

  /// Kapan [data] terakhir dipastikan sama dengan server.
  DateTime? get checkedAt => _checkedAt;

  /// Pengambilan terakhir gagal.
  bool get failed => _failed;
  bool get busy => _pending != null;

  /// [data] dari simpanan HP dan belum sekali pun dipastikan ke server sejak
  /// aplikasi dibuka.
  bool get fromCache => _fromCache;

  /// [data] lebih lama dari [ewsStaleAfter], jadi bukan gambaran kondisi
  /// sekarang.
  bool get isStale {
    final checkedAt = _checkedAt;
    return checkedAt != null &&
        clock.now().difference(checkedAt) >= ewsStaleAfter;
  }

  /// Mengisi [data] dari simpanan HP bila belum ada data dari server.
  Future<void> restore() async {
    final saved = await _cache?.read();
    if (saved == null || _data != null || _disposed) return;
    _data = saved.data;
    _checkedAt = saved.checkedAt;
    _fromCache = true;
    notifyListeners();
  }

  /// Sinyal desa bisa lambat, jadi permintaan baru menunggu yang masih jalan.
  Future<void> refresh() => _pending ??= _fetch().whenComplete(() {
    _pending = null;
    if (!_disposed) notifyListeners();
  });

  Future<void> _fetch() async {
    try {
      _data = await _load();
      _failed = false;
      _fromCache = false;
      final checkedAt = _checkedAt = clock.now();
      unawaited(_cache?.save(body: _newBody, checkedAt: checkedAt));
    } catch (error, stack) {
      _failed = true;
      // Sinyal putus itu biasa. TypeError berarti JSON-nya terbaca tapi
      // bentuknya berubah di server, dan warga akan terus melihat "Belum
      // tersambung" sampai aplikasi diperbaiki.
      if (error is TypeError) {
        CrashReports.record(error, stack, reason: 'membaca data server');
      }
    } finally {
      _newBody = null;
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
    if (_fromCache ||
        checkedAt == null ||
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
