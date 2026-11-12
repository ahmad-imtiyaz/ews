import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../data/ews_data.dart';
import '../data/monitoring.dart';
import '../services/ews_feed.dart';
import '../services/notification_inbox.dart';
import '../widgets/notification_bell.dart';
import '../widgets/status_icon.dart';
import '../widgets/top_bar.dart';

const _pagePadding = 16.0;
const _sectionGap = 24.0;
const _cardGap = 10.0;

const _sensorIcons = {
  'tanah': Icons.water_drop_outlined,
  'hujan': Icons.thunderstorm_outlined,
  'miring': Icons.landscape_outlined,
  'udara': Icons.air,
};

String _clock(DateTime time) => [
  time.hour,
  time.minute,
  time.second,
].map((part) => part.toString().padLeft(2, '0')).join('.');

/// Menampilkan wilayah bersensor dari server. Baru EWS-02 yang terhubung
/// (lihat `ewsDeviceOfArea` di config.dart).
class SensorScreen extends StatelessWidget {
  const SensorScreen({super.key, required this.feed, this.inbox});

  /// Diambil berkala oleh MainShell selama aplikasi terbuka.
  final EwsFeed feed;

  /// Lonceng di bar atas. Kosong di tes yang membuka halaman ini sendiri.
  final NotificationInbox? inbox;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      appBar: TopBar(
        actions: [
          if (inbox case final inbox?) NotificationBell(inbox: inbox),
        ],
      ),
      body: ListenableBuilder(
        listenable: feed,
        builder: (context, _) {
          final data = feed.data;
          if (data == null) {
            return Padding(
              padding: EdgeInsets.only(bottom: bottomInset),
              child: feed.failed
                  ? _FirstLoadFailed(busy: feed.busy, onRetry: feed.refresh)
                  : const _FirstLoad(),
            );
          }
          return RefreshIndicator(
            onRefresh: feed.refresh,
            color: AppColors.ink,
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                _pagePadding,
                8,
                _pagePadding,
                bottomInset + _pagePadding,
              ),
              children: _content(context, data),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _content(BuildContext context, EwsData data) {
    final note = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(color: AppColors.inkSoft);

    return [
      if (feed.failed) ...[
        _Notice(
          icon: Icons.cloud_off_outlined,
          title: 'Belum tersambung ke server',
          body:
              'Angka di bawah dari pengecekan ${_clock(feed.checkedAt!)}. '
              'Aplikasi mencoba lagi tiap 10 detik.',
        ),
        const SizedBox(height: 10),
      ],
      // Alat yang diam saat Waspada tidak boleh terbaca sudah aman, jadi
      // kalimat dari server ditaruh paling atas.
      for (final text in data.offlineNotices) ...[
        _Notice(
          icon: Icons.sensors_off_outlined,
          title: 'Alat tidak mengirim data',
          body: text,
        ),
        const SizedBox(height: 10),
      ],
      _SummaryCard(data: data),
      if (!feed.failed) ...[
        const SizedBox(height: 8),
        Text(
          'Diperbarui tiap 10 detik, terakhir dicek '
          '${_clock(feed.checkedAt!)}',
          style: note,
        ),
      ],
      if (data.areas.isEmpty) ...[
        const SizedBox(height: _sectionGap),
        const _Notice(
          icon: Icons.sensors_off_outlined,
          title: 'Belum ada alat terdaftar',
          body:
              'Bacaan sensor muncul di sini setelah alat EWS dipasang dan '
              'mulai mengirim data.',
        ),
      ],
      for (final area in data.areas) ...[
        const SizedBox(height: _sectionGap),
        _AreaSection(
          area: area,
          thresholds: data.thresholds,
          showStatus: data.areas.length > 1,
        ),
      ],
      const SizedBox(height: _sectionGap),
      _StatusLog(data: data),
      const SizedBox(height: 16),
      Text(
        'Ini alat bantu pemantauan warga, bukan peringatan resmi BPBD. Saat '
        'ragu, utamakan keselamatan dan ikuti arahan perangkat desa.',
        style: note,
      ),
    ];
  }
}

class _FirstLoad extends StatelessWidget {
  const _FirstLoad();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: AppColors.ink),
          const SizedBox(height: 14),
          Text(
            'Mengambil data sensor...',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }
}

class _FirstLoadFailed extends StatelessWidget {
  const _FirstLoadFailed({required this.busy, required this.onRetry});

