import 'dart:io';

import 'package:ews/analysis/photo_analyzer.dart';
import 'package:ews/analysis/report.dart';
import 'package:ews/app_theme.dart';
import 'package:ews/screens/report_result_screen.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  setUpAll(() async {
    final loader = FontLoader(appFontFamily);
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      final bytes = File('assets/fonts/PlusJakartaSans-$weight.ttf')
          .readAsBytes();
      loader.addFont(bytes.then(ByteData.sublistView));
    }
    await loader.load();
  });

  final jpeg = Uint8List.fromList(
    img.encodeJpg(img.Image(width: 8, height: 8)),
  );

  ReportPhoto photo({double sharpness = 80}) => ReportPhoto(
    path: 'foto.jpg',
    bytes: jpeg,
    quality: PhotoQuality(
      width: 1600,
      height: 1200,
      brightness: 120,
      sharpness: sharpness,
    ),
  );

  /// Halaman hasil dibuka dari halaman lain supaya "Ganti foto" bisa kembali.
  Future<void> open(WidgetTester tester, List<ReportPhoto> photos) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final report = ReportAnalysis(
      time: DateTime(2026, 11, 19, 9, 30),
      story: 'lemah bengkah',
      photos: photos,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ReportResultScreen(
                    report: report,
                    cnnInstalled: false,
                    trainingSize: 0,
                  ),
                ),
              ),
              child: const Text('Formulir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Formulir'));
    await tester.pumpAndSettle();
  }

  Future<void> tapSend(WidgetTester tester) async {
    final send = find.text('Kirim ke petugas lewat WhatsApp');
    await tester.scrollUntilVisible(send, 300);
    await tester.ensureVisible(send);
    await tester.pumpAndSettle();
    await tester.tap(send);
    await tester.pumpAndSettle();
  }

  testWidgets('foto buram ditanyakan dulu, Ganti foto kembali ke formulir', (
    tester,
  ) async {
    await open(tester, [photo(), photo(sharpness: 40)]);

    await tapSend(tester);
    expect(find.text('Foto 2 kurang jelas'), findsOneWidget);
    expect(find.text('Foto 2: buram'), findsOneWidget);
    expect(find.textContaining('Pegang HP diam'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Ganti foto'));
    await tester.pumpAndSettle();
    expect(find.byType(ReportResultScreen), findsNothing);
    expect(find.text('Formulir'), findsOneWidget);
  });

  testWidgets('Tetap kirim melanjutkan tanpa bertanya lagi', (tester) async {
    await open(tester, [photo(sharpness: 40), photo(sharpness: 30)]);

    await tapSend(tester);
    expect(find.text('2 foto kurang jelas'), findsOneWidget);
    expect(find.text('Foto 2: buram'), findsOneWidget);

    await tester.tap(find.text('Tetap kirim'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(ReportResultScreen), findsOneWidget);
  });

  testWidgets('semua foto jelas langsung dikirim tanpa pertanyaan', (
    tester,
  ) async {
    await open(tester, [photo(), photo()]);

    await tapSend(tester);
    expect(find.byType(AlertDialog), findsNothing);
  });
}
