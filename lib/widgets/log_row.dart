import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../data/monitoring.dart';
import 'status_icon.dart';

typedef LogItem = ({
  MonitoringStatus status,
  String title,
  String note,
  String time,
});

/// Satu baris catatan perubahan status. Jam di kanan judul supaya tiap baris
/// cukup dua tingkat dan daftar panjang tetap mudah dipindai.
class LogRow extends StatelessWidget {
  const LogRow({super.key, required this.item});

  final LogItem item;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final (:status, :title, :note, :time) = item;
    // Teks besar tidak muat berdampingan, jadi jam turun ke bawah.
    final timeBelow = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final titleText = Text(
      title,
      style: textTheme.bodyLarge?.copyWith(
        fontWeight: FontWeight.w600,
        height: 1.3,
      ),
    );
    final timeText = Text(
      time,
      style: textTheme.bodyMedium?.copyWith(color: AppColors.inkSoft),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StatusIcon(status: status, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (time.isEmpty || timeBelow)
                  titleText
                else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: titleText),
                      const SizedBox(width: 8),
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: timeText,
                      ),
                    ],
                  ),
                if (note.isNotEmpty)
                  Text(
                    note,
                    style: textTheme.bodyLarge?.copyWith(
                      color: AppColors.inkSoft,
                    ),
                  ),
                if (time.isNotEmpty && timeBelow) timeText,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Baris catatan dengan garis pemisah, untuk isi kartu putih.
List<Widget> logRows(Iterable<LogItem> items) => [
  for (final (index, item) in items.indexed) ...[
    if (index > 0) const Divider(indent: 48, endIndent: 14),
    LogRow(item: item),
  ],
];

/// Tombol di dasar kartu catatan, mis. "Lihat semua (50)".
class LogFooterButton extends StatelessWidget {
  const LogFooterButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Icon(icon, size: 22, color: AppColors.ink),
            ],
          ),
        ),
      ),
    );
  }
}