  final bool busy;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 32),
            const SizedBox(height: 10),
            Text(
              'Belum bisa mengambil data sensor',
              textAlign: TextAlign.center,
              style: textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Periksa sinyal. Aplikasi mencoba lagi tiap 10 detik.',
              textAlign: TextAlign.center,
              style: textTheme.bodyLarge?.copyWith(color: AppColors.inkSoft),
            ),
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: busy ? null : onRetry,
              child: Text(busy ? 'Mengambil data...' : 'Coba lagi'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(body, style: textTheme.bodyLarge),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.data});

  final EwsData data;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final summary = data.summary;
    final status = summary.statusKind;
    final location = summary.location;
    final time = summary.time;
    final place = [
      if (location != null) areaLabel(data, location),
      if (time != null) 'bacaan ${shortTime(time)}',
    ].join(', ');
    // Saat Aman, pemicunya "Semua sensor normal", sama dengan kalimat pertama
    // saran.
    final trigger = status == MonitoringStatus.normal ? null : summary.trigger;
    final hasDetail = trigger != null || summary.advice.isNotEmpty;

    // Kartu putih seperti kartu lain. Warna status hanya di bentuknya, sama
    // seperti penanda di peta, jadi satu-satunya warna di atas adalah status.
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                StatusIcon(status: status, size: 40),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        summary.status ?? 'Belum ada data',
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          height: 1.15,
                        ),
                      ),
                      if (place.isNotEmpty)
                        Text(
                          place,
                          style: textTheme.bodyMedium?.copyWith(
                            color: AppColors.inkSoft,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (hasDetail) ...[
              const SizedBox(height: 14),
              const Divider(),
              const SizedBox(height: 12),
            ],
            if (trigger != null)
              Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(
                      text: 'Penyebab: ',
                      style: TextStyle(color: AppColors.inkSoft),
                    ),
                    TextSpan(
                      text: trigger,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                style: textTheme.bodyLarge,
              ),
            if (trigger != null && summary.advice.isNotEmpty)
              const SizedBox(height: 6),
            if (summary.advice.isNotEmpty)
              Text(summary.advice, style: textTheme.bodyLarge),
          ],
        ),
      ),
    );
  }
}

class _AreaSection extends StatelessWidget {
  const _AreaSection({
    required this.area,
    required this.thresholds,
    required this.showStatus,
  });

  final EwsArea area;
  final Map<String, EwsThreshold> thresholds;

