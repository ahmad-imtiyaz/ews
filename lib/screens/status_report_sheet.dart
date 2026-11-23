import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../data/ews_data.dart';
import '../data/monitoring.dart';
import '../services/ews_history.dart';
import '../widgets/log_row.dart';
import '../widgets/sheet_frame.dart';
import '../widgets/status_icon.dart';

typedef ReadingsLoader = Future<PastReadings> Function(DateTime at);

/// Report untuk `items[index]`. [items] urut terbaru di atas, jadi catatan
/// sesudahnya ada di `index - 1`.
void showStatusReport(
  BuildContext context,
  List<LogItem> items,
  int index, {
  ReadingsLoader load = fetchReadingsAt,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => StatusReportSheet(
      item: items[index],
      next: index > 0 ? items[index - 1] : null,
      load: load,
    ),
  );
}

const _sensorIcons = {
  'kelembapan_tanah': Icons.water_drop_outlined,
  'intensitas_hujan': Icons.thunderstorm_outlined,
  'kemiringan': Icons.landscape_outlined,
  'kelembapan_udara': Icons.air,
};

const _days = ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'];
const _months = [
  'Januari',
  'Februari',
  'Maret',
  'April',
  'Mei',
  'Juni',
  'Juli',
  'Agustus',
  'September',
  'Oktober',
  'November',
  'Desember',
];

String _two(int part) => part.toString().padLeft(2, '0');
String _clockOf(DateTime time) => '${_two(time.hour)}.${_two(time.minute)}';

/// "Senin, 23 November 2026, 17.43 WIB"
String fullDateLabel(DateTime time) =>
    '${_days[time.weekday - 1]}, ${time.day} ${_months[time.month - 1]} '
    '${time.year}, ${_clockOf(time)} WIB';

String _ago(DateTime time) {
  final age = clock.now().difference(time);
  if (age.inMinutes < 1) return 'baru saja';
  if (age.inHours < 1) return '${age.inMinutes} menit lalu';
  if (age.inDays < 1) return '${age.inHours} jam lalu';
  return '${age.inDays} hari lalu';
}

String durationLabel(Duration span) {
  if (span.inMinutes < 1) return 'kurang dari 1 menit';
  if (span.inHours < 1) return '${span.inMinutes} menit';
  if (span.inDays < 1) {
    final minutes = span.inMinutes % 60;
    return minutes == 0
        ? '${span.inHours} jam'
        : '${span.inHours} jam $minutes menit';
  }
  return '${span.inDays} hari';
}

String? _advice(MonitoringStatus status) => switch (status) {
  MonitoringStatus.awas =>
    'Segera menjauh dari lereng dan ikuti arahan petugas.',
  MonitoringStatus.waspada => 'Siapkan diri dan pantau kabar dari petugas.',
  MonitoringStatus.noData =>
    'Kondisi saat itu tidak diketahui. Jangan anggap aman.',
  MonitoringStatus.normal => 'Semua sensor di bawah batas waspada.',
};

/// Sensor yang disebut di keterangan, mis. "Intensitas hujan 56,3%". Bila
/// tidak ada yang disebut (mis. "Kabel EWS putus"), sensor yang saat itu
/// melewati batas waspada.
Set<String> triggerKeys(
  String note,
  MonitoringStatus status,
  List<PastReading> readings,
) {
  if (status != MonitoringStatus.waspada && status != MonitoringStatus.awas) {
    return const {};
  }
  final text = note.toLowerCase();
  final named = {
    for (final reading in readings)
      if (text.contains(reading.name.toLowerCase())) reading.key,
  };
  if (named.isNotEmpty) return named;
  return {
    for (final reading in readings)
      if (reading.level case SensorLevel.waspada || SensorLevel.lewatBatas)
        reading.key,
  };
}

class StatusReportSheet extends StatefulWidget {
  const StatusReportSheet({
    super.key,
    required this.item,
    this.next,
    this.load = fetchReadingsAt,
  });

  final LogItem item;

