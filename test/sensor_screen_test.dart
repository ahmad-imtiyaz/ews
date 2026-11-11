import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:ews/app_theme.dart';
import 'package:ews/config.dart';
import 'package:ews/data/ews_data.dart';
import 'package:ews/data/ews_sample.dart';
import 'package:ews/data/sample_data.dart';
import 'package:ews/screens/main_shell.dart';
import 'package:ews/screens/sensor_screen.dart';
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

  final sample = EwsData.fromJson(
    jsonDecode(ewsSampleJson) as Map<String, dynamic>,
  );

  void usePhoneSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Widget app(Widget home, {double textScale = 1}) => MaterialApp(
    theme: buildAppTheme(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: home,
  );

  // Timer pengambilan berkala harus berhenti sebelum tes selesai.
  Future<void> unmount(WidgetTester tester) =>
      tester.pumpWidget(const SizedBox());

  testWidgets('menampilkan status, kartu sensor, dan riwayat', (tester) async {
    usePhoneSize(tester);
    await tester.pumpWidget(app(SensorScreen(load: () async => sample)));
    await tester.pump();

    expect(find.text('Pantau sensor'), findsOneWidget);
    expect(find.textContaining('terakhir dicek'), findsOneWidget);
    expect(find.text('Penyebab: Kelembapan tanah 55%'), findsOneWidget);
    expect(find.text('55%'), findsOneWidget);
    expect(find.text('Waspada mulai 50%'), findsOneWidget);
    expect(find.text('Waspada mulai 15°'), findsOneWidget);
    // Dua wilayah, jadi status tiap wilayah ikut tampil.
    expect(find.text('Aman'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Perubahan status'), 300);
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
    expect(find.text('Waspada · Lereng Kebun Kopi'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('gagal memuat lalu berhasil setelah Coba lagi', (tester) async {
    usePhoneSize(tester);
    var calls = 0;
    await tester.pumpWidget(
      app(
        SensorScreen(
          load: () async {
            calls++;
            if (calls == 1) throw Exception('tanpa sinyal');
            return sample;
          },
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Belum bisa mengambil data sensor'), findsOneWidget);

    await tester.tap(find.text('Coba lagi'));
    await tester.pump();

    expect(find.text('55%'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('angka lama tetap tampil saat sinyal putus', (tester) async {
    usePhoneSize(tester);
    var online = true;
    await tester.pumpWidget(
      app(
        SensorScreen(
          load: () async => online ? sample : throw Exception('putus'),
        ),
      ),
    );
    await tester.pump();

    online = false;
    await tester.pump(ewsRefreshInterval);

    expect(find.text('Belum tersambung ke server'), findsOneWidget);
    expect(find.text('55%'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('berhenti mengambil data saat menu lain dibuka', (tester) async {
    usePhoneSize(tester);
    var calls = 0;
    Widget screen(bool active) => app(
      SensorScreen(
        active: active,
        load: () async {
          calls++;
          return sample;
        },
      ),
    );

    await tester.pumpWidget(screen(true));
    await tester.pump(ewsRefreshInterval);
    expect(calls, 2);

    await tester.pumpWidget(screen(false));
    await tester.pump(ewsRefreshInterval * 3);
    expect(calls, 2);

    // Kembali ke menu ini langsung mengambil data baru.
    await tester.pumpWidget(screen(true));
    await tester.pump();
    expect(calls, 3);
    await unmount(tester);
  });

  testWidgets('teks diperbesar tidak terpotong', (tester) async {
    usePhoneSize(tester);
    await tester.pumpWidget(
      app(SensorScreen(load: () async => sample), textScale: 2),
    );
    await tester.pump();

    await tester.scrollUntilVisible(find.text('Perubahan status'), 300);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('menu Sensor di kanan Beranda membuka halaman pantau', (
    tester,
  ) async {
    usePhoneSize(tester);
    await tester.pumpWidget(
      app(
        MainShell(
          initialData: waspadaData,
          showMapTiles: false,
          locateOnReport: false,
          loadSensors: () async => sample,
        ),
      ),
    );

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

  testWidgets('data contoh ditandai jelas', (tester) async {
    usePhoneSize(tester);
    await tester.pumpWidget(
      app(SensorScreen(load: EwsSampleFeed(random: Random(1)).next)),
    );
    await tester.pump();

    expect(find.text('Data contoh'), findsOneWidget);
    expect(find.text('Lereng Kebun Kopi, data contoh'), findsOneWidget);
    expect(find.text('Data contoh, bukan bacaan alat'), findsOneWidget);
    expect(find.textContaining(RegExp(r'[Bb]acaan \d')), findsNothing);
    await unmount(tester);
  });
}
