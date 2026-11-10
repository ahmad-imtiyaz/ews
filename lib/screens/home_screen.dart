import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../app_theme.dart';
import '../data/sample_data.dart';
import '../data/village_map.dart';
import '../services/notification_service.dart';
import '../services/phone_location.dart';
import '../widgets/map_markers.dart';
import '../widgets/top_bar.dart';
import 'notifications_screen.dart';

const _pagePadding = 16.0;
const _sectionGap = 16.0;

enum MapMode {
  peta(
    label: 'Peta',
    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    attribution: '© OpenStreetMap',
    maxNativeZoom: 19,
    grayscale: true,
  ),
  satelit(
    label: 'Satelit',
    urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
    attribution: 'Citra © Esri',
    maxNativeZoom: 17,
  ),
  medan(
    label: 'Medan',
    urlTemplate: 'https://tile.opentopomap.org/{z}/{x}/{y}.png',
    attribution: '© OpenStreetMap, SRTM, OpenTopoMap',
    maxNativeZoom: 17,
  );

  const MapMode({
    required this.label,
    required this.urlTemplate,
    required this.attribution,
    required this.maxNativeZoom,
    this.grayscale = false,
  });

  final String label;
  final String urlTemplate;
  final String attribution;
  final int maxNativeZoom;
  final bool grayscale;
}