  /// Dengan satu wilayah, statusnya sudah tampil di kartu besar di atas.
  final bool showStatus;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final time = area.time == null ? '-' : shortTime(area.time!);
    final columns = MediaQuery.textScalerOf(context).scale(1) > 1.3 ? 1 : 2;
    final sensors = area.sensors;
    final device = deviceOfArea(area);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                device == null ? area.name : '${device.id} ${device.place}',
                style: textTheme.titleLarge,
              ),
            ),
            if (showStatus) ...[
              const SizedBox(width: 8),
              _AreaStatus(area: area),
            ],
          ],
        ),
        const SizedBox(height: 4),
        if (area.offline)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(Icons.sensors_off_outlined, size: 18),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Alat tidak mengirim data sejak $time',
                  style: textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          )
        else
          Text(
            'Bacaan $time',
            style: textTheme.bodyMedium?.copyWith(color: AppColors.inkSoft),
          ),
        const SizedBox(height: 10),
        for (var i = 0; i < sensors.length; i += columns) ...[
          if (i > 0) const SizedBox(height: _cardGap),
          // Kartu sebaris sama tinggi walau nama sensornya beda panjang.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var j = i; j < i + columns; j++) ...[
                  if (j > i) const SizedBox(width: _cardGap),
                  Expanded(
                    child: j < sensors.length
                        ? _SensorCard(
                            sensor: sensors[j],
                            threshold: thresholds[sensors[j].key],
                            stale: area.offline,
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _AreaStatus extends StatelessWidget {
  const _AreaStatus({required this.area});

  final EwsArea area;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        StatusIcon(status: area.statusKind, size: 22),
        const SizedBox(width: 6),
        Text(
          area.status ?? 'Belum ada data',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ],
    );
  }
}

class _SensorCard extends StatelessWidget {
  const _SensorCard({
    required this.sensor,
    required this.threshold,
    required this.stale,
  });

  final EwsSensor sensor;
  final EwsThreshold? threshold;

  /// Alat sedang tidak mengirim, jadi angka ini bacaan lama.
  final bool stale;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final threshold = this.threshold;
    final footnote = stale
        ? 'Data lama'
        : threshold == null
        ? null
        : 'Waspada mulai ${formatNumber(threshold.waspada)}${sensor.unit}';
    // Kelembapan udara tidak ikut menentukan status, jadi kartunya lebih
    // tenang: tanpa isi putih, hanya garis tepi.
    final informational =
        sensor.level == SensorLevel.notRated && sensor.value != null;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: informational ? null : Colors.white,
        border: informational ? Border.all(color: AppColors.border) : null,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(_sensorIcons[sensor.icon] ?? Icons.sensors, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(sensor.name, style: textTheme.titleMedium),
                ),
              ],
            ),
            // Angka dan label rata bawah dengan kartu di sebelahnya.
            const Spacer(),
            const SizedBox(height: 10),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                sensor.text,
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                  color: stale ? AppColors.stale : AppColors.ink,
                ),
              ),
            ),
            const SizedBox(height: 8),
            _LevelLine(sensor: sensor, stale: stale),
            if (footnote != null) ...[
              const SizedBox(height: 6),
              Text(
                footnote,
                style: textTheme.bodyMedium?.copyWith(color: AppColors.inkSoft),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Bentuk status yang sama dengan penanda peta, lalu katanya. Bentuk
/// membuat status terbaca tanpa melihat warna.
class _LevelLine extends StatelessWidget {
  const _LevelLine({required this.sensor, required this.stale});

  final EwsSensor sensor;
  final bool stale;

  @override
  Widget build(BuildContext context) {
    // Bacaan lama yang Normal belum tentu masih aman, jadi tanpa bentuk dan
    // abu-abu. Bacaan lama yang Waspada tetap ditandai: alat bisa mati
    // justru karena tanahnya bergerak.
    final shape = sensor.value == null
        ? MonitoringStatus.noData
        : switch (sensor.level) {
            SensorLevel.normal => stale ? null : MonitoringStatus.normal,
            SensorLevel.waspada ||
            SensorLevel.lewatBatas => MonitoringStatus.waspada,
            SensorLevel.notRated => null,
          };

    return Row(
      children: [
        if (shape != null) ...[
          StatusIcon(status: shape, size: 20),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            sensor.word,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: shape == null ? AppColors.inkSoft : AppColors.ink,
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusLog extends StatelessWidget {
  const _StatusLog({required this.data});

  final EwsData data;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final log = data.log;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Perubahan status', style: textTheme.titleMedium),
        const SizedBox(height: 10),
        DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: log.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    'Belum ada perubahan status.',
                    style: textTheme.bodyLarge?.copyWith(
                      color: AppColors.inkSoft,
                    ),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (index, entry) in log.indexed) ...[
                      if (index > 0) const Divider(indent: 48, endIndent: 14),
                      _StatusLogRow(
                        entry: entry,
                        place: areaLabel(data, entry.area),
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _StatusLogRow extends StatelessWidget {
  const _StatusLogRow({required this.entry, required this.place});

  final EwsLogEntry entry;
  final String place;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StatusIcon(status: entry.statusKind, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${entry.status ?? 'Tidak ada data'} · $place',
                  style: textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (entry.note.isNotEmpty)
                  Text(entry.note, style: textTheme.bodyLarge),
                const SizedBox(height: 2),
                Text(
                  shortTime(entry.time),
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
