import 'package:material_ui/material_ui.dart';

import '../../app_theme.dart';
import '../../data/ews_data.dart';
import '../../data/monitoring.dart';
import '../../widgets/sheet_frame.dart';
import '../../widgets/status_icon.dart';

class SensorSheet extends StatelessWidget {
  const SensorSheet({super.key, required this.sensor});

  final SensorPoint sensor;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final area = sensor.area;
    final time = area?.time == null ? '-' : shortTime(area!.time!);
    final trigger = sensor.status == MonitoringStatus.normal
        ? null
        : area?.trigger;

    return SheetFrame(
      children: [
        Text('${sensor.id}, ${sensor.place}', style: textTheme.titleLarge),
        const SizedBox(height: 12),
        WhiteCard(
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StatusIcon(status: sensor.status, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          area == null
                              ? 'Belum terhubung'
                              : sensor.status.label,
                          style: textTheme.titleMedium,
                        ),
                        if (trigger != null)
                          Text(trigger, style: textTheme.bodyLarge),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (area == null)
          Text(
            'Alat ini belum mengirim data ke server, jadi belum ada bacaan.',
            style: textTheme.bodyLarge?.copyWith(color: AppColors.inkSoft),
          )
        else ...[
          Text(
            area.offline ? 'Tidak mengirim data sejak $time' : 'Bacaan $time',
            style: textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          WhiteCard(
            children: [
              for (final (index, reading) in area.sensors.indexed) ...[
                if (index > 0) const Divider(indent: 14, endIndent: 14),
                _ReadingRow(reading: reading, stale: area.offline),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

class _ReadingRow extends StatelessWidget {
  const _ReadingRow({required this.reading, required this.stale});

  final EwsSensor reading;
  final bool stale;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(reading.name, style: textTheme.bodyLarge)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  reading.text,
                  textAlign: TextAlign.end,
                  style: textTheme.labelLarge?.copyWith(
                    color: stale ? AppColors.stale : null,
                  ),
                ),
                Text(
                  stale ? 'Data lama' : reading.word,
                  textAlign: TextAlign.end,
                  style: textTheme.bodyMedium?.copyWith(
                    color: AppColors.inkSoft,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