// Tombol di peta ditekan sambil menunggu, jadi tidak selama di Lapor.
Future<PhoneFix> _locateForMap() =>
    findPhoneLocation(timeLimit: const Duration(seconds: 10));

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.initialData,
    this.load = loadMonitoring,
    this.showMapTiles = true,
    this.locate = _locateForMap,
  });

  final MonitoringData initialData;
  final Future<MonitoringData> Function() load;
  final bool showMapTiles;
  final Future<PhoneFix> Function() locate;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _notificationService = NotificationService();
  final _notifications = <NotificationEntry>[];

  late MonitoringData _data = widget.initialData;
  bool _isRetrying = false;
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startNotifications());
  }

  Future<void> _startNotifications() async {
    await _notificationService.initialize();
    await _notificationService.requestPermission();
    await _notificationService.startPush(onMessage: _recordPush);
    if (!mounted) return;
    // Membuka aplikasi tidak perlu membunyikan HP, cukup tercatat di lonceng.
    _announce(_data, notifyPhone: false);
  }

  void _recordPush(MonitoringStatus status, String title, String body) {
    if (!mounted) return;
    setState(() {
      _notifications.add(
        NotificationEntry(
          status: status,
          title: title,
          body: body,
          time: _timeNow,
        ),
      );
      _unread++;
    });
  }

  @override
  void dispose() {
    _notificationService.dispose();
    super.dispose();
  }

  String get _timeNow {
    final now = TimeOfDay.now();
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    return '$hour.$minute';
  }

  // Status Normal tidak perlu mengganggu warga, dan kegagalan memuat sudah
  // tampil di bagian catatan.
  bool _needsAttention(MonitoringData data) =>
      !data.loadFailed && data.status != MonitoringStatus.normal;

  void _announce(MonitoringData data, {required bool notifyPhone}) {
    if (!_needsAttention(data)) return;

    // Data simulasi tidak boleh terbaca sebagai peringatan nyata.
    final title = 'Contoh: ${data.title}';
    setState(() {
      _notifications.add(
        NotificationEntry(
          status: data.status,
          title: title,
          body: data.summary,
          time: _timeNow,
        ),
      );
      _unread++;
    });
    if (notifyPhone) {
      _notificationService.showStatusAlert(
        status: data.status,
        title: title,
        body: data.summary,
      );
    }
  }

  void _openNotifications() {
    setState(() => _unread = 0);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NotificationsScreen(
          entries: _notifications,
          service: _notificationService,
        ),
      ),
    );
  }

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
    } else {
      _announce(loaded, notifyPhone: true);
    }
  }

  Future<void> _showScenarioPicker() async {
    final picked = await showModalBottomSheet<MonitoringData>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ScenarioSheet(selected: _data),
    );
    if (picked == null || identical(picked, _data)) return;
    setState(() => _data = picked);
    _announce(picked, notifyPhone: true);
  }

  void _showSheet(Widget sheet) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => sheet,
    );
  }

  Widget _buildLog({bool scrollable = true}) {
    return _LogSection(
      data: _data,
      scrollable: scrollable,
      isRetrying: _isRetrying,
      onRetry: _retryLoad,
    );
  }

  Widget _buildMap() {
    return _MapPanel(
      data: _data,
      showTiles: widget.showMapTiles,
      locate: widget.locate,
      onSensorTap: (sensor) => _showSheet(_SensorSheet(sensor: sensor)),
      onReportTap: (report) => _showSheet(_ReportSheet(report: report)),
    );
  }

  // Peta dan catatan mengisi layar tanpa menggulir halaman, karena geser
  // ke atas atau bawah di peta dipakai untuk menggeser peta. Catatan yang
  // panjang digulir di dalam kartunya sendiri.
  Widget _buildFixedLayout() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          _pagePadding,
          8,
          _pagePadding,
          _pagePadding,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: 5, child: _buildMap()),
            const SizedBox(height: _sectionGap),
            Expanded(flex: 4, child: _buildLog()),
          ],
        ),
      ),
    );
  }

  // Teks yang diperbesar tidak muat dalam susunan tetap, jadi halaman digulir.
  // Bagian bawah diberi ruang setinggi menu bawah agar catatan terakhir tidak
  // tertutup.
  Widget _buildLargeTextLayout() {
    return ListView(
      padding: EdgeInsets.fromLTRB(
        _pagePadding,
        8,
        _pagePadding,
        MediaQuery.paddingOf(context).bottom + _pagePadding,
      ),
      children: [
        SizedBox(height: 300, child: _buildMap()),
        const SizedBox(height: _sectionGap),
        _buildLog(scrollable: false),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLargeText = MediaQuery.textScalerOf(context).scale(1) > 1.3;

    return Scaffold(
      appBar: TopBar(
        title: 'EWS Lumeneng',
        // Pada susunan tetap yang bergulir hanya kartu catatan, bukan isi
        // yang lewat di bawah bar.
        notificationPredicate: isLargeText
            ? defaultScrollNotificationPredicate
            : (_) => false,
        actions: [
          Semantics(
            label: 'Data contoh. Ganti contoh keadaan.',
            excludeSemantics: true,
            child: OutlinedButton(
              onPressed: _showScenarioPicker,
              child: const Text('Data contoh'),
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: 'Notifikasi',
            child: Semantics(
              label: _unread > 0
                  ? 'Notifikasi, $_unread belum dibaca'
                  : 'Notifikasi',
              excludeSemantics: true,
              child: OutlinedButton(
                onPressed: _openNotifications,
                style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
                child: Badge.count(
                  count: _unread,
                  isLabelVisible: _unread > 0,
                  backgroundColor: AppColors.ink,
                  textColor: Colors.white,
                  child: const Icon(Icons.notifications_none, size: 22),
                ),
              ),
            ),
          ),
        ],
      ),
      body: isLargeText ? _buildLargeTextLayout() : _buildFixedLayout(),
    );
  }
}

class _MapPanel extends StatefulWidget {
  const _MapPanel({
    required this.data,
    required this.showTiles,
    required this.locate,
    required this.onSensorTap,
    required this.onReportTap,
  });

  final MonitoringData data;
  final bool showTiles;
  final Future<PhoneFix> Function() locate;
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
  MapMode _mode = MapMode.satelit;
  int _tileAttempt = 0;
  bool _tilesFailed = false;

  VillageMap? _villageMap;
  List<Polygon> _zonePolygons = const [];

  /// Zona kajian hanya rujukan; yang tampil lebih dulu area pantau alat EWS.
  bool _showZones = false;
  bool _legendOpen = false;

  PhoneFix? _me;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    loadVillageMap().then((map) {
      if (!mounted) return;
      setState(() {
        _villageMap = map;
        _zonePolygons = [
          for (final area in map.zones)
            Polygon(
              points: area.outline,
              holePointsList: area.holes,
              color: area.zone.color.withValues(alpha: 0.4),
              borderColor: area.zone.color,
              borderStrokeWidth: 1.2,
            ),
        ];
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _zoomBy(double delta) {
    final camera = _controller.camera;
    _controller.move(camera.center, camera.zoom + delta);
  }

  List<_LegendSection> _legendSections() {
    final map = _villageMap;
    if (map == null) return const [];
    return [
      if (map.monitoringAreas.isNotEmpty)
        (
          title: map.monitoringAreasAreSamples
              ? 'Area EWS (contoh)'
              : 'Area EWS',
          entries: [
            for (final status in MonitoringStatus.values)
              (status.background, status.label),
          ],
        ),
      if (_showZones && _zonePolygons.isNotEmpty)
        (
          title: 'Zona longsor',
          entries: [
            for (final zone in LandslideZone.values) (zone.color, zone.label),
          ],
        ),
    ];
  }

  /// Area pantau tiap alat, warnanya ikut status alat itu.
  List<Polygon> _monitoringPolygons(VillageMap map) => [
    for (final sensor in widget.data.sensors)
      if (map.monitoringAreas[sensor.id] case final area?) ...[
        // Garis putih di bawahnya supaya hijau dan merah tua tetap terlihat
        // di atas citra satelit yang gelap.
        Polygon(points: area, borderColor: Colors.white, borderStrokeWidth: 5),
        Polygon(
          points: area,
          color: sensor.status.background.withValues(alpha: 0.35),
          borderColor: sensor.status.background,
          borderStrokeWidth: 2.5,
          pattern: sensor.isStale
              ? StrokePattern.dashed(segments: const [10, 6])
              : const StrokePattern.solid(),
        ),
      ],
  ];

  Future<void> _goToMyLocation() async {
    if (_locating) return;
    setState(() => _locating = true);
    PhoneFix? fix;
    var problem = LocationProblem.notFound;
    try {
      fix = await widget.locate();
    } on LocationUnavailable catch (e) {
      problem = e.problem;
    } catch (_) {
      problem = LocationProblem.notFound;
    }
    if (!mounted) return;
    setState(() {
      _locating = false;
      _me = fix ?? _me;
    });
    if (fix != null) {
      _controller.move(
        LatLng(fix.latitude, fix.longitude),
        max(_controller.camera.zoom, 16),
      );
      return;
    }
    final message = switch (problem) {
      LocationProblem.serviceOff =>
        'Lokasi HP mati. Nyalakan lokasi, lalu coba lagi.',
      LocationProblem.denied =>
        'Izin lokasi ditolak, jadi posisi Anda tidak bisa ditampilkan.',
      LocationProblem.notFound =>
        'Lokasi belum didapat. Coba lagi di tempat terbuka.',
    };
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _selectMode(MapMode mode) {
    setState(() {
      _mode = mode;
      _tilesFailed = false;
    });
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: ColoredBox(
        color: AppColors.mapBackground,
        child: Stack(
          children: [
            FlutterMap(
              mapController: _controller,
              options: MapOptions(
                initialCameraFit: CameraFit.bounds(
                  bounds: LatLngBounds.fromPoints(mapFocusPoints),
                  // Atas dan bawah menyisakan tempat menu mode dan atribusi
                  // supaya penanda di tepi tidak tertutup.
                  padding: const EdgeInsets.fromLTRB(56, 80, 64, 64),
                  maxZoom: 15.5,
                ),
                minZoom: 11,
                maxZoom: 18,
                backgroundColor: AppColors.mapBackground,
                interactionOptions: const InteractionOptions(
                  flags:
                      InteractiveFlag.drag |
                      InteractiveFlag.pinchZoom |
                      InteractiveFlag.doubleTapZoom,
                ),
              ),
              children: [
                if (widget.showTiles)
                  TileLayer(
                    key: ValueKey((_mode, _tileAttempt)),
                    urlTemplate: _mode.urlTemplate,
                    maxNativeZoom: _mode.maxNativeZoom,
                    userAgentPackageName: 'id.kkn.ews_lumeneng',
                    errorTileCallback: _onTileError,
                    tileBuilder: _mode.grayscale
                        ? (context, tile, _) => ColorFiltered(
                            colorFilter: _grayscale,
                            child: tile,
                          )
                        : null,
                  ),
                if (_showZones)
                  PolygonLayer(
                    polygons: _zonePolygons,
                    // Bawaan Android (pathCombine) melubangi poligon dengan
                    // Path.combine per lubang di setiap frame; 85 lubang
                    // membuat geser peta tinggal ±2 fps. Zona tidak saling
                    // tumpang, jadi evenOdd memberi gambar yang sama.
                    painterFillMethod: PolygonPainterFillMethod.evenOdd,
                  ),
                if (_villageMap case final map?)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: map.boundary,
                        strokeWidth: 2.5,
                        color: Colors.white,
                        borderStrokeWidth: 1.5,
                        borderColor: const Color(0x99000000),
                      ),
                    ],
                  ),
                if (_villageMap case final map?)
                  PolygonLayer(polygons: _monitoringPolygons(map)),
                if (_me case final me?)
                  CircleLayer(
                    circles: [
                      CircleMarker(
                        point: LatLng(me.latitude, me.longitude),
                        radius: me.accuracy,
                        useRadiusInMeter: true,
                        color: AppColors.myLocation.withValues(alpha: 0.15),
                        borderColor: AppColors.myLocation.withValues(
                          alpha: 0.6,
                        ),
                        borderStrokeWidth: 1,
                      ),
                    ],
                  ),
                MarkerLayer(
                  markers: [
                    for (final report in widget.data.reports)
                      Marker(
                        point: report.position,
                        width: 96,
                        height: 56,
                        child: ReportMarkerButton(
                          report: report,
                          onTap: () => widget.onReportTap(report),
                        ),
                      ),
                    for (final sensor in widget.data.sensors)
                      Marker(
                        point: sensor.position,
                        width: 96,
                        height: 56,
                        child: SensorMarkerButton(
                          sensor: sensor,
                          onTap: () => widget.onSensorTap(sensor),
                        ),
                      ),
                    if (_me case final me?)
                      Marker(
                        point: LatLng(me.latitude, me.longitude),
                        width: 24,
                        height: 24,
                        child: const _MyLocationDot(),
                      ),
                  ],
                ),
              ],
            ),
            Positioned(
              left: 8,
              top: 4,
              child: MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.2,
                child: _MapModeMenu(
                  selected: _mode,
                  showZones: _showZones,
                  onSelected: _selectMode,
                  onZonesToggled: () =>
                      setState(() => _showZones = !_showZones),
                ),
              ),
            ),
            Positioned(
              left: 12,
              right: 64,
              bottom: 12,
              child: Align(
                alignment: Alignment.bottomLeft,
                child: _tilesFailed
                    ? _MapFailureNotice(onRetry: _retryTiles)
                    : _MapAttribution(
                        text: _showZones && _zonePolygons.isNotEmpty
                            ? '${_mode.attribution} · Zona: kajian LPBI NU 2024'
                            : _mode.attribution,
                      ),
              ),
            ),
            Positioned(
              right: 8,
              bottom: 4,
              child: Column(
                children: [
                  _MapButton(
                    icon: Icons.my_location,
                    tooltip: 'Ke lokasi saya',
                    busy: _locating,
                    onPressed: _goToMyLocation,
                  ),
                  const SizedBox(height: 8),
                  _MapButton(
                    icon: Icons.add,
                    tooltip: 'Perbesar peta',
                    onPressed: () => _zoomBy(1),
                  ),
                  _MapButton(
                    icon: Icons.remove,
                    tooltip: 'Perkecil peta',
                    onPressed: () => _zoomBy(-1),
                  ),
                ],
              ),
            ),
            // Paling akhir supaya saat dibuka menutupi tombol peta, bukan
            // tertutup olehnya. Tertutup secara bawaan agar area EWS di
            // kanan atas tidak terhalang.
            if (_legendSections() case final sections when sections.isNotEmpty)
              Positioned(
                top: 4,
                right: 8,
                bottom: 4,
                child: Align(
                  alignment: Alignment.topRight,
                  child: MediaQuery.withClampedTextScaling(
                    maxScaleFactor: 1.2,
                    child: _MapLegend(
                      open: _legendOpen,
                      onToggle: () =>
                          setState(() => _legendOpen = !_legendOpen),
                      sections: sections,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

const _zonesMenuItem = 'zona';

class _MapModeMenu extends StatelessWidget {
  const _MapModeMenu({
    required this.selected,
    required this.showZones,
    required this.onSelected,
    required this.onZonesToggled,
  });

  final MapMode selected;
  final bool showZones;
  final ValueChanged<MapMode> onSelected;
  final VoidCallback onZonesToggled;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    Widget item(String label, {required bool checked, required String state}) {
      return Row(
        children: [
          Expanded(child: Text(label, style: textTheme.bodyLarge)),
          if (checked) Icon(Icons.check, size: 18, semanticLabel: state),
        ],
      );
    }

    return PopupMenuButton<Object>(
      tooltip: 'Pilih mode peta',
      initialValue: selected,
      onSelected: (value) =>
          value is MapMode ? onSelected(value) : onZonesToggled(),
      position: PopupMenuPosition.under,
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      itemBuilder: (_) => [
        for (final mode in MapMode.values)
          PopupMenuItem<Object>(
            value: mode,
            height: 44,
            child: item(
              mode.label,
              checked: mode == selected,
              state: 'Sedang dipilih',
            ),
          ),
        const PopupMenuDivider(),
        PopupMenuItem<Object>(
          value: _zonesMenuItem,
          height: 44,
          child: item(
            'Zona rawan longsor',
            checked: showZones,
            state: 'Sedang tampil',
          ),
        ),
      ],
      // Kotak terlihat setinggi 34, tetapi area sentuhnya tetap 44.
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.layers_outlined, size: 16),
                const SizedBox(width: 6),
                Text(
                  selected.label,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.keyboard_arrow_down, size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MapButton extends StatelessWidget {
  const _MapButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.busy = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    // Terlihat setinggi 40, tetapi area sentuhnya tetap 48.
    return IconButton.filled(
      onPressed: onPressed,
      tooltip: tooltip,
      iconSize: 20,
      icon: busy
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Icon(icon),
      style: IconButton.styleFrom(
        backgroundColor: AppColors.ink,
        foregroundColor: Colors.white,
        fixedSize: const Size(40, 40),
        minimumSize: const Size(40, 40),
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
    );
  }
}

typedef _LegendSection = ({String title, List<(Color, String)> entries});

class _MapLegend extends StatelessWidget {
  const _MapLegend({
    required this.open,
    required this.onToggle,
    required this.sections,
  });

  final bool open;
  final VoidCallback onToggle;
  final List<_LegendSection> sections;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    const labelStyle = TextStyle(
      fontSize: 11,
      height: 1.25,
      color: AppColors.ink,
    );
    final decoration = BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.border),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Semantics(
          button: true,
          expanded: open,
          label: 'Keterangan warna peta',
          excludeSemantics: true,
          child: InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(10),
            // Kotak terlihat setinggi 34, tetapi area sentuhnya tetap 44.
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: DecoratedBox(
                decoration: decoration,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Keterangan',
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        open
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        size: 16,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (open)
          Flexible(
            child: DecoratedBox(
              decoration: decoration,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(8, 5, 9, 7),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final (index, section) in sections.indexed) ...[
                      if (index > 0) const SizedBox(height: 8),
                      Text(
                        section.title,
                        style: labelStyle.copyWith(fontWeight: FontWeight.w600),
                      ),
                      for (final (color, label) in section.entries)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox.square(
                                dimension: 10,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: color,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(label, style: labelStyle),
                            ],
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _MyLocationDot extends StatelessWidget {
  const _MyLocationDot();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Lokasi Anda',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.myLocation,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 4)],
        ),
      ),
    );
  }
}

class _MapAttribution extends StatelessWidget {
  const _MapAttribution({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          text,
          textScaler: TextScaler.noScaling,
          style: const TextStyle(fontSize: 10, color: AppColors.ink),
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
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Peta belum bisa dimuat. Periksa sinyal.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(onPressed: onRetry, child: const Text('Coba lagi')),
          ],
        ),
      ),
    );
  }
}

class _LogSection extends StatefulWidget {
  const _LogSection({
    required this.data,
    required this.scrollable,
    required this.isRetrying,
    required this.onRetry,
  });

  final MonitoringData data;
  final bool scrollable;
  final bool isRetrying;
  final VoidCallback onRetry;

  @override
  State<_LogSection> createState() => _LogSectionState();
}

class _LogSectionState extends State<_LogSection> {
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
              'Belum ada catatan hari ini. Perubahan status dan '
              'laporan warga akan muncul di sini.',
              style: textTheme.bodyLarge?.copyWith(color: AppColors.inkSoft),
            ),
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (index, entry) in data.log.indexed) ...[
                if (index > 0) const Divider(indent: 60, endIndent: 14),
                _LogRow(entry: entry),
              ],
            ],
          );

    final scrollable = widget.scrollable;
    final card = DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        // Batang gulir selalu tampil bila catatan tidak muat, supaya baris
        // yang terpotong di bawah terbaca sebagai "masih ada lagi".
        child: scrollable
            ? Scrollbar(
                controller: _scroll,
                thumbVisibility: true,
                child: SingleChildScrollView(controller: _scroll, child: body),
              )
            : body,
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

class _LogRow extends StatelessWidget {
  const _LogRow({required this.entry});

  final LogEntry entry;

  IconData get _icon => switch (entry.kind) {
    LogKind.status => Icons.warning_amber_rounded,
    LogKind.report => Icons.description_outlined,
    LogKind.noData => Icons.sensors_off_outlined,
    LogKind.verified => Icons.verified_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: AppColors.iconTile,
              shape: BoxShape.circle,
            ),
            child: Icon(_icon, size: 18, color: AppColors.ink),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.text,
                  style: textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w500,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  entry.time,
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

class _WhiteCard extends StatelessWidget {
  const _WhiteCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
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
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
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
        Text('${sensor.id}, ${sensor.place}', style: textTheme.titleLarge),
        const SizedBox(height: 12),
        DecoratedBox(
          decoration: BoxDecoration(
            color: status.background,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                StatusShape(status: status, size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    status.label,
                    style: textTheme.titleMedium?.copyWith(
                      color: status.foreground,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('Data terakhir ${sensor.lastData}', style: textTheme.titleMedium),
        const SizedBox(height: 2),
        Text(
          'Nilai contoh, bukan hasil pengukuran lapangan.',
          style: textTheme.bodyMedium?.copyWith(color: AppColors.inkSoft),
        ),
        const SizedBox(height: 12),
        _WhiteCard(
          children: [
            for (final (index, reading) in sensor.readings.indexed) ...[
              if (index > 0) const Divider(indent: 14, endIndent: 14),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(reading.name, style: textTheme.bodyLarge),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            reading.value,
                            textAlign: TextAlign.end,
                            style: textTheme.labelLarge?.copyWith(
                              color: sensor.isStale ? AppColors.stale : null,
                            ),
                          ),
                          if (sensor.isStale)
                            Text(
                              'Data lama',
                              style: textTheme.bodyMedium?.copyWith(
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
        ),
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
        Text(report.title, style: textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          '${report.place}, ${report.time}',
          style: textTheme.bodyMedium?.copyWith(color: AppColors.inkSoft),
        ),
        const SizedBox(height: 12),
        _WhiteCard(
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Menunggu verifikasi', style: textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    'Belum diperiksa petugas, jadi belum mengubah status titik.',
                    style: textTheme.bodyLarge,
                  ),
                ],
              ),
            ),
          ],
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
        Text('Ganti contoh keadaan', style: textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          'Hanya untuk mencoba tampilan. Ini bukan data lapangan.',
          style: textTheme.bodyMedium?.copyWith(color: AppColors.inkSoft),
        ),
        const SizedBox(height: 12),
        _WhiteCard(
          children: [
            for (final (index, scenario) in sampleScenarios.indexed) ...[
              if (index > 0) const Divider(indent: 14, endIndent: 14),
              ListTile(
                minTileHeight: 48,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                title: Text(scenario.name, style: textTheme.bodyLarge),
                trailing: identical(scenario, selected)
                    ? const Icon(
                        Icons.check,
                        size: 20,
                        semanticLabel: 'Sedang dipilih',
                      )
                    : null,
                onTap: () => Navigator.of(context).pop(scenario),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
