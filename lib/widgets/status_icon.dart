import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../data/monitoring.dart';

/// Ikon garis per status untuk kartu putih. Tiap status punya gambar sendiri
/// (centang, segitiga, segi delapan, sensor dicoret), jadi tetap terbaca
/// tanpa melihat warna. Peta tetap memakai [StatusShape] yang berisi warna
/// penuh supaya terlihat di atas citra satelit.
class StatusIcon extends StatelessWidget {
  const StatusIcon({super.key, required this.status, this.size = 24});

  final MonitoringStatus status;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (status) {
      MonitoringStatus.normal => (
        Icons.check_circle_outline_rounded,
        AppColors.normal,
      ),
      MonitoringStatus.waspada => (
        Icons.warning_amber_rounded,
        AppColors.waspadaOnWhite,
      ),
      MonitoringStatus.awas => (Icons.dangerous_outlined, AppColors.awas),
      MonitoringStatus.noData => (Icons.sensors_off_outlined, AppColors.stale),
    };
    return Icon(icon, size: size, color: color);
  }
}