  /// Catatan sesudahnya, untuk menghitung berapa lama status ini bertahan.
  /// `null` bila ini catatan terbaru.
  final LogItem? next;
  final ReadingsLoader load;

  @override
  State<StatusReportSheet> createState() => _StatusReportSheetState();
}

class _StatusReportSheetState extends State<StatusReportSheet> {
  late Future<PastReadings>? _readings = _start();

  Future<PastReadings>? _start() => switch (widget.item.at) {
    final at? => widget.load(at),
    null => null,
  };

  void _retry() => setState(() {
    _readings = _start();
  });

  String? _durationText() {
    final at = widget.item.at;
    final next = widget.next;
    if (next == null) {
      return 'Catatan terbaru, belum ada perubahan sesudahnya.';
    }
    final nextAt = next.at;
    if (at == null || nextAt == null) return null;
    final change = next.status == MonitoringStatus.noData
        ? 'lalu alat berhenti mengirim data'
        : 'lalu berubah jadi ${next.status.label}';
    // Hari yang sama dengan kejadiannya cukup jamnya.
    final when = timeLabel(nextAt, now: at);
    return 'Berlangsung ${durationLabel(nextAt.difference(at))}, $change '
        '${when.contains(',') ? 'pada' : 'pukul'} $when.';
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final item = widget.item;
    final at = item.at;
    final advice = _advice(item.status);
    final duration = _durationText();
    final device = ewsDevices.first;

    return SheetFrame(
      children: [
        Row(
          children: [
            StatusIcon(status: item.status, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.status.label,
                    style: textTheme.titleLarge?.copyWith(fontSize: 22),
                  ),
                  Text(
                    '${device.id} ${device.place}',
                    style: textTheme.bodyLarge?.copyWith(
                      color: AppColors.inkSoft,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(Icons.schedule, size: 18),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                at == null ? item.time : '${fullDateLabel(at)} · ${_ago(at)}',
                style: textTheme.bodyLarge,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        WhiteCard(
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.note.isEmpty ? item.title : item.note,
                    style: textTheme.titleMedium,
                  ),
                  if (advice != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      advice,
                      style: textTheme.bodyLarge?.copyWith(
                        color: AppColors.inkSoft,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (duration != null) ...[
              const Divider(height: 1, indent: 14, endIndent: 14),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(Icons.timelapse, size: 18),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(duration, style: textTheme.bodyLarge)),
                  ],
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 20),
        Text('Bacaan sensor saat itu', style: textTheme.titleMedium),
        const SizedBox(height: 4),
        _readingsSection(textTheme),
      ],
    );
  }

  Widget _readingsSection(TextTheme textTheme) {
    final muted = textTheme.bodyLarge?.copyWith(color: AppColors.inkSoft);
    final readings = _readings;
    if (readings == null) {
      return Text(
        'Jam kejadian tidak terbaca, jadi bacaan sensor saat itu tidak bisa '
        'diambil.',
        style: muted,
      );
    }

    return FutureBuilder<PastReadings>(
      future: readings,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Mengambil bacaan dari server...', style: muted),
                ),
              ],
            ),
          );
        }

        if (snapshot.error is TooOldForHistory) {
          return Text(
            'Server hanya menyimpan bacaan sensor 7 hari terakhir.',
            style: muted,
          );
        }

        final data = snapshot.data;
        if (data == null) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Bacaan sensor belum bisa diambil. Periksa sinyal.',
                style: muted,
              ),
              const SizedBox(height: 8),
              OutlinedButton(onPressed: _retry, child: const Text('Coba lagi')),
            ],
          );
        }

        if (data.readings.every((reading) => reading.value == null)) {
          return Text(
            'Alat tidak mengirim data antara ${_blockLabel(data)}.',
            style: muted,
          );
        }

        final triggers = triggerKeys(
          widget.item.note,
          widget.item.status,
          data.readings,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              data.step < const Duration(minutes: 2)
                  ? 'Bacaan pukul ${_clockOf(data.from)}.'
                  : 'Angka tertinggi antara ${_blockLabel(data)}.',
              style: textTheme.bodyMedium?.copyWith(color: AppColors.inkSoft),
            ),
            const SizedBox(height: 10),
            WhiteCard(
              children: [
                for (final (index, reading) in data.readings.indexed) ...[
                  if (index > 0) const Divider(height: 1),
                  _PastReadingRow(
                    reading: reading,
                    trigger: triggers.contains(reading.key)
                        ? widget.item.status
                        : null,
                  ),
                ],
              ],
            ),
          ],
        );
      },
    );
  }

  static String _blockLabel(PastReadings data) =>
      '${_clockOf(data.from)} dan ${_clockOf(data.from.add(data.step))}';
}

