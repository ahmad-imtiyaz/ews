import 'package:material_ui/material_ui.dart';

import '../../app_theme.dart';
import '../../data/monitoring.dart';
import '../../widgets/log_row.dart';
import '../status_report_sheet.dart';

/// Kartu catatan di bawah peta pendek, dan judul catatan sering dua baris.
/// Sisanya ada di halaman Lihat semua.
const logPreviewCount = 2;

List<LogItem> logItemsFrom(MonitoringData data) => [
  for (final entry in data.log)
    (
      status: entry.status,
      title: entry.title,
      note: entry.note,
      time: entry.time,
      at: entry.at,
    ),
];

class LogSection extends StatefulWidget {
  const LogSection({
    super.key,
    required this.data,
    required this.scrollable,
    required this.isRetrying,
    required this.onRetry,
    required this.onShowAll,
  });

  final MonitoringData data;
  final bool scrollable;
  final bool isRetrying;
  final VoidCallback onRetry;
  final VoidCallback onShowAll;

  @override
  State<LogSection> createState() => _LogSectionState();
}

class _LogSectionState extends State<LogSection> {
  // Pengendali sendiri, bukan milik halaman, karena menu Lapor yang hidup di
  // halaman yang sama juga punya daftar bergulir.
  final _scroll = ScrollController();

  MonitoringData get data => widget.data;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Widget _buildFailure(TextTheme textTheme) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(data.title, style: textTheme.titleMedium),
          const SizedBox(height: 2),
          Text(
            data.summary,
            style: textTheme.bodyLarge?.copyWith(color: AppColors.inkSoft),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: widget.isRetrying ? null : widget.onRetry,
            child: Text(widget.isRetrying ? 'Mengambil data...' : 'Coba lagi'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    final body = data.loadFailed
        ? _buildFailure(textTheme)
        : data.log.isEmpty
        ? Padding(
            padding: const EdgeInsets.all(14),
            child: Text(
              'Belum ada catatan. Perubahan status alat EWS akan muncul '
              'di sini.',
              style: textTheme.bodyLarge?.copyWith(color: AppColors.inkSoft),
            ),
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: logRows(
              logItemsFrom(data).take(logPreviewCount),
              onTap: (index) =>
                  showStatusReport(context, logItemsFrom(data), index),
            ),
          );

    final scrollable = widget.scrollable;
    final hasMore = !data.loadFailed && data.log.length > logPreviewCount;
    final card = Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Di HP yang layarnya pendek dua catatan pun bisa tidak muat.
          // Batang gulir selalu tampil supaya baris yang terpotong terbaca
          // sebagai "masih ada lagi".
          if (scrollable)
            Flexible(
              child: Scrollbar(
                controller: _scroll,
                thumbVisibility: true,
                child: SingleChildScrollView(controller: _scroll, child: body),
              ),
            )
          else
            body,
          if (hasMore) ...[
            const Divider(height: 1),
            LogFooterButton(
              label: 'Lihat semua (${data.log.length})',
              icon: Icons.chevron_right,
              onTap: widget.onShowAll,
            ),
          ],
        ],
      ),
    );

    return Column(
      mainAxisSize: scrollable ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Expanded(
                child: Text('Catatan terbaru', style: textTheme.titleMedium),
              ),
              if (data.updated != null)
                Text(
                  data.updated!,
                  style: textTheme.bodyMedium?.copyWith(
                    color: AppColors.inkSoft,
                  ),
                ),
            ],
          ),
        ),
        if (scrollable) Flexible(child: card) else card,
      ],
    );
  }
}
