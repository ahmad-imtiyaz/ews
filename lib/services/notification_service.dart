import 'dart:async';
import 'dart:ui';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../data/monitoring.dart';

typedef PushMessageCallback = void Function(
  MonitoringStatus status,
  String title,
  String body,
);

/// Notifikasi bawaan HP. Saat aplikasi tertutup, Android sendiri yang menampilkan
/// kiriman Firebase memakai channel di bawah, jadi kode ini tidak ikut berjalan.
class NotificationService {
  NotificationService([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  /// Semua HP warga berlangganan topik ini untuk menerima peringatan.
  static const pushTopic = 'warga-lumeneng';

  final _subscriptions = <StreamSubscription<RemoteMessage>>[];

  // Suara channel ikut volume nada dering, bukan volume notifikasi yang di
  // banyak HP jauh lebih kecil. Android mengunci setelan suara channel sejak
  // pertama dibuat, jadi tiap ganti suara atau volume, id-nya harus naik.
  static const _awasChannel = AndroidNotificationChannel(
    'ews_awas_v3',
    'Peringatan Awas',
    description: 'Titik pantau berstatus Awas.',
    importance: Importance.max,
    sound: RawResourceAndroidNotificationSound('ews_awas'),
    audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
  );

  static const _waspadaChannel = AndroidNotificationChannel(
    'ews_waspada_v3',
    'Peringatan Waspada',
    description: 'Titik pantau perlu diperhatikan atau tidak mengirim data.',
    importance: Importance.max,
    sound: RawResourceAndroidNotificationSound('ews_waspada'),
    audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
  );

  /// Biru tua dari logo aplikasi, sama dengan `notification_color` di Android.
  static const _logoBlue = Color(0xFF003163);

  static const _oldChannelIds = [
    'ews_awas_v1',
    'ews_waspada_v1',
    'ews_awas_v2',
    'ews_waspada_v2',
  ];

  final FlutterLocalNotificationsPlugin _plugin;
  int _nextId = 1;

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  Future<void> initialize() async {
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_notification'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
      );
      // Channel harus sudah ada sebelum kiriman dari server datang, supaya
      // notifikasi saat aplikasi tertutup tetap memakai suara EWS.
      await _android?.createNotificationChannel(_awasChannel);
      await _android?.createNotificationChannel(_waspadaChannel);
      for (final id in _oldChannelIds) {
        await _android?.deleteNotificationChannel(channelId: id);
      }
    } catch (_) {
      // Tanpa notifikasi HP, riwayat di aplikasi tetap berjalan.
    }
  }

  Future<bool> requestPermission() async {
    try {
      return await _android?.requestNotificationsPermission() ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> isAllowed() async {
    try {
      return await _android?.areNotificationsEnabled() ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> startPush({required PushMessageCallback onMessage}) async {
    try {
      void record(RemoteMessage message) {
        final notification = message.notification;
        if (notification == null) return;
        onMessage(
          _statusOf(message),
          notification.title ?? 'Peringatan EWS',
          notification.body ?? '',
        );
      }

      // Firebase tidak menampilkan kiriman saat aplikasi sedang dibuka.
      _subscriptions.add(
        FirebaseMessaging.onMessage.listen((message) {
          final notification = message.notification;
          if (notification == null) return;
          showStatusAlert(
            status: _statusOf(message),
            title: notification.title ?? 'Peringatan EWS',
            body: notification.body ?? '',
          );
          record(message);
        }),
      );
      _subscriptions.add(FirebaseMessaging.onMessageOpenedApp.listen(record));

      final messaging = FirebaseMessaging.instance;
      final initial = await messaging.getInitialMessage();
      if (initial != null) record(initial);
      await messaging.subscribeToTopic(pushTopic);
    } catch (_) {
      // Tanpa internet atau Firebase, langganan dicoba lagi saat aplikasi dibuka.
    }
  }

  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
  }

  MonitoringStatus _statusOf(RemoteMessage message) {
    final isAwas =
        message.data['status'] == 'awas' ||
        message.notification?.android?.channelId == _awasChannel.id;
    return isAwas ? MonitoringStatus.awas : MonitoringStatus.waspada;
  }

  Future<void> showStatusAlert({
    required MonitoringStatus status,
    required String title,
    required String body,
  }) async {
    final isAwas = status == MonitoringStatus.awas;
    final channel = isAwas ? _awasChannel : _waspadaChannel;
    try {
      await _plugin.show(
        id: _nextId++,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            channel.id,
            channel.name,
            channelDescription: channel.description,
            importance: channel.importance,
            priority: Priority.high,
            icon: 'ic_notification',
            color: _logoBlue,
            sound: channel.sound,
            audioAttributesUsage: channel.audioAttributesUsage,
            styleInformation: BigTextStyleInformation(body),
          ),
        ),
      );
    } catch (_) {
      // Riwayat di aplikasi tetap berjalan.
    }
  }
}
