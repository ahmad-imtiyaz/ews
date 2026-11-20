import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/monitoring.dart';
import 'notification_service.dart';

class NotificationEntry {
  const NotificationEntry({
    required this.status,
    required this.title,
    required this.body,
    required this.time,
  });

  final MonitoringStatus status;
  final String title;
  final String body;
  final DateTime time;

  Map<String, Object> toJson() => {
    'status': status.name,
    'title': title,
    'body': body,
    'time': time.toIso8601String(),
  };

  factory NotificationEntry.fromJson(Map<String, dynamic> json) =>
      NotificationEntry(
        status:
            MonitoringStatus.values.asNameMap()[json['status']] ??
            MonitoringStatus.noData,
        title: json['title'] as String,
        body: json['body'] as String,
        time: DateTime.parse(json['time'] as String),
      );
}

/// Riwayat lonceng, satu untuk semua menu, supaya hitungan belum dibaca sama
/// di Beranda, Lapor, dan Sensor. Disimpan di HP, jadi peringatan semalam
/// masih ada setelah aplikasi ditutup.
class NotificationInbox extends ChangeNotifier {
  NotificationInbox({NotificationService? service})
    : service = service ?? NotificationService() {
    _loaded = _load();
  }

  static const _key = 'notifications';

  /// Lebih dari ini, yang paling lama dibuang.
  static const maxEntries = 50;

  final NotificationService service;

  /// Terlama di depan.
  final entries = <NotificationEntry>[];
  int _unread = 0;
  late final Future<void> _loaded;
  bool _disposed = false;

  int get unread => _unread;

  /// Selesai saat riwayat dari HP sudah terbaca.
  Future<void> get ready => _loaded;

  Future<void> _load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw == null || _disposed) return;
      final saved = jsonDecode(raw) as Map<String, dynamic>;
      // Yang tercatat selagi simpanan dibaca tetap di belakang.
      entries.insertAll(0, [
        for (final entry in saved['entries'] as List)
          NotificationEntry.fromJson(entry as Map<String, dynamic>),
      ]);
      _unread += saved['unread'] as int? ?? 0;
      _trim();
      notifyListeners();
    } catch (_) {
      // Simpanan rusak: mulai dari riwayat kosong.
    }
  }

  Future<void> _save() async {
    await _loaded;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode({
          'unread': _unread,
          'entries': [for (final entry in entries) entry.toJson()],
        }),
      );
    } catch (_) {}
  }

  void _trim() {
    if (entries.length > maxEntries) {
      entries.removeRange(0, entries.length - maxEntries);
    }
    if (_unread > entries.length) _unread = entries.length;
  }

  void add(NotificationEntry entry) {
    entries.add(entry);
    _unread++;
    _trim();
    notifyListeners();
    _save();
  }

  void markRead() {
    if (_unread == 0) return;
    _unread = 0;
    notifyListeners();
    _save();
  }

  @override
  void dispose() {
    _disposed = true;
    service.dispose();
    super.dispose();
  }
}
