import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../app_theme.dart';
import '../data/ews_data.dart';
import '../data/monitoring.dart';
import '../data/village_map.dart';
import '../services/ews_feed.dart';
import '../services/notification_inbox.dart';
import '../services/phone_location.dart';
import '../widgets/map_markers.dart';
import '../widgets/notification_bell.dart';
import '../widgets/status_icon.dart';
import '../widgets/top_bar.dart';

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

// Titiknya sudah tampil dari posisi pertama, jadi boleh menunggu GPS lebih
// lama daripada di Lapor.
Stream<PhoneFix> _locateForMap() =>
    watchPhoneLocation(timeLimit: const Duration(seconds: 45));

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.feed,
    required this.inbox,
    this.showMapTiles = true,
    this.locate = _locateForMap,
  });

  final EwsFeed feed;

  /// Dipegang MainShell karena loncengnya ada di semua menu. Beranda yang
  /// menyalakan notifikasi dan mengisinya, karena status ada di sini.
  final NotificationInbox inbox;
  final bool showMapTiles;
  final Stream<PhoneFix> Function() locate;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late MonitoringData _data = _fromFeed();
  bool _isRetrying = false;
  bool _notificationsReady = false;

  MonitoringData _fromFeed() =>
      monitoringFrom(widget.feed.data, refreshFailed: widget.feed.failed);

  @override
  void initState() {
    super.initState();
    widget.feed.addListener(_onFeedChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _startNotifications());
  }

  @override
  void dispose() {
    widget.feed.removeListener(_onFeedChanged);
    super.dispose();
  }

  Future<void> _startNotifications() async {
    final service = widget.inbox.service;
    await service.initialize();
    await service.requestPermission();
    await service.startPush(onMessage: _recordPush);
    if (!mounted) return;
    _notificationsReady = true;
    // Membuka aplikasi tidak perlu membunyikan HP, cukup tercatat di lonceng.
    _announce(_data, isChange: false);
  }

  void _onFeedChanged() {
    final previous = _data;
    final next = _fromFeed();
    setState(() => _data = next);
    if (!_notificationsReady || next.loadFailed) return;
    if (previous.loadFailed) {
      // Data pertama setelah gagal memuat, sama seperti aplikasi baru dibuka.
      _announce(next, isChange: false);
    } else if (next.status != previous.status) {
      _announce(next, isChange: true);
    }
  }

  void _recordPush(MonitoringStatus status, String title, String body) {
    if (!mounted) return;
    widget.inbox.add(
      NotificationEntry(
        status: status,
        title: title,
        body: body,
        time: _timeNow,
      ),
    );
  }

  String get _timeNow {
    final now = TimeOfDay.now();
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    return '$hour.$minute';
  }

  /// Normal saat aplikasi dibuka tidak perlu dicatat. Kembali Normal dicatat
  /// di lonceng tanpa membunyikan HP.
  void _announce(MonitoringData data, {required bool isChange}) {
    if (data.loadFailed) return;
    final isNormal = data.status == MonitoringStatus.normal;
    if (isNormal && !isChange) return;

    widget.inbox.add(
      NotificationEntry(
        status: data.status,
        title: data.title,
        body: data.summary,
        time: _timeNow,
      ),
    );
    if (isChange && !isNormal) {
      widget.inbox.service.showStatusAlert(
        status: data.status,
        title: data.title,
        body: data.summary,
      );
    }
  }

  Future<void> _retryLoad() async {
    setState(() => _isRetrying = true);
    await widget.feed.refresh();
    if (!mounted) return;
    setState(() => _isRetrying = false);
    if (widget.feed.data == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Masih belum bisa memuat data.')),
      );
    }
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
        actions: [NotificationBell(inbox: widget.inbox)],
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
  });

  final MonitoringData data;
  final bool showTiles;
  final Stream<PhoneFix> Function() locate;
  final ValueChanged<SensorPoint> onSensorTap;

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

  /// Penanda alat bisa disembunyikan supaya area pantau yang kecil di
  /// bawahnya terlihat utuh.
  bool _showEwsLocations = true;

  bool _mapReady = false;
  bool _cameraTouched = false;
  bool _fittedToAreas = false;

  PhoneFix? _me;
  StreamSubscription<PhoneFix>? _locationUpdates;
  bool _locating = false;

  /// Peta ikut pindah ke posisi yang makin tajam sampai warga menggesernya.
  bool _followMe = false;

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
      _fitToAreas();
    });
  }

  // Atas dan bawah menyisakan tempat menu mode dan atribusi supaya penanda di
  // tepi tidak tertutup.
  static const _fitPadding = EdgeInsets.fromLTRB(56, 80, 64, 64);

  /// Area pantau baru terbaca setelah peta tampil, jadi peta dipaskan ulang
  /// ke semua area dan penanda, kecuali warga sudah lebih dulu menggesernya.
  void _fitToAreas() {
    final map = _villageMap;
    if (!_mapReady || map == null || _cameraTouched || _fittedToAreas) return;
    final points = [
      for (final sensor in widget.data.sensors) ...[
        sensor.position,
        ...?map.monitoringAreas[sensor.id],
      ],
    ];
    if (points.isEmpty) return;
    _fittedToAreas = true;
    _controller.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(points),
        padding: _fitPadding,
        maxZoom: 17,
      ),
    );
  }

  @override
  void dispose() {
    _locationUpdates?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _zoomBy(double delta) {
    _cameraTouched = true;
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
              (_areaColor(status), status.label),
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

  /// Tanpa data, area dibiarkan putih: tidak ada kondisi yang bisa diwarnai.
  static Color _areaColor(MonitoringStatus status) =>
      status == MonitoringStatus.noData ? Colors.white : status.background;

  /// Area pantau tiap alat, warnanya ikut status alat itu.
  List<Polygon> _monitoringPolygons(VillageMap map) => [
    for (final sensor in widget.data.sensors)
      if (map.monitoringAreas[sensor.id] case final area?) ...[
        // Garis putih di bawahnya supaya hijau dan merah tua tetap terlihat
        // di atas citra satelit yang gelap.
        Polygon(points: area, borderColor: Colors.white, borderStrokeWidth: 5),
        Polygon(
          points: area,
          color: _areaColor(sensor.status).withValues(
            alpha: sensor.status == MonitoringStatus.noData ? 0.55 : 0.35,
          ),
          borderColor: sensor.status.background,
          borderStrokeWidth: 2.5,
          pattern: sensor.isStale
              ? StrokePattern.dashed(segments: const [10, 6])
              : const StrokePattern.solid(),
        ),
      ],
  ];

  void _goToMyLocation() {
    if (_locating) return;
    setState(() => _locating = true);
    _followMe = true;
    PhoneFix? latest;
    _locationUpdates = widget.locate().listen(
      (fix) {
        latest = fix;
        setState(() => _me = fix);
        if (!_followMe) return;
        _cameraTouched = true;
        _controller.move(
          LatLng(fix.latitude, fix.longitude),
          max(_controller.camera.zoom, 16),
        );
      },
      onError: (Object e) => _showMessage(switch (e) {
        LocationUnavailable(problem: LocationProblem.serviceOff) =>
          'Lokasi HP mati. Nyalakan lokasi, lalu coba lagi.',
        LocationUnavailable(problem: LocationProblem.denied) =>
          'Izin lokasi ditolak, jadi posisi Anda tidak bisa ditampilkan.',
        _ => 'Lokasi belum didapat. Coba lagi di tempat terbuka.',
      }),
      onDone: () {
        setState(() => _locating = false);
        if (latest case final fix? when fix.accuracy > gpsAccuracy) {
          _showMessage(
            'Titik Anda masih perkiraan, bisa meleset sampai '
            '±${fix.accuracy.round()} m. GPS belum dapat sinyal, coba lagi '
            'di tempat terbuka.',
          );
        }
      },
    );
  }

  void _showMessage(String message) {
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
                  bounds: LatLngBounds.fromPoints([
                    for (final device in ewsDevices) device.position,
                  ]),
                  padding: _fitPadding,
                  maxZoom: 17,
                ),
                onMapReady: () {
                  _mapReady = true;
                  _fitToAreas();
                },
                onPositionChanged: (camera, hasGesture) {
                  if (!hasGesture) return;
                  _cameraTouched = true;
                  _followMe = false;
                },
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
                    if (_showEwsLocations)
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
                  showEwsLocations: _showEwsLocations,
                  onSelected: _selectMode,
                  onZonesToggled: () =>
                      setState(() => _showZones = !_showZones),
                  onEwsLocationsToggled: () =>
                      setState(() => _showEwsLocations = !_showEwsLocations),
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
const _ewsMenuItem = 'ews';

class _MapModeMenu extends StatelessWidget {
  const _MapModeMenu({
    required this.selected,
    required this.showZones,
    required this.showEwsLocations,
    required this.onSelected,
    required this.onZonesToggled,
    required this.onEwsLocationsToggled,
  });

  final MapMode selected;
  final bool showZones;
  final bool showEwsLocations;
  final ValueChanged<MapMode> onSelected;
  final VoidCallback onZonesToggled;
  final VoidCallback onEwsLocationsToggled;

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
      onSelected: (value) => switch (value) {
        final MapMode mode => onSelected(mode),
        _zonesMenuItem => onZonesToggled(),
        _ => onEwsLocationsToggled(),
      },
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
        PopupMenuItem<Object>(
          value: _ewsMenuItem,
          height: 44,
          child: item(
            'Lokasi EWS',
            checked: showEwsLocations,
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
                                    border: Border.all(color: AppColors.border),
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
              'Belum ada catatan. Perubahan status alat EWS akan muncul '
              'di sini.',
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

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StatusIcon(status: entry.status, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.title,
                  style: textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
                if (entry.note.isNotEmpty)
                  Text(entry.note, style: textTheme.bodyLarge),
                if (entry.time.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    entry.time,
                    style: textTheme.bodyMedium?.copyWith(
                      color: AppColors.inkSoft,
                    ),
                  ),
                ],
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
    final area = sensor.area;
    final time = area?.time == null ? '-' : shortTime(area!.time!);
    final trigger = sensor.status == MonitoringStatus.normal
        ? null
        : area?.trigger;

    return _SheetFrame(
      children: [
        Text('${sensor.id}, ${sensor.place}', style: textTheme.titleLarge),
        const SizedBox(height: 12),
        _WhiteCard(
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
          _WhiteCard(
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
