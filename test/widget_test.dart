import 'dart:io';

import 'package:ews/analysis/text_analyzer.dart';
import 'package:ews/app_theme.dart';
import 'package:ews/data/sample_data.dart';
import 'package:ews/data/village_map.dart';
import 'package:ews/screens/home_screen.dart';
import 'package:ews/screens/main_shell.dart';
import 'package:ews/screens/report_result_screen.dart';
import 'package:ews/screens/report_screen.dart';
import 'package:ews/screens/splash_screen.dart';
import 'package:ews/services/phone_location.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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

  Widget home(
    MonitoringData data, {
    Future<MonitoringData> Function()? load,
    Stream<PhoneFix> Function()? locate,
  }) => app(
    HomeScreen(
      initialData: data,
      load: load ?? loadMonitoring,
      showMapTiles: false,
      locate:
          locate ??
          () =>
              Stream.error(const LocationUnavailable(LocationProblem.notFound)),
    ),
  );

  group('Splash', () {
    const maxWait = Duration(seconds: 5);

    testWidgets('selesai lalu masuk ke halaman Peta', (tester) async {
      usePhoneSize(tester);
      await tester.pumpWidget(app(const SplashScreen(showMapTiles: false)));

      expect(find.text('Pemantauan longsor desa'), findsOneWidget);

      await tester.pump(maxWait);
      await tester.pumpAndSettle();

      expect(find.text('Pemantauan longsor desa'), findsNothing);
      expect(find.text('Lapor'), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('EWS-01 berubah menjadi Waspada'), findsOneWidget);
    });

    testWidgets('ketuk layar melewati animasi', (tester) async {
      usePhoneSize(tester);
      await tester.pumpWidget(app(const SplashScreen(showMapTiles: false)));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(SplashScreen));
      await tester.pumpAndSettle();

      expect(find.text('Lapor'), findsOneWidget);
    });

    testWidgets('status Awas langsung masuk ke Peta', (tester) async {
      usePhoneSize(tester);
      await tester.pumpWidget(
        app(SplashScreen(showMapTiles: false, load: () async => awasData)),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('EWS-01 berubah menjadi Awas'), findsOneWidget);
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

      await tester.pumpWidget(app(const SplashScreen(showMapTiles: false)));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(find.text('Lapor'), findsOneWidget);
    });

    testWidgets('memberi tahu saat data lama dimuat', (tester) async {
      usePhoneSize(tester);
      await tester.pumpWidget(
        app(
          SplashScreen(
            showMapTiles: false,
            load: () async {
              await Future<void>.delayed(const Duration(seconds: 7));
              return waspadaData;
            },
          ),
        ),
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
        app(
          SplashScreen(
            showMapTiles: false,
            load: () async => throw Exception('tanpa sinyal'),
          ),
        ),
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
      await tester.pumpWidget(home(failedData));

      await tester.tap(find.text('Coba lagi'));
      await tester.pumpAndSettle();

      expect(find.text('EWS-01 berubah menjadi Waspada'), findsOneWidget);
      expect(find.text('Coba lagi'), findsNothing);
    });

    testWidgets('marker titik membuka detail dan bisa ditutup', (tester) async {
      usePhoneSize(tester);
      await tester.pumpWidget(home(waspadaData));
      await tester.pump();

      await tester.tap(find.text('EWS-02'));
      await tester.pumpAndSettle();

      expect(find.text('EWS-02, Sikembang'), findsOneWidget);
      expect(find.text('Data terakhir 07.15'), findsOneWidget);
      expect(find.text('Data lama'), findsNWidgets(sampleReadings.length));

      await tester.tap(find.text('Tutup'));
      await tester.pumpAndSettle();
      expect(find.text('EWS-02, Sikembang'), findsNothing);
    });

    testWidgets('marker laporan menyatakan belum diverifikasi', (tester) async {
      usePhoneSize(tester);
      await tester.pumpWidget(home(waspadaData));
      await tester.pump();

      await tester.tap(find.text('Laporan'));
      await tester.pumpAndSettle();

      expect(find.text('Menunggu verifikasi'), findsOneWidget);
    });

    testWidgets('mode peta bisa diganti dan sumbernya ikut berubah', (
      tester,
    ) async {
      usePhoneSize(tester);
      await tester.pumpWidget(home(waspadaData));
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
    Future<void> pumpHomeWithMap(
      WidgetTester tester,
      MonitoringData data,
    ) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(home(data));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }

    testWidgets('area EWS tampil lebih dulu, zona longsor bisa dinyalakan', (
      tester,
    ) async {
      usePhoneSize(tester);
      await pumpHomeWithMap(tester, waspadaData);

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
      await pumpHomeWithMap(tester, waspadaData);
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
      expect(find.text('Laporan'), findsOneWidget);
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
      List<Color> areaColors() => [
        for (final layer in tester.widgetList<PolygonLayer>(
          find.byWidgetPredicate((w) => w is PolygonLayer),
        ))
          for (final polygon in layer.polygons)
            if (polygon.color != null) polygon.borderColor,
      ];

      await pumpHomeWithMap(tester, waspadaData);
      expect(areaColors(), [AppColors.waspada, AppColors.stale]);

      await pumpHomeWithMap(tester, awasData);
      expect(areaColors(), [AppColors.awas, AppColors.waspada]);

      await pumpHomeWithMap(tester, normalData);
      expect(areaColors(), [AppColors.normal, AppColors.normal]);
    });

    testWidgets('tombol lokasi menampilkan posisi HP di peta', (tester) async {
      usePhoneSize(tester);
      await tester.pumpWidget(
        home(
          waspadaData,
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
          waspadaData,
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
          waspadaData,
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

    testWidgets('perubahan status masuk riwayat lonceng tanpa pop up', (
      tester,
    ) async {
      usePhoneSize(tester);
      await tester.pumpWidget(home(normalData));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Notifikasi'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Belum ada notifikasi'), findsOneWidget);
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Data contoh'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Awas'));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsNothing);
      expect(find.text('1'), findsOneWidget);

      await tester.tap(find.byTooltip('Notifikasi'));
      await tester.pumpAndSettle();
      expect(find.text('Contoh: Awas'), findsOneWidget);
    });

    testWidgets('Data contoh bisa mengganti keadaan', (tester) async {
      usePhoneSize(tester);
      await tester.pumpWidget(home(waspadaData));

      await tester.tap(find.text('Data contoh'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Normal, catatan kosong'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Belum ada catatan hari ini'), findsOneWidget);
    });

    for (final scenario in sampleScenarios) {
      for (final scale in [1.0, 1.3, 1.5, 2.0]) {
        testWidgets('${scenario.name} tanpa overflow pada teks ${scale}x', (
          tester,
        ) async {
          usePhoneSize(tester);
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

          await tester.pumpWidget(home(scenario));
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

    Widget shell() => app(
      const MainShell(
        initialData: waspadaData,
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
      expect(find.text('EWS-01 berubah menjadi Waspada'), findsOneWidget);
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
