import 'dart:convert';

import 'package:ews/widgets/photo_viewer.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

// PNG 1x1 transparan.
final _pixel = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA'
  '60e6kgAAAABJRU5ErkJggg==',
);

void main() {
  testWidgets('geser untuk pindah foto, catatan ikut foto yang tampil', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PhotoViewer(
          photos: [_pixel, _pixel, _pixel],
          initialIndex: 1,
          notes: const [null, 'Foto 2: buram.', null],
        ),
      ),
    );

    expect(find.text('Foto 2 dari 3'), findsOneWidget);
    expect(find.text('Foto 2: buram.'), findsOneWidget);

    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
    await tester.pumpAndSettle();

    expect(find.text('Foto 3 dari 3'), findsOneWidget);
    expect(find.text('Foto 2: buram.'), findsNothing);
  });

  testWidgets('usapan cepat dalam satu lompatan tetap pindah foto', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: PhotoViewer(photos: [_pixel, _pixel])),
    );

    // Satu gerakan besar langsung melewati batas geser dan batas zoom, kasus
    // yang dulu dimenangkan InteractiveViewer.
    final gesture = await tester.startGesture(const Offset(700, 300));
    await gesture.moveBy(const Offset(-500, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('Foto 2 dari 2'), findsOneWidget);
  });

  testWidgets('foto yang diperbesar tidak pindah saat digeser', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: PhotoViewer(photos: [_pixel, _pixel])),
    );

    final a = await tester.startGesture(const Offset(350, 300), pointer: 10);
    final b = await tester.startGesture(const Offset(450, 300), pointer: 11);
    for (var i = 0; i < 10; i++) {
      await a.moveBy(const Offset(-15, 0));
      await b.moveBy(const Offset(15, 0));
      await tester.pump();
    }
    await a.up();
    await b.up();
    await tester.pumpAndSettle();

    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
    await tester.pumpAndSettle();

    expect(find.text('Foto 1 dari 2'), findsOneWidget);
    final zoom = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    expect(
      zoom.transformationController!.value.getMaxScaleOnAxis(),
      greaterThan(1),
    );
  });

  testWidgets('satu foto tanpa nomor', (tester) async {
    await tester.pumpWidget(MaterialApp(home: PhotoViewer(photos: [_pixel])));

    expect(find.text('Foto'), findsOneWidget);
  });
}
