import 'dart:async';

import 'package:flutter/material.dart';

import '../data/monitoring.dart';
import '../services/ews_feed.dart';
import '../services/notification_inbox.dart';
import '../services/phone_location.dart';
import 'home/log_section.dart';
import 'home/map_panel.dart';
import 'home/sensor_sheet.dart';
import 'log_screen.dart';
import '../widgets/notification_bell.dart';
import '../widgets/top_bar.dart';

const _pagePadding = 16.0;
const _sectionGap = 16.0;

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
  late bool _live = _isLive(_data);
  bool _isRetrying = false;
  bool _notificationsReady = false;

  /// Status terakhir yang sudah diberitahukan, dari kiriman server atau dari
  /// data yang diambil aplikasi. Keduanya biasanya melihat perubahan yang
  /// sama dalam beberapa detik, jadi yang datang kedua tidak dicatat lagi.
  MonitoringStatus? _announced;

  /// Selama aplikasi di latar, perubahan status sudah dibunyikan Android dari
  /// kiriman server. Data pertama setelah kembali cukup dicatat di lonceng.
  bool _quietNextFetch = false;
  late final AppLifecycleListener _lifecycle;

  MonitoringData _fromFeed() => monitoringFrom(
    widget.feed.data,
    refreshFailed: widget.feed.failed,
    outdated: widget.feed.isStale,
    checkedAt: widget.feed.checkedAt,
  );

  /// Hanya data yang baru dipastikan ke server yang boleh membunyikan atau
  /// mencatat peringatan. Data simpanan dan data lama bisa sudah tidak
  /// berlaku, dan sinyal HP yang putus bukan perubahan kondisi lereng.
  bool _isLive(MonitoringData data) =>
      !data.loadFailed && !data.outdated && !widget.feed.fromCache;

  @override
  void initState() {
    super.initState();
    widget.feed.addListener(_onFeedChanged);
    _lifecycle = AppLifecycleListener(onShow: () => _quietNextFetch = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _startNotifications());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    widget.feed.removeListener(_onFeedChanged);
    super.dispose();
  }

  Future<void> _startNotifications() async {
    final service = widget.inbox.service;
    await service.initialize();
    await service.requestPermission();
    await service.startPush(onMessage: _recordPush);
    await widget.inbox.ready;
    if (!mounted) return;
    _notificationsReady = true;
    // Membuka aplikasi tidak perlu membunyikan HP, cukup tercatat di lonceng.
    if (_live) _announce(_data, isChange: false);
  }

  void _onFeedChanged() {
    final previous = _data;
    final wasLive = _live;
    final next = _fromFeed();
    setState(() => _data = next);
    _live = _isLive(next);
    if (!_notificationsReady || !_live) return;
    final ring = !_quietNextFetch;
    _quietNextFetch = false;
    if (!wasLive) {
      // Data pertama setelah gagal memuat, setelah data simpanan, atau setelah
      // lama tidak tersambung, sama seperti aplikasi baru dibuka.
      _announce(next, isChange: false);
    } else if (next.status != previous.status) {
      _announce(next, isChange: true, ring: ring);
    }
  }

  void _recordPush(
    MonitoringStatus status,
    String title,
    String body, {
    required bool live,
  }) {
    if (!mounted || status == _announced) return;
    _announced = status;
    widget.inbox.add(
      NotificationEntry(
        status: status,
        title: title,
        body: body,
        time: DateTime.now(),
      ),
    );
    if (live && status != MonitoringStatus.normal) {
      widget.inbox.service.showStatusAlert(
        status: status,
        title: title,
        body: body,
      );
    }
  }

  /// Normal saat aplikasi dibuka tidak perlu dicatat. Kembali Normal dicatat
  /// di lonceng tanpa membunyikan HP, begitu juga semua perubahan bila [ring]
  /// false.
  void _announce(
    MonitoringData data, {
    required bool isChange,
    bool ring = true,
  }) {
    if (data.loadFailed || data.status == _announced) return;
    _announced = data.status;
    final isNormal = data.status == MonitoringStatus.normal;
    if (isNormal && !isChange) return;
    // Riwayat tersimpan di HP, jadi membuka aplikasi berkali-kali saat Awas
    // tidak boleh menumpuk catatan yang sama.
    final last = widget.inbox.entries.lastOrNull;
    if (!isChange &&
        last != null &&
        last.status == data.status &&
        last.body == data.summary) {
      return;
    }

    widget.inbox.add(
      NotificationEntry(
        status: data.status,
        title: data.title,
        body: data.summary,
        time: DateTime.now(),
      ),
    );
    if (isChange && ring && !isNormal) {
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
    if (widget.feed.failed) {
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
    return LogSection(
      data: _data,
      scrollable: scrollable,
      isRetrying: _isRetrying,
      onRetry: _retryLoad,
      onShowAll: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => LogScreen(
            title: 'Catatan terbaru',
            feed: widget.feed,
            items: () => logItemsFrom(_fromFeed()),
          ),
        ),
      ),
    );
  }

  Widget _buildMap() {
    return MapPanel(
      data: _data,
      showTiles: widget.showMapTiles,
      locate: widget.locate,
      onSensorTap: (sensor) => _showSheet(SensorSheet(sensor: sensor)),
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
