import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:ews/data/ews_data.dart';
import 'package:ews/data/monitoring.dart';
import 'package:ews/screens/status_report_sheet.dart';
import 'package:ews/services/ews_history.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

int _ms(DateTime time) => time.millisecondsSinceEpoch;

PastReading _reading(String key, String name, double? value) => PastReading(
  key: key,
  name: name,
  unit: key == 'kemiringan' ? '°' : '%',
  value: value,
  threshold: key == 'kelembapan_udara' ? null : const EwsThreshold(50, 100),
);

final _readings = PastReadings(
  from: DateTime(2026, 11, 23, 17, 40),
  step: const Duration(minutes: 10),
  readings: [
    _reading('kelembapan_tanah', 'Kelembapan tanah', 3.34),
    _reading('intensitas_hujan', 'Intensitas hujan', 56.3),
    _reading('kemiringan', 'Kemiringan', null),
    _reading('kelembapan_udara', 'Kelembapan udara', 71),
  ],
);

void main() {
  group('fetchReadingsAt', () {
    final requests = <Uri>[];
    final client = MockClient((request) async {
      requests.add(request.url);
      final key = request.url.queryParameters['sensor']!;
      // Bentuk balasan sama dengan server sungguhan.
      return http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'sensor': {
              'kelembapan_tanah': 'Kelembapan tanah',
              'intensitas_hujan': 'Intensitas hujan',
              'kemiringan': 'Kemiringan',
              'kelembapan_udara': 'Kelembapan udara',
            }[key],
            'satuan': key == 'kemiringan' ? '°' : '%',
            'ambang': key == 'kelembapan_udara'
                ? null
                : {'waspada': 50, 'validasi': 100},
            'titik': [
              {'t': _ms(DateTime(2026, 11, 23, 17, 30)), 'y': 73.95},
              {'t': _ms(DateTime(2026, 11, 23, 17, 40)), 'y': 56.3},
              {'t': _ms(DateTime(2026, 11, 23, 17, 50)), 'y': 0},
            ],
          }),
        ),
        200,
      );
    });

    setUp(requests.clear);

    test('mengambil blok 10 menit yang memuat jam kejadian', () async {
      final result = await withClock(
        Clock.fixed(DateTime(2026, 11, 23, 22)),
        () => fetchReadingsAt(DateTime(2026, 11, 23, 17, 43), client: client),
      );

      expect(requests, hasLength(4));
      expect(requests.first.queryParameters['rentang'], '24j');
      expect(result.from, DateTime(2026, 11, 23, 17, 40));
      expect(result.step, const Duration(minutes: 10));
      final hujan = result.readings[1];
      expect(hujan.name, 'Intensitas hujan');
      expect(hujan.value, 56.3);
      expect(hujan.level, SensorLevel.waspada);
      expect(result.readings[3].threshold, isNull);
    });

    test('kejadian lama memakai blok per jam, lebih dari 7 hari ditolak', () {
      final now = DateTime(2026, 11, 23, 22);
      expect(
        withClock(
          Clock.fixed(now),
          () => fetchReadingsAt(DateTime(2026, 11, 10), client: client),
        ),
        throwsA(isA<TooOldForHistory>()),
      );
    });

    test('blok tanpa kiriman terbaca tidak ada data', () async {
      final result = await withClock(
        Clock.fixed(DateTime(2026, 11, 23, 22)),
        () => fetchReadingsAt(DateTime(2026, 11, 23, 12, 5), client: client),
      );
      expect(result.readings.every((r) => r.value == null), isTrue);
    });
  });

  test('pemicu dari keterangan, atau dari sensor yang lewat batas', () {
    final readings = _readings.readings;
    expect(
      triggerKeys('Intensitas hujan 56,3%', MonitoringStatus.waspada, readings),
      {'intensitas_hujan'},
    );
    expect(triggerKeys('Kabel EWS putus', MonitoringStatus.awas, readings), {
      'intensitas_hujan',
    });
    expect(
      triggerKeys('Kembali normal', MonitoringStatus.normal, readings),
      isEmpty,
    );
  });

  test('lama berlangsung', () {
    expect(durationLabel(const Duration(seconds: 20)), 'kurang dari 1 menit');
    expect(durationLabel(const Duration(minutes: 9)), '9 menit');
    expect(
      durationLabel(const Duration(hours: 2, minutes: 5)),
      '2 jam 5 menit',
    );
  });

  testWidgets('report menandai sensor pemicu dan lama berlangsung', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatusReportSheet(
            item: (
              status: MonitoringStatus.waspada,
              title: 'Waspada · EWS Sikembang',
              note: 'Intensitas hujan 56,3%',
              time: '17.43',
              at: DateTime(2026, 11, 23, 17, 43),
            ),
            next: (
              status: MonitoringStatus.normal,
              title: 'Aman · EWS Sikembang',
              note: 'Kembali normal',
              time: '17.52',
              at: DateTime(2026, 11, 23, 17, 52),
            ),
            load: (_) async => _readings,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Senin, 23 November 2026, 17.43 WIB'),
      findsOneWidget,
    );
    expect(
      find.text('Berlangsung 9 menit, lalu berubah jadi Normal pukul 17.52.'),
      findsOneWidget,
    );
    expect(
      find.text('Angka tertinggi antara 17.40 dan 17.50.'),
      findsOneWidget,
    );
    expect(find.text('Pemicu notifikasi'), findsOneWidget);
    expect(find.text('56,3%'), findsOneWidget);
    expect(find.text('Waspada · waspada mulai 50%'), findsOneWidget);
    expect(
      find.text('Tidak ada kiriman saat itu · waspada mulai 50°'),
      findsOneWidget,
    );
  });

  testWidgets('perubahan di hari lain disebut tanggalnya', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatusReportSheet(
            item: (
              status: MonitoringStatus.waspada,
              title: 'Waspada',
              note: 'Intensitas hujan 56,3%',
              time: '23.50',
              at: DateTime(2026, 11, 23, 23, 50),
            ),
            next: (
              status: MonitoringStatus.normal,
              title: 'Aman',
              note: 'Kembali normal',
              time: '00.20',
              at: DateTime(2026, 11, 24, 0, 20),
            ),
            load: (_) async => _readings,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Berlangsung 30 menit, lalu berubah jadi Normal pada 24 Nov, 00.20.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('bacaan gagal diambil bisa dicoba lagi', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatusReportSheet(
            item: (
              status: MonitoringStatus.waspada,
              title: 'Waspada',
              note: 'Intensitas hujan 56,3%',
              time: '17.43',
              at: DateTime(2026, 11, 23, 17, 43),
            ),
            load: (_) async {
              if (calls++ == 0) throw http.ClientException('putus');
              return _readings;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Catatan terbaru, belum ada perubahan sesudahnya.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Coba lagi'));
    await tester.pumpAndSettle();
    expect(find.text('Pemicu notifikasi'), findsOneWidget);
  });
}
