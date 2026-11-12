import 'dart:convert';
import 'dart:io';

import 'package:ews/app_theme.dart';
import 'package:ews/config.dart';
import 'package:ews/data/ews_data.dart';
import 'package:ews/data/monitoring.dart';
import 'package:ews/screens/main_shell.dart';
import 'package:ews/screens/sensor_screen.dart';
import 'package:ews/services/ews_feed.dart';
import 'package:ews/widgets/status_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ews_sample.dart';

void main() {
  // Pakai font asli supaya ukuran teks di tes sama dengan di ponsel.
  setUpAll(() async {
    final loader = FontLoader(appFontFamily);
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      final bytes = File('assets/fonts/PlusJakartaSans-$weight.ttf')
          .readAsBytes();
      loader.addFont(bytes.then(ByteData.sublistView));
    }
    await loader.load();
  });

  EwsData parse(String json) =>
      EwsData.fromJson(jsonDecode(json) as Map<String, dynamic>);
  final sample = parse(ewsSampleJson);
  final live = parse(ewsLiveJson);

  void usePhoneSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Widget app(Widget home, {double textScale = 1}) => MaterialApp(
    theme: buildAppTheme(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: home,
  );

  /// Halaman ini tidak mengambil data sendiri, jadi feed diisi lebih dulu.
  Future<EwsFeed> feedOf(Future<EwsData> Function() load) async {
    final feed = EwsFeed(load: load);
    addTearDown(feed.dispose);
    await feed.refresh();
    return feed;
  }

  testWidgets('menampilkan status, kartu sensor, dan riwayat', (tester) async {
    usePhoneSize(tester);
    final feed = await feedOf(() async => sample);
    await tester.pumpWidget(app(SensorScreen(feed: feed)));

    expect(find.text('Pantau sensor'), findsOneWidget);
    expect(find.textContaining('terakhir dicek'), findsOneWidget);
    expect(find.text('Penyebab: Kelembapan tanah 55%'), findsOneWidget);
    // Wilayah 1 di server adalah EWS-02.
    expect(find.textContaining('EWS-02 Sikembang, bacaan'), findsOneWidget);
    expect(find.text('EWS-02 Sikembang'), findsOneWidget);
    expect(find.text('55%'), findsOneWidget);
    expect(find.text('Waspada mulai 50%'), findsOneWidget);
    expect(find.text('Waspada mulai 15°'), findsOneWidget);
    // Dua wilayah, jadi status tiap wilayah ikut tampil.
    expect(find.text('Aman'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Perubahan status'), 300);
    expect(find.text('Tebing Dusun B'), findsOneWidget);
    expect(
      find.textContaining('Alat tidak mengirim data sejak'),
      findsOneWidget,
    );
    expect(find.text('Data lama'), findsNWidgets(4));
    // Alat offline yang terakhir Lewat batas tetap ditandai Waspada.
    final lewatBatas = find.ancestor(
      of: find.text('Lewat batas'),
      matching: find.byType(Row),
    );
    expect(
      tester
          .widget<StatusIcon>(
            find.descendant(
              of: lewatBatas.first,
              matching: find.byType(StatusIcon),
            ),
          )
          .status,
      MonitoringStatus.waspada,
    );
    expect(find.text('Waspada · EWS-02 Sikembang'), findsOneWidget);
  });

  testWidgets('balasan asli: alat diam saat Waspada diperingatkan di atas', (
    tester,
  ) async {
    usePhoneSize(tester);
    final feed = await feedOf(() async => live);
    await tester.pumpWidget(app(SensorScreen(feed: feed)));

    expect(find.text('Alat tidak mengirim data'), findsOneWidget);
    expect(find.textContaining('jangan anggap sudah aman'), findsOneWidget);
    expect(find.text('Penyebab: Kemiringan 9,9°'), findsOneWidget);
    expect(find.text('EWS-02 Sikembang'), findsOneWidget);
    expect(find.text('9,9°'), findsOneWidget);
    // Alat diam, jadi tiap kartu ditandai bacaan lama, bukan ambangnya.
    expect(find.text('Data lama'), findsNWidgets(4));
    expect(find.text('Data contoh'), findsNothing);

    await tester.scrollUntilVisible(find.text('Perubahan status'), 300);
    expect(find.text('Awas · EWS-02 Sikembang'), findsOneWidget);
    expect(find.text('Kabel EWS putus, Kemiringan 9,9°'), findsOneWidget);
  });

  testWidgets('gagal memuat lalu berhasil setelah Coba lagi', (tester) async {
    usePhoneSize(tester);
    var calls = 0;
    final feed = await feedOf(() async {
      calls++;
      if (calls == 1) throw Exception('tanpa sinyal');
      return sample;
    });
    await tester.pumpWidget(app(SensorScreen(feed: feed)));

    expect(find.text('Belum bisa mengambil data sensor'), findsOneWidget);

    await tester.tap(find.text('Coba lagi'));
    await tester.pump();

    expect(find.text('55%'), findsOneWidget);
  });

  testWidgets('angka lama tetap tampil saat sinyal putus', (tester) async {
    usePhoneSize(tester);
    var online = true;
    final feed = await feedOf(
      () async => online ? sample : throw Exception('putus'),
    );
    await tester.pumpWidget(app(SensorScreen(feed: feed)));

    online = false;
    await feed.refresh();
    await tester.pump();

    expect(find.text('Belum tersambung ke server'), findsOneWidget);
    expect(find.text('55%'), findsOneWidget);
  });

  testWidgets('teks diperbesar tidak terpotong', (tester) async {
    usePhoneSize(tester);
    for (final data in [sample, live]) {
      final feed = await feedOf(() async => data);
      await tester.pumpWidget(app(SensorScreen(feed: feed), textScale: 2));

      await tester.scrollUntilVisible(find.text('Perubahan status'), 300);
      expect(tester.takeException(), isNull);
    }
  });

  group('MainShell', () {
    Future<int Function()> pumpShell(WidgetTester tester) async {
      var calls = 0;
      final feed = EwsFeed(
        load: () async {
          calls++;
          return sample;
        },
      );
      await tester.pumpWidget(
        app(
          MainShell(feed: feed, showMapTiles: false, locateOnReport: false),
        ),
      );
      return () => calls;
    }

    // Timer pengambilan berkala harus berhenti sebelum tes selesai.
    Future<void> unmount(WidgetTester tester) =>
        tester.pumpWidget(const SizedBox());

    testWidgets('menu Sensor di kanan Beranda membuka halaman pantau', (
      tester,
    ) async {
      usePhoneSize(tester);
      await pumpShell(tester);
      await tester.pump();

      final home = tester.getCenter(find.byTooltip('Beranda'));
      final sensor = tester.getCenter(find.text('Sensor'));
      expect(sensor.dx, greaterThan(home.dx));

      await tester.tap(find.text('Sensor'));
      await tester.pumpAndSettle();
      expect(find.text('Pantau sensor'), findsOneWidget);
      expect(find.text('55%'), findsOneWidget);

      await tester.tap(find.byTooltip('Beranda'));
      await tester.pumpAndSettle();
      expect(find.text('EWS-02 berubah menjadi Waspada'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('data diambil berkala dan berhenti saat aplikasi ditinggal', (
      tester,
    ) async {
      usePhoneSize(tester);
      final calls = await pumpShell(tester);
      await tester.pump();
      expect(calls(), 1);

      await tester.pump(ewsRefreshInterval);
      expect(calls(), 2);

      final binding = tester.binding;
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(ewsRefreshInterval * 3);
      expect(calls(), 2);

      // Kembali ke aplikasi langsung mengambil data baru.
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(calls(), 3);
      await unmount(tester);
    });
  });
}
