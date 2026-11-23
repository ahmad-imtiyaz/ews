import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../services/ews_feed.dart';
import '../widgets/log_row.dart';
import '../widgets/top_bar.dart';
import 'status_report_sheet.dart';

/// Semua catatan dari Beranda atau Sensor. Server mengirim puluhan perubahan,
/// jadi daftar dibuka sebagian dulu. Isinya ikut diperbarui selama halaman
/// terbuka.
class LogScreen extends StatefulWidget {
  const LogScreen({
    super.key,
    required this.title,
    required this.feed,
    required this.items,
  });

  final String title;
  final EwsFeed feed;

  /// Dibaca ulang tiap kali [feed] mengambil data baru.
  final List<LogItem> Function() items;

  static const pageSize = 15;

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  int _shown = LogScreen.pageSize;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: TopBar(title: widget.title, backLabel: 'Kembali'),
      body: ListenableBuilder(
        listenable: widget.feed,
        builder: (context, _) {
          final items = widget.items();
          final left = items.length - _shown;

          return ListView(
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              16,
              MediaQuery.paddingOf(context).bottom + 16,
            ),
            children: [
              Text(
                items.isEmpty
                    ? 'Perubahan status alat EWS akan muncul di sini.'
                    : '${items.length} catatan, terbaru di atas. Ketuk '
                          'catatan untuk melihat report-nya.',
                style: textTheme.bodyMedium?.copyWith(color: AppColors.inkSoft),
              ),
              const SizedBox(height: 12),
              if (items.isNotEmpty)
                Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ...logRows(
                        items.take(_shown),
                        onTap: (index) =>
                            showStatusReport(context, items, index),
                      ),
                      if (left > 0) ...[
                        const Divider(height: 1),
                        LogFooterButton(
                          label: left > LogScreen.pageSize
                              ? 'Tampilkan ${LogScreen.pageSize} lagi '
                                    '(sisa $left)'
                              : 'Tampilkan $left lagi',
                          icon: Icons.expand_more,
                          onTap: () =>
                              setState(() => _shown += LogScreen.pageSize),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
