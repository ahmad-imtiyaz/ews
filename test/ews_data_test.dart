import 'dart:convert';
import 'dart:math';

import 'package:ews/data/ews_data.dart';
import 'package:ews/data/ews_sample.dart';
import 'package:ews/data/sample_data.dart';
import 'package:ews/services/ews_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'ews_sample.dart';

void main() {
  group('EwsData.fromJson', () {
    final data = EwsData.fromJson(
      jsonDecode(ewsSampleJson) as Map<String, dynamic>,
    );

    test('membaca bagian utama dan status server', () {
      expect(data.summary.status, 'Waspada');
      expect(data.summary.statusKind, MonitoringStatus.waspada);
      expect(data.summary.location, 'Lereng Kebun Kopi');
      expect(statusFromServer('Aman'), MonitoringStatus.normal);
      expect(statusFromServer('Awas'), MonitoringStatus.awas);
      expect(statusFromServer(null), MonitoringStatus.noData);
    });

    test('sensor tetap urut seperti di web dan angka bulat jadi double', () {
      final sensors = data.areas.first.sensors;
      expect(sensors.map((s) => s.key), [
        'kelembapan_tanah',
        'intensitas_hujan',
        'kemiringan',
        'kelembapan_udara',
      ]);
      expect(sensors[0].value, 55.0);
      expect(sensors[0].level, SensorLevel.waspada);
      expect(sensors[2].value, -9.9);
      expect(sensors[2].unit, '°');
      expect(sensors[3].level, SensorLevel.notRated);
    });

    test('sensor tanpa nilai dan wilayah offline', () {
      final offline = data.areas[1];
      expect(offline.offline, isTrue);
      expect(offline.sensors[1].value, isNull);
      expect(offline.sensors[1].word, 'Tidak ada data');
    });

    test('ambang hanya untuk tiga sensor', () {
      expect(data.thresholds.keys, hasLength(3));
      expect(data.thresholds['kemiringan']!.waspada, 15);
      expect(data.thresholds['kelembapan_udara'], isNull);
    });

    test('bagian yang tidak dikirim server dianggap kosong', () {
      final empty = EwsData.fromJson({
        'utama': {'status': null, 'saran': 'Belum ada data.'},
      });
      expect(empty.areas, isEmpty);
      expect(empty.log, isEmpty);
      expect(empty.thresholds, isEmpty);
    });
  });

  test('formatNumber memakai koma', () {
    expect(formatNumber(24), '24');
    expect(formatNumber(100), '100');
    expect(formatNumber(12.35), '12,35');
    expect(formatNumber(50.5), '50,5');
  });

  group('EwsApi', () {
    test('memakai data lama saat server membalas 304', () async {
      final sentEtags = <String?>[];
      final client = MockClient((request) async {
        sentEtags.add(request.headers['If-None-Match']);
        if (request.headers['If-None-Match'] == '"v1"') {
          return http.Response('', 304);
        }
        return http.Response.bytes(
          utf8.encode(ewsSampleJson),
          200,
          headers: {'etag': '"v1"', 'content-type': 'application/json'},
        );
      });
      final api = EwsApi('http://ews.test', client: client);

      final first = await api.fetch();
      final second = await api.fetch();

      expect(sentEtags, [null, '"v1"']);
      expect(identical(first, second), isTrue);
      // "°" tetap utuh karena isi dibaca sebagai UTF-8.
      expect(first.areas.first.sensors[2].text, '-9,9°');
    });

    test('kode selain 200 dianggap gagal', () async {
      final api = EwsApi(
        'http://ews.test',
        client: MockClient((_) async => http.Response('', 500)),
      );
      expect(api.fetch(), throwsA(isA<http.ClientException>()));
    });
  });

  group('EwsSampleFeed', () {
    test('naik turun tipis dan tetap di rentang Normal', () async {
      final feed = EwsSampleFeed(random: Random(7));
      EwsData? previous;
      for (var i = 0; i < 500; i++) {
        final data = await feed.next();
        expect(data.sample, isTrue);
        expect(data.summary.status, 'Aman');
        expect(data.log, isEmpty);

        final sensors = data.areas.single.sensors;
        expect(
          sensors.take(3).map((s) => s.level),
          everyElement(SensorLevel.normal),
        );
        expect(sensors[3].level, SensorLevel.notRated);

        if (previous != null) {
          final before = previous.areas.single.sensors;
          // Kelembapan tanah tidak pernah melompat lebih dari 1,5% sekali ambil.
          expect(
            (sensors[0].value! - before[0].value!).abs(),
            lessThanOrEqualTo(1.5),
          );
        }
        previous = data;
      }
    });

    test('teks memakai koma dan satuan seperti server', () async {
      final sensors = (await EwsSampleFeed(
        random: Random(1),
      ).next()).areas.single.sensors;
      expect(sensors[0].text, matches(RegExp(r'^\d+(,\d)?%$')));
      expect(sensors[2].text, matches(RegExp(r'^-?\d+(,\d)?°$')));
    });
  });
}
