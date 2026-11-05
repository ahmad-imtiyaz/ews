import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';

import '../app_theme.dart';
import '../data/sample_data.dart';
import '../widgets/map_markers.dart';
import 'report_placeholder_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.initialData,
    this.load = loadMonitoring,
    this.showMapTiles = true,
  });

  final MonitoringData initialData;
  final Future<MonitoringData> Function() load;
  final bool showMapTiles;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late MonitoringData _data = widget.initialData;
  bool _isRetrying = false;

  Future<void> _retryLoad() async {
    setState(() => _isRetrying = true);
    MonitoringData? loaded;
    try {
      loaded = await widget.load();
    } catch (_) {
      loaded = null;
    }
    if (!mounted) return;
    setState(() {
      _isRetrying = false;
      _data = loaded ?? _data;
    });
    if (loaded == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Masih belum bisa memuat data.')),
      );
    }
  }

  Future<void> _showScenarioPicker() async {
    final picked = await showModalBottomSheet<MonitoringData>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ScenarioSheet(selected: _data),
    );
    if (picked != null) setState(() => _data = picked);
  }

  void _showSheet(Widget sheet) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => sheet,
    );
  }

  @override
  Widget build(BuildContext context) {
    final topBar = _TopBar(onSampleTap: _showScenarioPicker);
    final band = _StatusBand(
      data: _data,
      isRetrying: _isRetrying,
      onRetry: _retryLoad,
    );
    final map = _MapPanel(
      data: _data,
      showTiles: widget.showMapTiles,
      onSensorTap: (sensor) => _showSheet(_SensorSheet(sensor: sensor)),
      onReportTap: (report) => _showSheet(_ReportSheet(report: report)),
    );

    // Teks yang diperbesar tidak muat dalam susunan tetap, jadi halaman digulir.
    final isLargeText = MediaQuery.textScalerOf(context).scale(1) > 1.3;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: isLargeText
                    ? ListView(
                        children: [
                          topBar,
                          band,
                          SizedBox(height: 260, child: map),
                          _LogSection(data: _data, scrollable: false),
                        ],
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) => Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            topBar,
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxHeight: constraints.maxHeight * 0.36,
                              ),
                              child: band,
                            ),
                            Expanded(flex: 3, child: map),
                            Expanded(flex: 2, child: _LogSection(data: _data)),
                          ],
                        ),
                      ),
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ReportPlaceholderScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.edit_note, size: 28),
                  label: const Text('Buat laporan'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onSampleTap});

  final VoidCallback onSampleTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 4,
        children: [
          Text('EWS Lumeneng', style: Theme.of(context).textTheme.titleLarge),
          Semantics(
            label: 'Data contoh. Ganti contoh keadaan.',
            excludeSemantics: true,
            child: OutlinedButton(
              onPressed: onSampleTap,
              child: const Text('Data contoh'),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBand extends StatelessWidget {
  const _StatusBand({
    required this.data,
    required this.isRetrying,
    required this.onRetry,
  });

  final MonitoringData data;
  final bool isRetrying;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final foreground = data.status.foreground;
    final textTheme = Theme.of(context).textTheme;

    return ColoredBox(
      color: data.status.background,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                StatusShape(status: data.status, size: 36),
                const SizedBox(width: 10),
                Expanded(
                  // Kata status sudah besar, jadi skalanya dibatasi agar tidak
                  // terpotong di tengah kata.
                  child: MediaQuery.withClampedTextScaling(
                    maxScaleFactor: 1.5,
                    child: Text(
                      data.title,
                      style: textTheme.headlineLarge?.copyWith(
                        color: foreground,
                        height: 1.1,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              data.summary,
              style: textTheme.bodyLarge?.copyWith(color: foreground),
            ),
            if (data.updated != null)
              Text(
                data.updated!,
                style: textTheme.bodyLarge?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w700,
                ),
              ),
            if (data.loadFailed) ...[
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: isRetrying ? null : onRetry,
                child: Text(isRetrying ? 'Mengambil data...' : 'Coba lagi'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MapPanel extends StatefulWidget {
  const _MapPanel({
    required this.data,
    required this.showTiles,
    required this.onSensorTap,
    required this.onReportTap,
  });

  final MonitoringData data;
  final bool showTiles;
  final ValueChanged<SensorPoint> onSensorTap;
  final ValueChanged<ReportPoint> onReportTap;

  @override
  State<_MapPanel> createState() => _MapPanelState();
}

class _MapPanelState extends State<_MapPanel> {
  static const _grayscale = ColorFilter.matrix([
    0.2126,
    0.7152,
    0.0722,
    0,
    0,
    0.2126,
    0.7152,
    0.0722,
    0,
    0,
    0.2126,
    0.7152,
    0.0722,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ]);

  final _controller = MapController();
  int _tileAttempt = 0;
  bool _tilesFailed = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _zoomBy(double delta) {
    final camera = _controller.camera;
    _controller.move(camera.center, camera.zoom + delta);
  }

  void _retryTiles() {
    setState(() {
      _tilesFailed = false;
      _tileAttempt++;
    });
  }

  void _onTileError(TileImage tile, Object error, StackTrace? stackTrace) {
    if (mounted && !_tilesFailed) setState(() => _tilesFailed = true);
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: ColoredBox(
        color: AppColors.mapBackground,
        child: Stack(
          children: [
            FlutterMap(
              mapController: _controller,
              options: const MapOptions(
                initialCenter: mapCenter,
                initialZoom: 14,
                minZoom: 11,
                maxZoom: 18,
                backgroundColor: AppColors.mapBackground,
                interactionOptions: InteractionOptions(
                  flags:
                      InteractiveFlag.drag |
                      InteractiveFlag.pinchZoom |
                      InteractiveFlag.doubleTapZoom,
                ),
              ),
              children: [
                if (widget.showTiles)
                  TileLayer(
                    key: ValueKey(_tileAttempt),
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'id.kkn.ews_lumeneng',
                    errorTileCallback: _onTileError,
                    tileBuilder: (context, tile, _) =>
                        ColorFiltered(colorFilter: _grayscale, child: tile),
                  ),
                MarkerLayer(
                  markers: [
                    for (final report in widget.data.reports)
                      Marker(
                        point: report.position,
                        width: 112,
                        height: 64,
                        child: ReportMarkerButton(
                          report: report,
                          onTap: () => widget.onReportTap(report),
                        ),
                      ),
                    for (final sensor in widget.data.sensors)
                      Marker(
                        point: sensor.position,
                        width: 112,
                        height: 64,
                        child: SensorMarkerButton(
                          sensor: sensor,
                          onTap: () => widget.onSensorTap(sensor),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            const Positioned(left: 0, top: 0, child: _MapAttribution()),
            if (_tilesFailed)
              Positioned(
                left: 8,
                right: 8,
                top: 8,
                child: _MapFailureNotice(onRetry: _retryTiles),
              ),
            Positioned(
              right: 8,
              bottom: 8,
              child: MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.2,
                child: Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _zoomBy(1),
                      icon: const Icon(Icons.add),
                      label: const Text('Perbesar'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () => _zoomBy(-1),
                      icon: const Icon(Icons.remove),
                      label: const Text('Perkecil'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapAttribution extends StatelessWidget {
  const _MapAttribution();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Colors.white,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          '© OpenStreetMap',
          textScaler: TextScaler.noScaling,
          style: TextStyle(fontSize: 12, color: AppColors.ink),
        ),
      ),
    );
  }
}

class _MapFailureNotice extends StatelessWidget {
  const _MapFailureNotice({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.ink, width: 1.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            const Expanded(
              child: Text('Peta belum bisa dimuat. Periksa sinyal.'),
            ),
            const SizedBox(width: 8),
            OutlinedButton(onPressed: onRetry, child: const Text('Coba lagi')),
          ],
        ),
      ),
    );
  }
}

class _LogSection extends StatelessWidget {
  const _LogSection({required this.data, this.scrollable = true});

  final MonitoringData data;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final timeWidth = MediaQuery.textScalerOf(context).scale(58);

    final body = data.log.isEmpty
        ? Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              data.loadFailed
                  ? 'Catatan belum bisa ditampilkan.'
                  : 'Belum ada catatan hari ini. Perubahan status dan '
                        'laporan warga akan muncul di sini.',
              style: textTheme.bodyLarge?.copyWith(color: AppColors.inkSoft),
            ),
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (index, entry) in data.log.indexed) ...[
                if (index > 0) const Divider(indent: 16, endIndent: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: timeWidth,
                        child: Text(
                          entry.time,
                          style: textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Expanded(child: Text(entry.text)),
                    ],
                  ),
                ),
              ],
            ],
          );

    return Column(
      mainAxisSize: scrollable ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Text('Catatan terbaru', style: textTheme.titleMedium),
        ),
        if (scrollable)
          Expanded(child: SingleChildScrollView(child: body))
        else
          body,
      ],
    );
  }
}

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Tutup'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SensorSheet extends StatelessWidget {
  const _SensorSheet({required this.sensor});

  final SensorPoint sensor;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final status = sensor.status;

    return _SheetFrame(
      children: [
        Text('${sensor.id}, ${sensor.place}', style: textTheme.headlineSmall),
        const SizedBox(height: 12),
        DecoratedBox(
          decoration: BoxDecoration(
            color: status.background,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                StatusShape(status: status, size: 32),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    status.label,
                    style: textTheme.titleLarge?.copyWith(
                      color: status.foreground,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text('Data terakhir ${sensor.lastData}', style: textTheme.titleMedium),
        Text(
          'Nilai contoh, bukan hasil pengukuran lapangan.',
          style: textTheme.bodyLarge?.copyWith(color: AppColors.inkSoft),
        ),
        const SizedBox(height: 8),
        for (final reading in sensor.readings) ...[
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text(reading.name)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        reading.value,
                        textAlign: TextAlign.end,
                        style: textTheme.titleMedium?.copyWith(
                          color: sensor.isStale ? AppColors.stale : null,
                        ),
                      ),
                      if (sensor.isStale)
                        Text(
                          'Data lama',
                          style: textTheme.bodyLarge?.copyWith(
                            color: AppColors.stale,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _ReportSheet extends StatelessWidget {
  const _ReportSheet({required this.report});

  final ReportPoint report;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return _SheetFrame(
      children: [
        Text(report.title, style: textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text('${report.place}, ${report.time}', style: textTheme.titleMedium),
        const SizedBox(height: 12),
        Text('Menunggu verifikasi', style: textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Belum diperiksa petugas, jadi belum mengubah status titik.',
          style: textTheme.bodyLarge,
        ),
      ],
    );
  }
}

class _ScenarioSheet extends StatelessWidget {
  const _ScenarioSheet({required this.selected});

  final MonitoringData selected;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return _SheetFrame(
      children: [
        Text('Ganti contoh keadaan', style: textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          'Hanya untuk mencoba tampilan. Ini bukan data lapangan.',
          style: textTheme.bodyLarge,
        ),
        const SizedBox(height: 8),
        for (final scenario in sampleScenarios) ...[
          const Divider(),
          ListTile(
            minTileHeight: 56,
            contentPadding: EdgeInsets.zero,
            title: Text(scenario.name, style: textTheme.bodyLarge),
            trailing: identical(scenario, selected)
                ? const Icon(Icons.check, semanticLabel: 'Sedang dipilih')
                : null,
            onTap: () => Navigator.of(context).pop(scenario),
          ),
        ],
      ],
    );
  }
}
