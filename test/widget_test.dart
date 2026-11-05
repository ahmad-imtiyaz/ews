import 'dart:io';

import 'package:ews/app_theme.dart';
import 'package:ews/data/sample_data.dart';
import 'package:ews/screens/home_screen.dart';
import 'package:ews/screens/splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Pakai font asli supaya ukuran teks di tes sama dengan di ponsel.
  setUpAll(() async {
    final loader = FontLoader('AtkinsonHyperlegible');
    for (final weight in ['Regular', 'Bold']) {
      final bytes = File('assets/fonts/AtkinsonHyperlegible-$weight.ttf')
          .readAsBytes();
      loader.addFont(bytes.then(ByteData.sublistView));
    }
    await loader.load();
  });

  void usePhoneSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Widget app(Widget home) => MaterialApp(theme: buildAppTheme(), home: home);

  Widget home(MonitoringData data, {Future<MonitoringData> Function()? load}) =>
      app(
        HomeScreen(
          initialData: data,
          load: load ?? loadMonitoring,
          showMapTiles: false,
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
      expect(find.text('Buat laporan'), findsOneWidget);
      expect(find.text('Waspada'), findsOneWidget);
    });

    testWidgets('ketuk layar melewati animasi', (tester) async {
      usePhoneSize(tester);
      await tester.pumpWidget(app(const SplashScreen(showMapTiles: false)));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(SplashScreen));
      await tester.pumpAndSettle();

      expect(find.text('Buat laporan'), findsOneWidget);
    });

    testWidgets('status Awas langsung masuk ke Peta', (tester) async {
      usePhoneSize(tester);
      await tester.pumpWidget(
        app(SplashScreen(showMapTiles: false, load: () async => awasData)),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('Awas'), findsOneWidget);
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

      expect(find.text('Buat laporan'), findsOneWidget);
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
      expect(find.text('Buat laporan'), findsOneWidget);
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

      expect(find.text('Waspada'), findsOneWidget);
      expect(find.text('Coba lagi'), findsNothing);
    });

    testWidgets('marker titik membuka detail dan bisa ditutup', (tester) async {
      usePhoneSize(tester);
      await tester.pumpWidget(home(waspadaData));
      await tester.pump();

      await tester.tap(find.text('EWS-02'));
      await tester.pumpAndSettle();

      expect(find.text('EWS-02, Dusun B'), findsOneWidget);
      expect(find.text('Data terakhir 07.15'), findsOneWidget);
      expect(find.text('Data lama'), findsNWidgets(sampleReadings.length));

      await tester.tap(find.text('Tutup'));
      await tester.pumpAndSettle();
      expect(find.text('EWS-02, Dusun B'), findsNothing);
    });

    testWidgets('marker laporan menyatakan belum diverifikasi', (tester) async {
      usePhoneSize(tester);
      await tester.pumpWidget(home(waspadaData));
      await tester.pump();

      await tester.tap(find.text('Laporan'));
      await tester.pumpAndSettle();

      expect(find.text('Menunggu verifikasi'), findsOneWidget);
    });

    testWidgets('Buat laporan membuka halaman sementara dan kembali', (
      tester,
    ) async {
      usePhoneSize(tester);
      await tester.pumpWidget(home(waspadaData));

      await tester.tap(find.text('Buat laporan'));
      await tester.pumpAndSettle();
      expect(find.text('Formulir laporan sedang dibuat'), findsOneWidget);

      await tester.tap(find.text('Kembali ke peta'));
      await tester.pumpAndSettle();
      expect(find.text('Buat laporan'), findsOneWidget);
    });

    testWidgets('Data contoh bisa mengganti keadaan', (tester) async {
      usePhoneSize(tester);
      await tester.pumpWidget(home(waspadaData));

      await tester.tap(find.text('Data contoh'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Normal, catatan kosong'));
      await tester.pumpAndSettle();

      expect(find.text('Normal'), findsOneWidget);
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
          expect(find.text('Buat laporan'), findsOneWidget);
        });
      }
    }
  });
}
