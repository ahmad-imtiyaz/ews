import 'package:latlong2/latlong.dart';

// Semua isi berkas ini data simulasi. Pusat peta memakai posisi Desa Lumeneng
// dari OpenStreetMap. Dua alat EWS yang akan dipasang belum terhubung dan
// lokasinya belum pasti. Titik contohnya di Kaliwisnu (paling sering longsor
// menurut Kajian Pemetaan Bencana Desa Lumeneng 2024) dan Sikembang (di sebelah
// satu-satunya zona sangat rawan di kajian itu), laporan di Jomparang. Posisinya
// dibaca dari grid Peta Rawan Longsor kajian, meleset sampai ±100 m. Area pantau
// tiap alat ada di assets/peta/area_ews.geojson.

enum MonitoringStatus {
  normal('Normal'),
  waspada('Waspada'),
  awas('Awas'),
  noData('Tidak ada data');

  const MonitoringStatus(this.label);

  final String label;
}

class SensorReading {
  const SensorReading(this.name, this.value);

  final String name;
  final String value;
}

class SensorPoint {
  const SensorPoint({
    required this.id,
    required this.place,
    required this.position,
    required this.status,
    required this.lastData,
    this.readings = sampleReadings,
  });

  final String id;
  final String place;
  final LatLng position;
  final MonitoringStatus status;
  final String lastData;
  final List<SensorReading> readings;

  bool get isStale => status == MonitoringStatus.noData;
}

class ReportPoint {
  const ReportPoint({
    required this.title,
    required this.place,
    required this.position,
    required this.time,
  });

  final String title;
  final String place;
  final LatLng position;
  final String time;
}

enum LogKind { status, report, noData, verified }

class LogEntry {
  const LogEntry(this.time, this.text, this.kind);

  final String time;
  final String text;
  final LogKind kind;
}

class MonitoringData {
  const MonitoringData({
    required this.name,
    required this.status,
    required this.title,
    required this.summary,
    this.updated,
    this.sensors = const [],
    this.reports = const [],
    this.log = const [],
    this.loadFailed = false,
  });

  final String name;
  final MonitoringStatus status;
  final String title;
  final String summary;
  final String? updated;
  final List<SensorPoint> sensors;
  final List<ReportPoint> reports;
  final List<LogEntry> log;
  final bool loadFailed;
}

const _ews01Position = LatLng(-7.1899, 109.5911);
const _ews02Position = LatLng(-7.1854, 109.5927);
const _reportPosition = LatLng(-7.1866, 109.5893);

/// Titik yang harus terlihat saat peta pertama dibuka.
const mapFocusPoints = [_ews01Position, _ews02Position, _reportPosition];

const sampleReadings = [
  SensorReading('Kelembapan tanah', '78 %'),
  SensorReading('Kelembapan udara', '91 %'),
  SensorReading('pH tanah', '5,8'),
  SensorReading('Sensor utama', 'Jenis sensor belum ditentukan'),
];

const waspadaData = MonitoringData(
  name: 'Waspada',
  status: MonitoringStatus.waspada,
  title: 'Waspada',
  summary: '1 titik perlu diperhatikan. 1 titik tidak mengirim data.',
  updated: 'Diperbarui 10.42',
  sensors: [
    SensorPoint(
      id: 'EWS-01',
      place: 'Kaliwisnu',
      position: _ews01Position,
      status: MonitoringStatus.waspada,
      lastData: '10.42',
    ),
    SensorPoint(
      id: 'EWS-02',
      place: 'Sikembang',
      position: _ews02Position,
      status: MonitoringStatus.noData,
      lastData: '07.15',
    ),
  ],
  reports: [
    ReportPoint(
      title: 'Laporan retakan',
      place: 'Jomparang',
      position: _reportPosition,
      time: '10.39',
    ),
  ],
  log: [
    LogEntry('10.42', 'EWS-01 berubah menjadi Waspada', LogKind.status),
    LogEntry(
      '10.39',
      'Laporan retakan masuk, menunggu verifikasi',
      LogKind.report,
    ),
    LogEntry('10.35', 'EWS-02 tidak mengirim data', LogKind.noData),
    LogEntry(
      '10.20',
      'Petugas memverifikasi laporan di Kaliwisnu',
      LogKind.verified,
    ),
  ],
);

const normalData = MonitoringData(
  name: 'Normal, catatan kosong',
  status: MonitoringStatus.normal,
  title: 'Normal',
  summary: '2 titik mengirim data terbaru.',
  updated: 'Diperbarui 10.42',
  sensors: [
    SensorPoint(
      id: 'EWS-01',
      place: 'Kaliwisnu',
      position: _ews01Position,
      status: MonitoringStatus.normal,
      lastData: '10.42',
    ),
    SensorPoint(
      id: 'EWS-02',
      place: 'Sikembang',
      position: _ews02Position,
      status: MonitoringStatus.normal,
      lastData: '10.41',
    ),
  ],
);

const awasData = MonitoringData(
  name: 'Awas',
  status: MonitoringStatus.awas,
  title: 'Awas',
  summary: 'EWS-01 berstatus Awas. Ikuti arahan petugas desa.',
  updated: 'Diperbarui 10.42',
  sensors: [
    SensorPoint(
      id: 'EWS-01',
      place: 'Kaliwisnu',
      position: _ews01Position,
      status: MonitoringStatus.awas,
      lastData: '10.42',
    ),
    SensorPoint(
      id: 'EWS-02',
      place: 'Sikembang',
      position: _ews02Position,
      status: MonitoringStatus.waspada,
      lastData: '10.41',
    ),
  ],
  log: [
    LogEntry('10.42', 'EWS-01 berubah menjadi Awas', LogKind.status),
    LogEntry('10.41', 'EWS-02 berubah menjadi Waspada', LogKind.status),
  ],
);

const noDataData = MonitoringData(
  name: 'Tidak ada data baru',
  status: MonitoringStatus.noData,
  title: 'Tidak ada data baru',
  summary: 'Kondisi sekarang belum diketahui. Data terakhir 07.15.',
  sensors: [
    SensorPoint(
      id: 'EWS-01',
      place: 'Kaliwisnu',
      position: _ews01Position,
      status: MonitoringStatus.noData,
      lastData: '07.15',
    ),
    SensorPoint(
      id: 'EWS-02',
      place: 'Sikembang',
      position: _ews02Position,
      status: MonitoringStatus.noData,
      lastData: '07.15',
    ),
  ],
  log: [
    LogEntry('07.15', 'Semua titik berhenti mengirim data', LogKind.noData),
  ],
);

const failedData = MonitoringData(
  name: 'Gagal memuat data',
  status: MonitoringStatus.noData,
  title: 'Belum bisa memuat',
  summary: 'Kondisi sekarang belum diketahui. Periksa sinyal, lalu coba lagi.',
  loadFailed: true,
);

const sampleScenarios = [
  waspadaData,
  normalData,
  awasData,
  noDataData,
  failedData,
];

Future<MonitoringData> loadMonitoring() async => waspadaData;