class _PastReadingRow extends StatelessWidget {
  const _PastReadingRow({required this.reading, this.trigger});

  final PastReading reading;

  /// Status yang dipicu sensor ini, atau `null` bila bukan pemicunya.
  final MonitoringStatus? trigger;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final trigger = this.trigger;
    final threshold = reading.threshold;
    final word = switch (reading.level) {
      _ when reading.value == null => 'Tidak ada kiriman saat itu',
      SensorLevel.normal => 'Normal',
      SensorLevel.waspada => 'Waspada',
      SensorLevel.lewatBatas => 'Lewat batas',
      SensorLevel.notRated => 'Hanya informasi',
    };
    final accent = trigger == MonitoringStatus.awas
        ? AppColors.awas
        : AppColors.waspada;

    // Pemicu disorot dengan garis tebal di kiri dan latar tipis, supaya
    // langsung terlihat sensor mana yang membuat notifikasi muncul.
    return DecoratedBox(
      decoration: trigger == null
          ? const BoxDecoration()
          : BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              border: Border(left: BorderSide(color: accent, width: 5)),
            ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(trigger == null ? 14 : 9, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (trigger != null) ...[
              Row(
                children: [
                  StatusIcon(status: trigger, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    'Pemicu notifikasi',
                    style: textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(_sensorIcons[reading.key] ?? Icons.sensors, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    reading.name,
                    style: textTheme.bodyLarge?.copyWith(
                      fontWeight: trigger == null ? null : FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  reading.text,
                  style: trigger == null
                      ? textTheme.titleMedium?.copyWith(
                          color: reading.value == null
                              ? AppColors.inkSoft
                              : null,
                        )
                      : const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                ),
              ],
            ),
            if (reading.judged != null && threshold != null) ...[
              const SizedBox(height: 8),
              _ThresholdBar(
                value: reading.judged!,
                max: reading.key == 'kemiringan' ? 90 : 100,
                waspada: threshold.waspada,
              ),
            ],
            const SizedBox(height: 4),
            Text(
              threshold == null
                  ? word
                  : '$word · waspada mulai '
                        '${formatNumber(threshold.waspada)}${reading.unit}',
              style: textTheme.bodyMedium?.copyWith(color: AppColors.inkSoft),
            ),
          ],
        ),
      ),
    );
  }
}

/// Batang nilai dengan garis batas waspada, supaya terlihat seberapa jauh
/// angka itu dari batasnya.
class _ThresholdBar extends StatelessWidget {
  const _ThresholdBar({
    required this.value,
    required this.max,
    required this.waspada,
  });

  final double value;
  final double max;
  final double waspada;

  @override
  Widget build(BuildContext context) {
    final fill = (value / max).clamp(0.0, 1.0);
    final mark = (waspada / max).clamp(0.0, 1.0);

    return ExcludeSemantics(
      child: SizedBox(
        height: 12,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            return Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.centerLeft,
              children: [
                Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                Container(
                  height: 6,
                  width: width * fill,
                  decoration: BoxDecoration(
                    color: AppColors.ink,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                Positioned(
                  left: (width * mark - 1).clamp(0.0, width - 2),
                  top: 0,
                  bottom: 0,
                  child: const SizedBox(
                    width: 2,
                    child: ColoredBox(color: AppColors.inkSoft),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
