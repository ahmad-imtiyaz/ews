import 'package:flutter/foundation.dart';

import '../data/sample_data.dart';
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
  final String time;
}

/// Riwayat lonceng, satu untuk semua menu, supaya hitungan belum dibaca sama
/// di Beranda, Lapor, dan Sensor.
class NotificationInbox extends ChangeNotifier {
  NotificationInbox({NotificationService? service})
    : service = service ?? NotificationService();

  final NotificationService service;
  final entries = <NotificationEntry>[];
  int _unread = 0;

  int get unread => _unread;

  void add(NotificationEntry entry) {
    entries.add(entry);
    _unread++;
    notifyListeners();
  }

  void markRead() {
    if (_unread == 0) return;
    _unread = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    service.dispose();
    super.dispose();
  }
}
