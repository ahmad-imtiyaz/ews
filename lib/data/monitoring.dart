import 'package:latlong2/latlong.dart';

import '../config.dart';
import 'ews_data.dart';

// Keadaan Beranda dibentuk dari `GET /api/ews/data` (lihat ews_data.dart).
// Titik dan area pantau dua alat dari tim lapangan (10 November 2026): EWS-01
// di Jomparang, EWS-02 di barat permukiman Sikembang. Koordinatnya sama
// dengan `lintang`/`bujur` di server, areanya di assets/peta/area_ews.geojson.

enum MonitoringStatus {
  normal('Normal'),
  waspada('Waspada'),
  awas('Awas'),
  noData('Tidak ada data');

  const MonitoringStatus(this.label);

  final String label;

  /// Urutan untuk mencari kondisi terburuk. Tidak ada data di atas Normal
  /// karena alat yang diam belum tentu aman.
  int get _severity => switch (this) {
    normal => 0,
    noData => 1,
    waspada => 2,
    awas => 3,
  };
}

class EwsDevice {
  const EwsDevice(this.id, this.place, this.position);

  final String id;
  final String place;
  final LatLng position;
}

const ewsDevices = [
  EwsDevice('EWS-01', 'Jomparang', LatLng(-7.185390, 109.588069)),
  EwsDevice('EWS-02', 'Sikembang', LatLng(-7.186625, 109.591824)),
];

EwsDevice? deviceOfArea(EwsArea area) => switch (ewsDeviceOfArea[area.id]) {
  final id? => ewsDevices.where((d) => d.id == id).firstOrNull,
  null => null,
};

/// Nama wilayah dari server ("Titik Area 2") jadi nama alat di aplikasi
/// ("EWS-02 Sikembang") bila wilayah itu terhubung ke alat.
String areaLabel(EwsData data, String serverName) {
  for (final area in data.areas) {
    if (area.name != serverName) continue;
    if (deviceOfArea(area) case final device?) {
      return '${device.id} ${device.place}';
    }
  }
  return serverName;
}

class SensorPoint {
  const SensorPoint({required this.device, required this.status, this.area});

  final EwsDevice device;
  final MonitoringStatus status;

  /// `null` selama alat belum terhubung ke server.
  final EwsArea? area;

  String get id => device.id;
  String get place => device.place;
  LatLng get position => device.position;

  /// Bacaannya bukan kondisi sekarang: alat belum terhubung atau diam.
  bool get isStale => area?.offline ?? true;
}

class LogEntry {
  const LogEntry({
    required this.time,
    required this.title,
    required this.status,
    this.note = '',
  });

  final String time;
  final String title;
  final String note;
  final MonitoringStatus status;
}

class MonitoringData {
  const MonitoringData({
    required this.status,
    required this.summary,
    this.updated,
    this.sensors = const [],
    this.log = const [],
    this.loadFailed = false,
  });

  final MonitoringStatus status;
  final String summary;
  final String? updated;
  final List<SensorPoint> sensors;
  final List<LogEntry> log;
  final bool loadFailed;

  String get title => loadFailed ? 'Belum bisa memuat' : status.label;
}

MonitoringStatus _pointStatus(EwsArea? area) {
  if (area == null) return MonitoringStatus.noData;
  final status = area.statusKind;
  // Bacaan lama yang Normal belum tentu masih aman. Waspada dan Awas tetap,
  // karena alat bisa mati justru saat tanahnya bergerak.
  if (area.offline && status == MonitoringStatus.normal) {
    return MonitoringStatus.noData;
  }
  return status;
}

/// [ews] `null` berarti data belum pernah berhasil diambil. [refreshFailed]
/// berarti pengambilan terakhir gagal dan yang tampil masih data sebelumnya.
MonitoringData monitoringFrom(EwsData? ews, {bool refreshFailed = false}) {
  final areaOf = <String, EwsArea>{
    for (final area in ews?.areas ?? const <EwsArea>[])
      if (deviceOfArea(area) case final device?) device.id: area,
  };
  final points = [
    for (final device in ewsDevices)
      SensorPoint(
        device: device,
        area: areaOf[device.id],
        status: _pointStatus(areaOf[device.id]),
      ),
  ];

  if (ews == null) {
    return MonitoringData(
      status: MonitoringStatus.noData,
      summary: 'Kondisi sekarang belum diketahui. Periksa sinyal, lalu coba '
          'lagi.',
      sensors: points,
      loadFailed: true,
    );
  }

  final connected = [
    for (final point in points)
      if (point.area != null) point,
  ];
  final worst = connected.isEmpty
      ? null
      : connected.reduce(
          (a, b) => b.status._severity > a.status._severity ? b : a,
        );
  // Waktu bacaan alat yang kondisinya terburuk, sama dengan isi ringkasan.
  final readTime = worst?.area!.time;

  return MonitoringData(
    status: worst?.status ?? MonitoringStatus.noData,
    summary: worst == null
        ? 'Belum ada alat yang mengirim data.'
        : _summary(worst, connected),
    updated: refreshFailed
        ? 'Belum tersambung'
        : readTime == null
        ? null
        : 'Bacaan ${shortTime(readTime)}',
    sensors: points,
    log: [
      for (final point in connected)
        if (point.area case final area? when area.offline)
          LogEntry(
            time: area.time == null ? '' : shortTime(area.time!),
            title: '${point.id} berhenti mengirim data',
            status: MonitoringStatus.noData,
            note: point.status == MonitoringStatus.noData
                ? 'Kondisi sekarang belum diketahui.'
                : 'Terakhir ${point.status.label}. Kondisi sekarang tidak '
                      'diketahui, jangan anggap sudah aman.',
          ),
      for (final entry in ews.log)
        LogEntry(
          time: shortTime(entry.time),
          title:
              '${_deviceName(ews, entry.area)} berubah menjadi '
              '${entry.status ?? 'Tidak ada data'}',
          status: entry.statusKind,
          note: entry.note,
        ),
    ],
  );
}

String _deviceName(EwsData ews, String serverName) {
  for (final area in ews.areas) {
    if (area.name == serverName) return deviceOfArea(area)?.id ?? serverName;
  }
  return serverName;
}

String _summary(SensorPoint worst, List<SensorPoint> connected) {
  final area = worst.area!;
  final since = area.time == null ? '' : ' sejak ${shortTime(area.time!)}';
  final name = '${worst.id} ${worst.place}';
  return switch (worst.status) {
    MonitoringStatus.normal =>
      connected.length == 1
          ? 'Semua sensor $name normal.'
          : 'Semua alat mengirim bacaan normal.',
    MonitoringStatus.noData =>
      '$name tidak mengirim data$since. Kondisi sekarang belum diketahui.',
    MonitoringStatus.waspada || MonitoringStatus.awas =>
      '$name: ${area.trigger ?? worst.status.label}.'
          '${area.offline ? ' Alat tidak mengirim data$since, jangan anggap sudah aman.' : ''}',
  };
}
