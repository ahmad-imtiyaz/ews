import 'dart:convert';

import 'package:ews/data/ews_data.dart';
import 'package:ews/data/monitoring.dart';
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

  group('balasan asli desalumeneng.id', () {
    final live = EwsData.fromJson(
      jsonDecode(ewsLiveJson) as Map<String, dynamic>,
    );

    test('terbaca tanpa galat dan field baru ikut terbaca', () {
      final area = live.areas.single;
      expect(area.name, 'Titik Area 2');
      expect(area.offline, isTrue);
      expect(area.unknownCondition, isTrue);
      expect(area.sensors.map((s) => s.text), ['0%', '0%', '9,9°', '97,9%']);
      expect(live.offlineNotices.single, contains('jangan anggap sudah aman'));
      // Ambang dari server, bukan angka cadangan di aplikasi.
      expect(live.thresholds['kemiringan']!.waspada, 5);
    });

    test('wilayah server jadi EWS-02, EWS-01 tetap tanpa data', () {
      final data = monitoringFrom(live);
      final [ews01, ews02] = data.sensors;

      expect(ews01.id, 'EWS-01');
      expect(ews01.area, isNull);
      expect(ews01.status, MonitoringStatus.noData);

      expect(ews02.id, 'EWS-02');
      expect(ews02.area!.name, 'Titik Area 2');
      // Diam saat Waspada tetap Waspada, bukan dianggap aman.
      expect(ews02.status, MonitoringStatus.waspada);
      expect(ews02.isStale, isTrue);
      // Titik di aplikasi sama dengan lintang/bujur di server.
      expect(ews02.position.latitude, -7.186625);
      expect(ews02.position.longitude, 109.591824);

      expect(data.status, MonitoringStatus.waspada);
      expect(data.summary, startsWith('EWS-02 Sikembang: Kemiringan 9,9°.'));
      expect(data.summary, contains('jangan anggap sudah aman'));
      expect(areaLabel(live, 'Titik Area 2'), 'EWS-02 Sikembang');
    });

    test('catatan berisi alat berhenti lalu perubahan status dari server', () {
      final log = monitoringFrom(live).log;
      expect(log.map((e) => e.title), [
        'EWS-02 berhenti mengirim data',
        'EWS-02 berubah menjadi Awas',
      ]);
      expect(log[1].status, MonitoringStatus.awas);
      expect(log[1].note, 'Kabel EWS putus, Kemiringan 9,9°');
    });
  });

  group('monitoringFrom', () {
    EwsData area({required String status, required bool offline}) =>
        EwsData.fromJson({
          'utama': {'status': status, 'saran': ''},
          'wilayah': [
            {
              'id': 1,
              'nama': 'Titik Area 2',
              'status': status,
              'waktu': '12-11-2026 20:33',
              'offline': offline,
              'sensor': <String, dynamic>{},
            },
          ],
        });

    test('belum pernah berhasil memuat', () {
      final data = monitoringFrom(null);
      expect(data.loadFailed, isTrue);
      expect(data.title, 'Belum bisa memuat');
      expect(
        data.sensors.map((s) => s.status),
        everyElement(MonitoringStatus.noData),
      );
    });

    test('Aman yang sudah diam tidak lagi dianggap Normal', () {
      expect(
        monitoringFrom(area(status: 'Aman', offline: false)).status,
        MonitoringStatus.normal,
      );
      final stale = monitoringFrom(area(status: 'Aman', offline: true));
      expect(stale.status, MonitoringStatus.noData);
      expect(stale.summary, contains('tidak mengirim data'));
    });

    test('EWS-01 yang belum terhubung tidak menurunkan status desa', () {
      // Hanya EWS-02 yang terhubung, jadi Normal-nya tidak tertutup oleh
      // EWS-01 yang memang belum mengirim.
      final data = monitoringFrom(area(status: 'Aman', offline: false));
      expect(data.status, MonitoringStatus.normal);
      expect(data.summary, 'Semua sensor EWS-02 Sikembang normal.');
    });

    test('gagal memperbarui tetap menampilkan data sebelumnya', () {
      final data = monitoringFrom(
        area(status: 'Waspada', offline: false),
        refreshFailed: true,
      );
      expect(data.status, MonitoringStatus.waspada);
      expect(data.updated, 'Belum tersambung');
    });
  });

  test('shortTime menyingkat waktu server', () {
    final now = DateTime(2026, 11, 12, 21);
    expect(shortTime('12-11-2026 20:33', now: now), '20.33');
    expect(shortTime('6-11-2026 08:05', now: now), '6 Nov, 08.05');
    expect(shortTime('bukan waktu', now: now), 'bukan waktu');
  });
}
