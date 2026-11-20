import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:ews/app_theme.dart';
import 'package:ews/data/ews_data.dart';
import 'package:ews/data/monitoring.dart';
import 'package:ews/data/village_map.dart';
import 'package:ews/screens/home_screen.dart';
import 'package:ews/services/ews_cache.dart';
import 'package:ews/services/ews_feed.dart';
import 'package:ews/services/notification_inbox.dart';
import 'package:ews/services/notification_service.dart';
import 'package:ews/services/phone_location.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ews_sample.dart';

/// Balasan server dengan satu wilayah (EWS) berstatus [status].
String bodyWith(String status, {String? note}) => jsonEncode({
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
  'log': <Object>[],
});

EwsData parse(String body) =>
    EwsData.fromJson(jsonDecode(body) as Map<String, dynamic>);

void main() {
  setUpAll(loadVillageMap);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final aman = bodyWith('Aman');
  final awas = bodyWith('Awas', note: 'Kabel EWS putus');

  group('simpanan data server', () {
    test('balasan yang tersimpan terbaca lagi', () async {
      final at = DateTime(2026, 11, 19, 9, 12);
      await EwsCache().save(body: ewsLiveJson, checkedAt: at);

      final saved = await EwsCache().read();
      expect(saved!.checkedAt, at);
      expect(saved.data.areas, isNotEmpty);
    });

    test('tanpa balasan baru (304) hanya waktunya yang diperbarui', () async {
      await EwsCache().save(body: awas, checkedAt: DateTime(2026, 11, 19, 9));
      await EwsCache().save(checkedAt: DateTime(2026, 11, 19, 10));

      final saved = await EwsCache().read();
      expect(saved!.checkedAt, DateTime(2026, 11, 19, 10));
      expect(saved.data.summary.status, 'Awas');
    });

    test('simpanan rusak dianggap tidak ada', () async {
      SharedPreferences.setMockInitialValues({
        'ews.body': '<html>login wifi</html>',
        'ews.checkedAt': '2026-11-19T09:00:00.000',
      });
      expect(await EwsCache().read(), isNull);
    });
  });

  group('EwsFeed dengan simpanan', () {
    test('restore mengisi data dari HP lalu diganti data server', () async {
      await EwsCache().save(body: aman, checkedAt: DateTime(2026, 11, 19, 9));
      final feed = EwsFeed(load: () async => parse(awas), cache: EwsCache());
      addTearDown(feed.dispose);

      await feed.restore();
      expect(feed.fromCache, isTrue);
      expect(feed.data!.summary.status, 'Aman');

      await feed.refresh();
      expect(feed.fromCache, isFalse);
      expect(feed.data!.summary.status, 'Awas');
    });

    test('restore tidak menimpa data server yang sudah ada', () async {
      await EwsCache().save(body: aman, checkedAt: DateTime(2026, 11, 19, 9));
      final feed = EwsFeed(load: () async => parse(awas), cache: EwsCache());
      addTearDown(feed.dispose);

      await feed.refresh();
      await feed.restore();
      expect(feed.fromCache, isFalse);
      expect(feed.data!.summary.status, 'Awas');
    });

    test('data dianggap lama setelah 15 menit', () async {
      final now = DateTime(2026, 11, 20, 13);
      Future<bool> staleAfter(Duration age) async {
        await EwsCache().save(body: aman, checkedAt: now.subtract(age));
        final feed = EwsFeed(load: () async => parse(aman), cache: EwsCache());
        addTearDown(feed.dispose);
        await feed.restore();
        return withClock(Clock.fixed(now), () => feed.isStale);
      }

      expect(await staleAfter(const Duration(minutes: 5)), isFalse);
      expect(await staleAfter(const Duration(minutes: 15)), isTrue);
    });
  });

  group('Beranda dengan data lama', () {
    final checkedAt = DateTime(2026, 11, 19, 9, 12);

    test('Normal yang lama tidak tampil aman', () {
      final data = monitoringFrom(
        parse(aman),
        outdated: true,
        checkedAt: checkedAt,
      );
      expect(data.status, MonitoringStatus.noData);
      expect(data.sensors.every((s) => s.isStale), isTrue);
      expect(data.log.first.title, 'Belum tersambung ke server');
      expect(data.summary, contains('Jangan anggap sudah aman'));
    });

    test('Awas yang lama tetap Awas', () {
      final data = monitoringFrom(
        parse(awas),
        outdated: true,
        checkedAt: checkedAt,
      );
      expect(data.status, MonitoringStatus.awas);
      expect(data.summary, startsWith('EWS Sikembang: Kabel EWS putus.'));
    });
  });

  group('riwayat lonceng', () {
    NotificationEntry entry(int i) => NotificationEntry(
      status: MonitoringStatus.waspada,
      title: 'Waspada $i',
      body: '',
      time: DateTime(2026, 11, 19, 9, i % 60),
    );

    test('tetap ada setelah aplikasi dibuka lagi', () async {
      final first = NotificationInbox(service: _FakeNotifications());
      first
        ..add(entry(1))
        ..add(entry(2));
      await pumpEventQueue();

      final reopened = NotificationInbox(service: _FakeNotifications());
      await pumpEventQueue();
      expect(reopened.entries.map((e) => e.title), ['Waspada 1', 'Waspada 2']);
      expect(reopened.entries.last.time, DateTime(2026, 11, 19, 9, 2));
      expect(reopened.unread, 2);
    });

    test('yang paling lama dibuang setelah 50', () async {
      final inbox = NotificationInbox(service: _FakeNotifications());
      await pumpEventQueue();
      for (var i = 1; i <= 55; i++) {
        inbox.add(entry(i));
      }
      expect(inbox.entries, hasLength(NotificationInbox.maxEntries));
      expect(inbox.entries.first.title, 'Waspada 6');
      expect(inbox.unread, NotificationInbox.maxEntries);
    });

    test('simpanan rusak tidak menghentikan lonceng', () async {
      SharedPreferences.setMockInitialValues({'notifications': '{rusak'});
      final inbox = NotificationInbox(service: _FakeNotifications());
      await pumpEventQueue();
      inbox.add(entry(1));
      expect(inbox.entries, hasLength(1));
    });
  });

  group('peringatan saat sinyal buruk', () {
    late _FakeNotifications service;
    late NotificationInbox inbox;

    Future<void> openHome(WidgetTester tester, EwsFeed feed) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      service = _FakeNotifications();
      inbox = NotificationInbox(service: service);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: HomeScreen(
            feed: feed,
            inbox: inbox,
            showMapTiles: false,
            locate: () => Stream.error(
              const LocationUnavailable(LocationProblem.notFound),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('data simpanan yang lama tidak berbunyi, data server '
        'berikutnya dicatat tanpa bunyi', (tester) async {
      await EwsCache().save(
        body: awas,
        checkedAt: DateTime.now().subtract(const Duration(hours: 2)),
      );
      String? current;
      final feed = EwsFeed(
        load: () async => parse(current ?? (throw Exception('tanpa sinyal'))),
        cache: EwsCache(),
      );
      addTearDown(feed.dispose);
      await feed.restore();
      await feed.refresh();
      await openHome(tester, feed);

      expect(find.text('Belum tersambung ke server'), findsOneWidget);
      expect(inbox.entries, isEmpty);

      current = awas;
      await feed.refresh();
      await tester.pumpAndSettle();
      expect(inbox.entries.single.status, MonitoringStatus.awas);
      expect(service.alerts, isEmpty);
    });

    testWidgets('sinyal HP putus lama tidak membunyikan "Tidak ada data"', (
      tester,
    ) async {
      String? current = aman;
      final feed = EwsFeed(
        load: () async => parse(current ?? (throw Exception('tanpa sinyal'))),
      );
      addTearDown(feed.dispose);
      await feed.refresh();
      await openHome(tester, feed);

      current = null;
      await tester.pump(const Duration(minutes: 16));
      await feed.refresh();
      await tester.pumpAndSettle();
      expect(find.text('Belum tersambung ke server'), findsOneWidget);
      expect(service.alerts, isEmpty);
      expect(inbox.entries, isEmpty);

      // Tersambung lagi dan masih Normal: tidak ada yang perlu dicatat.
      current = aman;
      await feed.refresh();
      await tester.pumpAndSettle();
      expect(find.text('Belum tersambung ke server'), findsNothing);
      expect(service.alerts, isEmpty);
      expect(inbox.entries, isEmpty);
    });

    testWidgets('membuka aplikasi lagi saat Awas tidak menumpuk catatan '
        'yang sama', (tester) async {
      Future<void> openApp() async {
        final feed = EwsFeed(load: () async => parse(awas));
        addTearDown(feed.dispose);
        await feed.refresh();
        await openHome(tester, feed);
      }

      await openApp();
      expect(inbox.entries, hasLength(1));

      await tester.pumpWidget(const SizedBox());
      await openApp();
      expect(inbox.entries, hasLength(1));
      expect(inbox.unread, 1);
    });

    testWidgets('halaman Tentang terbuka dari bar atas', (tester) async {
      final feed = EwsFeed(load: () async => parse(aman));
      addTearDown(feed.dispose);
      await feed.refresh();
      await openHome(tester, feed);

      await tester.tap(find.byTooltip('Tentang aplikasi'));
      await tester.pumpAndSettle();
      expect(find.text('Keadaan darurat'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Data dan privasi'), 200);
      expect(tester.takeException(), isNull);
    });
  });
}

class _FakeNotifications extends NotificationService {
  final alerts = <MonitoringStatus>[];

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> startPush({required PushMessageCallback onMessage}) async {}

  @override
  Future<void> showStatusAlert({
    required MonitoringStatus status,
    required String title,
    required String body,
  }) async {
    alerts.add(status);
  }
}
