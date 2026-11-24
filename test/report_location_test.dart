import 'dart:async';
import 'dart:io';

import 'package:ews/analysis/text_analyzer.dart';
import 'package:ews/app_theme.dart';
import 'package:ews/screens/report_result_screen.dart';
import 'package:ews/screens/report_screen.dart';
import 'package:ews/services/phone_location.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tiap akurasi punya titik sendiri, supaya terlihat posisi mana yang dipakai.
PhoneFix _fix(double accuracy) =>
    (latitude: -7.18 - accuracy / 10000, longitude: 109.59, accuracy: accuracy);

void main() {
  late TextAnalyzer analyzer;
  setUpAll(() {
    analyzer = TextAnalyzer.fromCsv(
      dictionaryCsv: File(dictionaryAsset).readAsStringSync(),
      examplesCsv: File(examplesAsset).readAsStringSync(),
    );
  });

  /// Membuka Lapor dengan GPS palsu, mengisi cerita, lalu menekan Periksa
  /// laporan.
  Future<StreamController<PhoneFix>> openAndSubmit(
    WidgetTester tester, {
    List<PhoneFix> before = const [],
  }) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final gps = StreamController<PhoneFix>();
    // Tidak ditunggu: close() baru selesai setelah pump, dan setelah tes
    // tidak ada pump lagi, jadi menunggunya membuat tes macet.
    addTearDown(() => unawaited(gps.close()));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: ReportScreen(
          locate: () => gps.stream,
          loadText: () async => analyzer,
          loadCnn: () async => null,
        ),
      ),
    );
    for (final fix in before) {
      gps.add(fix);
    }
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'lemah bengkah');
    await tester.pump();
    final submit = find.text('Periksa laporan');
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
    await tester.tap(submit);
    await tester.pump();
    return gps;
  }

  testWidgets('lokasi kasar ditunggu, lanjut sendiri begitu akurat', (
    tester,
  ) async {
    final gps = await openAndSubmit(tester, before: [_fix(85)]);

    expect(find.text('Menunggu lokasi akurat'), findsOneWidget);
    expect(find.text('Sekarang ±85 m'), findsOneWidget);

    gps.add(_fix(40));
    await tester.pump();
    expect(find.text('Sekarang ±40 m'), findsOneWidget);

    gps.add(_fix(12));
    await tester.pumpAndSettle();
    expect(find.text('Menunggu lokasi akurat'), findsNothing);
    expect(find.byType(ReportResultScreen), findsOneWidget);
    // -7.18 - 12/10000, bukan titik ±85 m.
    final point = find.text('-7.18120, 109.59000');
    await tester.scrollUntilVisible(
      point,
      200,
      scrollable: find
          .descendant(
            of: find.byType(ReportResultScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(point, findsOneWidget);
  });

  testWidgets('pencarian yang berhenti di tengah penantian diulang', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // Pencarian pertama berhenti setelah posisi kasar, seperti batas 45 detik.
    final searches = <StreamController<PhoneFix>>[];
    Stream<PhoneFix> locate() {
      final gps = StreamController<PhoneFix>();
      searches.add(gps);
      // Tidak ditunggu: close() baru selesai setelah pump, dan setelah tes
      // tidak ada pump lagi, jadi menunggunya membuat tes macet.
      addTearDown(() => unawaited(gps.close()));
      return gps.stream;
    }

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: ReportScreen(
          locate: locate,
          loadText: () async => analyzer,
          loadCnn: () async => null,
        ),
      ),
    );
    searches.last.add(_fix(85));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'lemah bengkah');
    await tester.pump();
    final submit = find.text('Periksa laporan');
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
    await tester.tap(submit);
    await tester.pump();
    expect(find.text('Menunggu lokasi akurat'), findsOneWidget);

    // Tidak ditunggu: di tes widget masa depan close() baru selesai setelah
    // pump, jadi await di sini macet.
    unawaited(searches.last.close());
    await tester.pump();
    expect(searches, hasLength(2));

    searches.last.add(_fix(9));
    await tester.pumpAndSettle();
    expect(find.byType(ReportResultScreen), findsOneWidget);
  });

  testWidgets('Lanjut tanpa menunggu memakai lokasi yang ada', (tester) async {
    await openAndSubmit(tester, before: [_fix(85)]);

    await tester.tap(find.text('Lanjut tanpa menunggu'));
    await tester.pumpAndSettle();
    expect(find.byType(ReportResultScreen), findsOneWidget);
  });

  testWidgets('GPS yang tidak kunjung masuk ditunggu paling lama 30 detik', (
    tester,
  ) async {
    await openAndSubmit(tester, before: [_fix(85)]);
    expect(find.text('Menunggu lokasi akurat'), findsOneWidget);

    await tester.pump(const Duration(seconds: 29));
    expect(find.text('Menunggu lokasi akurat'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.byType(ReportResultScreen), findsOneWidget);
  });

  testWidgets('lokasi yang sudah akurat tidak ditunggu', (tester) async {
    await openAndSubmit(tester, before: [_fix(8)]);
    await tester.pumpAndSettle();
    expect(find.text('Menunggu lokasi akurat'), findsNothing);
    expect(find.byType(ReportResultScreen), findsOneWidget);
  });

  testWidgets('izin lokasi ditolak tidak menahan laporan', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: ReportScreen(
          locate: () =>
              Stream.error(const LocationUnavailable(LocationProblem.denied)),
          loadText: () async => analyzer,
          loadCnn: () async => null,
        ),
      ),
    );
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'lemah bengkah');
    await tester.pump();
    final submit = find.text('Periksa laporan');
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
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(find.text('Menunggu lokasi akurat'), findsNothing);
    expect(find.byType(ReportResultScreen), findsOneWidget);
  });
}
