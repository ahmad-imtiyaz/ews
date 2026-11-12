import 'dart:convert';
import 'dart:io';

import 'package:ews/analysis/text_analyzer.dart';
import 'package:ews/app_theme.dart';
import 'package:ews/data/ews_data.dart';
import 'package:ews/data/monitoring.dart';
import 'package:ews/data/village_map.dart';
import 'package:ews/screens/home_screen.dart';
import 'package:ews/screens/main_shell.dart';
import 'package:ews/screens/report_result_screen.dart';
import 'package:ews/screens/report_screen.dart';
import 'package:ews/screens/splash_screen.dart';
import 'package:ews/services/ews_feed.dart';
import 'package:ews/services/notification_inbox.dart';
import 'package:ews/services/phone_location.dart';
import 'package:ews/widgets/status_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
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
    // Hasilnya disimpan untuk seluruh jalannya aplikasi. Kalau pertama kali
    // dimuat dari initState di dalam jam palsu tes, bacaan asetnya tidak
    // pernah selesai dan semua tes sesudahnya ikut menunggu.
    await loadVillageMap();
  });

  void usePhoneSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Widget app(Widget home) => MaterialApp(theme: buildAppTheme(), home: home);

  EwsData parse(String json) =>
      EwsData.fromJson(jsonDecode(json) as Map<String, dynamic>);
  final live = parse(ewsLiveJson);

  /// Satu wilayah (EWS-02) dengan status tertentu, mis. untuk Normal dan Awas
  /// yang tidak ada di balasan asli.
  EwsData areaWith(String status, {String? note}) => EwsData.fromJson({
    'utama': {'status': status, 'saran': ''},
    'wilayah': [
      {
        'id': 1,
        'nama': 'Titik Area 2',
        'status': status,
        'pemicu': note,
        'waktu': '12-11-2026 20:33',
        'offline': false,
        'sensor': <String, dynamic>{},
      },
    ],
    'log': [
      if (note != null)
        {
          'waktu': '12-11-2026 20:33',
          'wilayah': 'Titik Area 2',
          'status': status,
          'keterangan': note,
        },
    ],
  });
  final normal = areaWith('Aman');
  final awas = areaWith('Awas', note: 'Kabel EWS putus');

  /// [data] `null` berarti server tidak bisa dihubungi.
  Future<EwsFeed> feedOf(EwsData? data) async {
    final feed = EwsFeed(
      load: () async => data ?? (throw Exception('tanpa sinyal')),
    );
    addTearDown(feed.dispose);
    await feed.refresh();
    return feed;
  }

  Widget home(EwsFeed feed, {Stream<PhoneFix> Function()? locate}) => app(
    HomeScreen(
      feed: feed,
      inbox: NotificationInbox(),
      showMapTiles: false,
      locate:
          locate ??
          () =>
              Stream.error(const LocationUnavailable(LocationProblem.notFound)),
    ),
  );

  group('Splash', () {
    const maxWait = Duration(seconds: 5);

    // Feed di sini dipegang dan ditutup MainShell.
    Widget splash(Future<EwsData> Function() load) => app(
      SplashScreen(feed: EwsFeed(load: load), showMapTiles: false),
    );

    testWidgets('selesai lalu masuk ke halaman Peta', (tester) async {
      usePhoneSize(tester);
      await tester.pumpWidget(splash(() async => live));

      expect(find.text('Pemantauan longsor desa'), findsOneWidget);

      await tester.pump(maxWait);
      await tester.pumpAndSettle();

      expect(find.text('Pemantauan longsor desa'), findsNothing);
      expect(find.text('Lapor'), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('EWS-02 berubah menjadi Awas'), findsOneWidget);
    });

    testWidgets('ketuk layar melewati animasi', (tester) async {
      usePhoneSize(tester);
      await tester.pumpWidget(splash(() async => live));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(SplashScreen));
      await tester.pumpAndSettle();

      expect(find.text('Lapor'), findsOneWidget);
    });

    testWidgets('status Awas langsung masuk ke Peta', (tester) async {
      usePhoneSize(tester);
      await tester.pumpWidget(splash(() async => awas));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('EWS-02 berubah menjadi Awas'), findsOneWidget);
    });

    testWidgets('animasi dimatikan di HP membuat splash singkat', (
      tester,
    ) async {
      usePhoneSize(tester);
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );

      await tester.pumpWidget(splash(() async => live));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(find.text('Lapor'), findsOneWidget);
    });

    testWidgets('memberi tahu saat data lama dimuat', (tester) async {
      usePhoneSize(tester);
      await tester.pumpWidget(
        splash(() async {
          await Future<void>.delayed(const Duration(seconds: 7));
          return live;
        }),
      );

      await tester.pump(maxWait);
      await tester.pump();
      expect(find.text('Mengambil data terbaru'), findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text('Lapor'), findsOneWidget);
    });

    testWidgets('gagal memuat tetap masuk ke Peta', (tester) async {
      usePhoneSize(tester);
      await tester.pumpWidget(
        splash(() async => throw Exception('tanpa sinyal')),
      );

      await tester.pump(maxWait);
      await tester.pumpAndSettle();

      expect(find.text('Belum bisa memuat'), findsOneWidget);
      expect(find.text('Coba lagi'), findsOneWidget);
    });
  });

  group('Halaman Peta', () {
    testWidgets('Coba lagi memuat ulang data', (tester) async {
      usePhoneSize(tester);
      var online = false;
      final feed = EwsFeed(
        load: () async => online ? live : throw Exception('tanpa sinyal'),
      );
      addTearDown(feed.dispose);
      await feed.refresh();
      await tester.pumpWidget(home(feed));

      online = true;
      await tester.tap(find.text('Coba lagi'));
      await tester.pumpAndSettle();

      expect(find.text('EWS-02 berubah menjadi Awas'), findsOneWidget);
      expect(find.text('Coba lagi'), findsNothing);
    });

    testWidgets('tanpa tombol Data contoh dan penanda laporan', (tester) async {
      usePhoneSize(tester);
      await tester.pumpWidget(home(await feedOf(live)));
      await tester.pump();

      expect(find.text('Data contoh'), findsNothing);
      expect(find.text('Laporan'), findsNothing);
      expect(find.text('EWS-01'), findsOneWidget);
      expect(find.text('EWS-02'), findsOneWidget);
    });

    testWidgets('EWS-01 belum terhubung, detailnya bisa ditutup', (
      tester,
    ) async {
      usePhoneSize(tester);
      await tester.pumpWidget(home(await feedOf(live)));
      await tester.pump();

      await tester.tap(find.text('EWS-01'));
      await tester.pumpAndSettle();

      expect(find.text('EWS-01, Jomparang'), findsOneWidget);
      expect(find.text('Belum terhubung'), findsOneWidget);
      expect(find.textContaining('belum mengirim data'), findsOneWidget);

      await tester.tap(find.text('Tutup'));
      await tester.pumpAndSettle();
      expect(find.text('EWS-01, Jomparang'), findsNothing);
    });

    testWidgets('EWS-02 menampilkan bacaan asli dari server', (tester) async {
      usePhoneSize(tester);
      await tester.pumpWidget(home(await feedOf(live)));
      await tester.pump();

      await tester.tap(find.text('EWS-02'));
      await tester.pumpAndSettle();

      expect(find.text('EWS-02, Sikembang'), findsOneWidget);
      expect(find.text('Waspada'), findsOneWidget);
      expect(find.text('Kemiringan 9,9°'), findsOneWidget);
      expect(find.textContaining('Tidak mengirim data sejak'), findsOneWidget);
      expect(find.text('9,9°'), findsOneWidget);
      expect(find.text('97,9%'), findsOneWidget);
      expect(find.text('Data lama'), findsNWidgets(4));
      expect(find.textContaining('contoh'), findsNothing);
    });

    testWidgets('catatan terbaru berisi kejadian dari alat', (tester) async {
      usePhoneSize(tester);
      await tester.pumpWidget(home(await feedOf(live)));
      await tester.pump();

      expect(find.text('EWS-02 berhenti mengirim data'), findsOneWidget);
      expect(find.textContaining('jangan anggap sudah aman'), findsOneWidget);
      expect(find.text('EWS-02 berubah menjadi Awas'), findsOneWidget);
      expect(find.text('Kabel EWS putus, Kemiringan 9,9°'), findsOneWidget);
      expect(find.textContaining('Bacaan '), findsOneWidget);
    });

    testWidgets('mode peta bisa diganti dan sumbernya ikut berubah', (
      tester,
    ) async {
      usePhoneSize(tester);
      await tester.pumpWidget(home(await feedOf(live)));
      await tester.pump();

      // Peta pertama kali dibuka dengan citra satelit.
      expect(find.textContaining('Citra © Esri'), findsOneWidget);

      await tester.tap(find.byTooltip('Pilih mode peta'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Peta'));
      await tester.pumpAndSettle();
      expect(find.textContaining('© OpenStreetMap'), findsOneWidget);
      expect(find.text('Medan'), findsNothing);

      await tester.tap(find.byTooltip('Pilih mode peta'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Medan'));
      await tester.pumpAndSettle();
      expect(find.textContaining('OpenTopoMap'), findsOneWidget);
    });

    // Peta desa sudah dimuat di setUpAll dengan jam asli, jadi then() di
    // initState baru jalan setelah event loop asli dapat giliran.
    Future<void> pumpHomeWithMap(WidgetTester tester, EwsData data) async {
      final feed = await feedOf(data);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(home(feed));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }

    testWidgets('area EWS tampil lebih dulu, zona longsor bisa dinyalakan', (
      tester,
    ) async {
      usePhoneSize(tester);
      await pumpHomeWithMap(tester, live);

      // Keterangan tertutup supaya area EWS di kanan atas tidak terhalang.
      expect(find.text('Keterangan'), findsOneWidget);
      expect(find.text('Area EWS'), findsNothing);
      await tester.tap(find.text('Keterangan'));
      await tester.pump();
      expect(find.text('Area EWS'), findsOneWidget);
      expect(find.text('Zona longsor'), findsNothing);
      expect(find.textContaining('Zona: kajian'), findsNothing);

      await tester.tap(find.byTooltip('Pilih mode peta'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Zona rawan longsor'));
      await tester.pumpAndSettle();
      expect(find.text('Area EWS'), findsOneWidget);
      expect(find.text('Zona longsor'), findsOneWidget);
      for (final zone in LandslideZone.values) {
        expect(find.text(zone.label), findsOneWidget);
      }
      expect(find.textContaining('Zona: kajian'), findsOneWidget);

      await tester.tap(find.text('Keterangan'));
      await tester.pump();
      expect(find.text('Zona longsor'), findsNothing);
    });

    testWidgets('lokasi EWS bisa disembunyikan, areanya tetap tampil', (
      tester,
    ) async {
      usePhoneSize(tester);
      await pumpHomeWithMap(tester, live);
      int areaCount() => [
        for (final layer in tester.widgetList<PolygonLayer>(
          find.byWidgetPredicate((w) => w is PolygonLayer),
        ))
          for (final polygon in layer.polygons)
            if (polygon.color != null) polygon,
      ].length;

      expect(find.text('EWS-01'), findsOneWidget);
      expect(areaCount(), 2);

      await tester.tap(find.byTooltip('Pilih mode peta'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lokasi EWS'));
      await tester.pumpAndSettle();
      expect(find.text('EWS-01'), findsNothing);
      expect(find.text('EWS-02'), findsNothing);
      expect(areaCount(), 2);

      await tester.tap(find.byTooltip('Pilih mode peta'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lokasi EWS'));
      await tester.pumpAndSettle();
      expect(find.text('EWS-01'), findsOneWidget);
    });

    testWidgets('warna area EWS mengikuti status alatnya', (tester) async {
      usePhoneSize(tester);
      // Garis tepi area berwarna status; poligon tanpa isi hanya garis putih
      // di bawahnya.
      List<Polygon> areas() => [
        for (final layer in tester.widgetList<PolygonLayer>(
          find.byWidgetPredicate((w) => w is PolygonLayer),
        ))
          for (final polygon in layer.polygons)
            if (polygon.color != null) polygon,
      ];
      List<Color> borders() => [for (final a in areas()) a.borderColor];

      await pumpHomeWithMap(tester, live);
      expect(borders(), [AppColors.stale, AppColors.waspada]);
      // EWS-01 belum mengirim data, jadi areanya dibiarkan putih.
      expect(areas().first.color!.withValues(alpha: 1), Colors.white);

      await pumpHomeWithMap(tester, awas);
      expect(borders(), [AppColors.stale, AppColors.awas]);

      await pumpHomeWithMap(tester, normal);
      expect(borders(), [AppColors.stale, AppColors.normal]);
    });

    testWidgets('tombol lokasi menampilkan posisi HP di peta', (tester) async {
      usePhoneSize(tester);
      await tester.pumpWidget(
        home(
          await feedOf(live),
          locate: () => Stream.value((
            latitude: -7.1800,
            longitude: 109.5850,
            accuracy: 15.0,
          )),
        ),
      );
      await tester.pump();
      expect(find.bySemanticsLabel('Lokasi Anda'), findsNothing);

      await tester.tap(find.byTooltip('Ke lokasi saya'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Lokasi Anda'), findsOneWidget);
    });

    testWidgets('lokasi yang belum dari GPS disebut masih perkiraan', (
      tester,
    ) async {
      usePhoneSize(tester);
      await tester.pumpWidget(
        home(
          await feedOf(live),
          locate: () => Stream.fromIterable([
            (latitude: -7.1732, longitude: 109.5816, accuracy: 88.0),
            (latitude: -7.1735, longitude: 109.5812, accuracy: 35.0),
          ]),
        ),
      );
      await tester.pump();

      await tester.tap(find.byTooltip('Ke lokasi saya'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Lokasi Anda'), findsOneWidget);
      expect(find.textContaining('meleset sampai ±35 m'), findsOneWidget);
    });

    testWidgets('izin lokasi ditolak dijelaskan tanpa memindah peta', (
      tester,
    ) async {
      usePhoneSize(tester);
      await tester.pumpWidget(
        home(
          await feedOf(live),
          locate: () =>
              Stream.error(const LocationUnavailable(LocationProblem.denied)),
        ),
      );
      await tester.pump();

      await tester.tap(find.byTooltip('Ke lokasi saya'));
      await tester.pump();
      expect(find.textContaining('Izin lokasi ditolak'), findsOneWidget);
      expect(find.bySemanticsLabel('Lokasi Anda'), findsNothing);
    });

    testWidgets('perubahan status dari server masuk lonceng tanpa pop up', (
      tester,
    ) async {
      usePhoneSize(tester);
      var current = normal;
      final feed = EwsFeed(load: () async => current);
      addTearDown(feed.dispose);
      await feed.refresh();
      await tester.pumpWidget(home(feed));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Notifikasi'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Belum ada notifikasi'), findsOneWidget);
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();

      current = awas;
      await feed.refresh();
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsNothing);
      expect(find.text('1'), findsOneWidget);

      await tester.tap(find.byTooltip('Notifikasi'));
      await tester.pumpAndSettle();
      expect(find.text('Awas'), findsOneWidget);
      expect(find.text('EWS-02 Sikembang: Kabel EWS putus.'), findsOneWidget);
      expect(find.textContaining('contoh'), findsNothing);
      // Ikon garis yang sama dengan menu Sensor.
      expect(
        tester.widget<StatusIcon>(find.byType(StatusIcon)).status,
        MonitoringStatus.awas,
      );
    });

    for (final (name, data) in [
      ('Balasan asli', live),
      ('Normal', normal),
      ('Awas', awas),
      ('Gagal memuat', null),
    ]) {
      for (final scale in [1.0, 1.3, 1.5, 2.0]) {
        testWidgets('$name tanpa overflow pada teks ${scale}x', (
          tester,
        ) async {
          usePhoneSize(tester);
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

          await tester.pumpWidget(home(await feedOf(data)));
          await tester.pump();

          expect(tester.takeException(), isNull);
          expect(find.textContaining('Aman'), findsNothing);
          expect(find.text('Catatan terbaru'), findsOneWidget);
        });
      }
    }
  });

  group('Pelaporan', () {
    // Menu Lapor tetap hidup saat tersembunyi, jadi kolomnya dicari juga di
    // halaman yang tidak tampil.
    bool storyHasFocus(WidgetTester tester) => tester
        .widget<EditableText>(find.byType(EditableText, skipOffstage: false))
        .focusNode
        .hasFocus;

    // Feed dipegang dan ditutup MainShell.
    Widget shell() => app(
      MainShell(
        feed: EwsFeed(load: () async => live),
        showMapTiles: false,
        locateOnReport: false,
      ),
    );

    testWidgets('menu bawah berpindah antara Beranda dan Lapor', (
      tester,
    ) async {
      usePhoneSize(tester);
      await tester.pumpWidget(shell());

      await tester.tap(find.text('Lapor'));
      await tester.pumpAndSettle();
      expect(find.text('Lapor tanda longsor'), findsOneWidget);

      await tester.tap(find.byTooltip('Beranda'));
      await tester.pumpAndSettle();
      expect(find.text('EWS-02 berubah menjadi Awas'), findsOneWidget);
    });

    testWidgets('lonceng ada di semua menu dengan hitungan yang sama', (
      tester,
    ) async {
      usePhoneSize(tester);
      await tester.pumpWidget(shell());
      await tester.pumpAndSettle();
      // Status Waspada dari server tercatat di lonceng saat aplikasi dibuka.
      final unread = find.bySemanticsLabel('Notifikasi, 1 belum dibaca');
      expect(unread, findsOneWidget);

      await tester.tap(find.text('Lapor'));
      await tester.pumpAndSettle();
      expect(unread, findsOneWidget);

      await tester.tap(find.text('Sensor'));
      await tester.pumpAndSettle();
      expect(unread, findsOneWidget);

      await tester.tap(find.byTooltip('Notifikasi'));
      await tester.pumpAndSettle();
      expect(find.text('Notifikasi'), findsWidgets);
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      expect(unread, findsNothing);
      expect(find.bySemanticsLabel('Notifikasi'), findsOneWidget);
    });

    testWidgets('cerita bahasa Jawa dibakukan di hasil analisis', (
      tester,
    ) async {
      usePhoneSize(tester);
      final analyzer = TextAnalyzer.fromCsv(
        dictionaryCsv: File(dictionaryAsset).readAsStringSync(),
        examplesCsv: File(examplesAsset).readAsStringSync(),
      );
      await tester.pumpWidget(
        app(
          ReportScreen(
            locateOnStart: false,
            loadText: () async => analyzer,
            loadCnn: () async => null,
          ),
        ),
      );

      final submit = find.text('Periksa laporan');
      await tester.enterText(
        find.byType(TextField),
        'lemah e bengkah neng mburi omah pak RT, saiki tambah amba',
      );
      await tester.pump();
      await tester.scrollUntilVisible(
        submit,
        200,
        scrollable: find
            .descendant(
              of: find.byType(ReportScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.ensureVisible(submit);
      await tester.pumpAndSettle();
      await tester.tap(submit);
      await tester.pumpAndSettle();

      expect(find.text('Hasil analisis'), findsOneWidget);
      expect(
        find.text(
          'Tanahnya retak di belakang rumah Pak RT, sekarang makin lebar.',
        ),
        findsOneWidget,
      );
      expect(find.text('Retakan tanah'), findsOneWidget);
      expect(find.text('mburi → belakang', findRichText: true), findsOneWidget);
      expect(find.text('e (digabung)', findRichText: true), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Hanya keterangan teks, tanpa foto'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(ReportResultScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(tester.takeException(), isNull);

      // Kembali untuk mengubah laporan tidak membuka keyboard sendiri.
      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.pumpAndSettle();
      expect(find.text('Periksa laporan'), findsOneWidget);
      expect(storyHasFocus(tester), isFalse);
    });

    testWidgets('judul atas tetap terlihat saat formulir digulir', (
      tester,
    ) async {
      usePhoneSize(tester);
      await tester.pumpWidget(shell());
      await tester.tap(find.text('Lapor'));
      await tester.pumpAndSettle();

      double barElevation() => tester
          .widget<Material>(
            find
                .descendant(
                  of: find.byType(AppBar),
                  matching: find.byType(Material),
                )
                .first,
          )
          .elevation;

      expect(barElevation(), 0);

      await tester.drag(
        find.text('Lapor tanda longsor'),
        const Offset(0, -500),
      );
      await tester.pumpAndSettle();

      expect(find.text('Lapor tanda longsor').hitTestable(), findsNothing);
      final title = tester.getRect(find.text('EWS Lumeneng'));
      expect(title.top, greaterThanOrEqualTo(0));
      expect(title.bottom, lessThanOrEqualTo(64));
      // Bayangan tipis muncul karena isi halaman lewat di bawah bar.
      expect(barElevation(), greaterThan(0));
    });

    testWidgets('kolom cerita tidak terfokus lagi setelah pindah menu', (
      tester,
    ) async {
      usePhoneSize(tester);
      await tester.pumpWidget(shell());
      await tester.tap(find.text('Lapor'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(storyHasFocus(tester), isTrue);

      await tester.tap(find.byTooltip('Beranda'));
      await tester.pumpAndSettle();
      expect(storyHasFocus(tester), isFalse);

      // Dulu fokus kembali ke kolom cerita yang tersembunyi setelah halaman
      // Notifikasi ditutup, sehingga keyboard muncul di Beranda.
      await tester.tap(find.byTooltip('Notifikasi'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.pumpAndSettle();
      expect(find.text('Catatan terbaru'), findsOneWidget);
      expect(storyHasFocus(tester), isFalse);
    });

    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets('formulir laporan tanpa overflow pada teks ${scale}x', (
        tester,
      ) async {
        usePhoneSize(tester);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        await tester.pumpWidget(shell());
        await tester.tap(find.text('Lapor'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      });
    }
  });
}
