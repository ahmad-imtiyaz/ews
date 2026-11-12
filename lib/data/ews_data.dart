import 'monitoring.dart';

// Bentuk data dari `GET /api/ews/data` di server Laravel EWS. Lihat
// ews_flutter.md untuk arti tiap field.

/// Status dari server: "Aman", "Waspada", "Awas", atau `null` bila belum ada
/// data. Awas hanya bisa datang dari server (kabel EWS putus atau persetujuan
/// admin), jadi status wilayah tidak pernah dihitung di aplikasi.
MonitoringStatus statusFromServer(String? status) => switch (status) {
  'Aman' => MonitoringStatus.normal,
  'Waspada' => MonitoringStatus.waspada,
  'Awas' => MonitoringStatus.awas,
  _ => MonitoringStatus.noData,
};

class EwsThreshold {
  const EwsThreshold(this.waspada, this.validasi);

  final double waspada;
  final double validasi;

  factory EwsThreshold.fromJson(Map<String, dynamic> json) => EwsThreshold(
    (json['waspada'] as num).toDouble(),
    (json['validasi'] as num).toDouble(),
  );
}

enum SensorLevel { normal, waspada, lewatBatas, notRated }

class EwsSensor {
  const EwsSensor({
    required this.key,
    required this.name,
    required this.icon,
    required this.value,
    required this.text,
    required this.level,
    required this.word,
  });

  /// kelembapan_tanah, intensitas_hujan, kemiringan, atau kelembapan_udara.
  final String key;
  final String name;

  /// tanah, hujan, miring, atau udara.
  final String icon;

  /// `null` bila sensor tidak mengirim.
  final double? value;

  /// Sudah berformat koma dan satuan dari server, mis. "9,9°".
  final String text;
  final SensorLevel level;

  /// "Normal", "Waspada", "Lewat batas", "Hanya informasi", "Tidak ada data".
  final String word;

  String get unit => key == 'kemiringan' ? '°' : '%';

  factory EwsSensor.fromJson(String key, Map<String, dynamic> json) =>
      EwsSensor(
        key: key,
        name: json['nama'] as String,
        icon: json['ikon'] as String? ?? '',
        // Server bisa mengirim 30 (int) atau 30.5 (double).
        value: (json['nilai'] as num?)?.toDouble(),
        text: json['teks'] as String? ?? '-',
        level: switch (json['level']) {
          0 => SensorLevel.normal,
          1 => SensorLevel.waspada,
          2 => SensorLevel.lewatBatas,
          _ => SensorLevel.notRated,
        },
        word: json['kata'] as String? ?? 'Tidak ada data',
      );
}

class EwsArea {
  const EwsArea({
    required this.id,
    required this.name,
    required this.status,
    required this.trigger,
    required this.time,
    required this.offline,
    required this.sensors,
    this.unknownCondition = false,
  });

  final int id;
  final String name;
  final String? status;
  final String? trigger;

  /// Kapan alat terakhir mengirim, `d-m-Y H:i` WIB.
  final String? time;

  /// Alat tidak mengirim selama 15 menit atau lebih.
  final bool offline;

  /// Server menganggap kondisi lereng sekarang tidak diketahui, mis. alat
  /// berhenti mengirim saat Waspada.
  final bool unknownCondition;
  final List<EwsSensor> sensors;

  MonitoringStatus get statusKind => statusFromServer(status);

  factory EwsArea.fromJson(Map<String, dynamic> json) => EwsArea(
    id: json['id'] as int,
    name: json['nama'] as String,
    status: json['status'] as String?,
    trigger: json['pemicu'] as String?,
    time: json['waktu'] as String?,
    offline: json['offline'] as bool? ?? false,
    unknownCondition: json['kondisi_tak_diketahui'] as bool? ?? false,
    // Urutan kunci dari server sama dengan urutan kartu di web.
    sensors: [
      for (final MapEntry(:key, :value)
          in (json['sensor'] as Map<String, dynamic>? ?? const {}).entries)
        EwsSensor.fromJson(key, value as Map<String, dynamic>),
    ],
  );
}

/// Kondisi terburuk dari semua wilayah.
class EwsSummary {
  const EwsSummary({
    required this.status,
    required this.location,
    required this.trigger,
    required this.time,
    required this.advice,
  });

  final String? status;
  final String? location;
  final String? trigger;
  final String? time;
  final String advice;

  MonitoringStatus get statusKind => statusFromServer(status);

  factory EwsSummary.fromJson(Map<String, dynamic> json) => EwsSummary(
    status: json['status'] as String?,
    location: json['lokasi'] as String?,
    trigger: json['pemicu'] as String?,
    time: json['waktu'] as String?,
    advice: json['saran'] as String? ?? '',
  );
}

class EwsLogEntry {
  const EwsLogEntry({
    required this.time,
    required this.area,
    required this.status,
    required this.note,
  });

  final String time;
  final String area;
  final String? status;
  final String note;

  MonitoringStatus get statusKind => statusFromServer(status);

  factory EwsLogEntry.fromJson(Map<String, dynamic> json) => EwsLogEntry(
    time: json['waktu'] as String? ?? '',
    area: json['wilayah'] as String? ?? '',
    status: json['status'] as String?,
    note: json['keterangan'] as String? ?? '',
  );
}

class EwsData {
  const EwsData({
    required this.summary,
    required this.areas,
    required this.log,
    required this.thresholds,
    this.offlineNotices = const [],
  });

  final EwsSummary summary;
  final List<EwsArea> areas;

  /// Kalimat dari server untuk tiap alat yang berhenti mengirim, mis. "Alat
  /// di Titik Area 2 berhenti mengirim data ... jangan anggap sudah aman."
  final List<String> offlineNotices;

  /// 10 perubahan status terakhir, terbaru di atas.
  final List<EwsLogEntry> log;

  /// Ambang yang diatur admin. Kelembapan udara memang tidak punya ambang.
  final Map<String, EwsThreshold> thresholds;

  factory EwsData.fromJson(Map<String, dynamic> json) => EwsData(
    summary: EwsSummary.fromJson(json['utama'] as Map<String, dynamic>),
    areas: [
      for (final area in json['wilayah'] as List? ?? const [])
        EwsArea.fromJson(area as Map<String, dynamic>),
    ],
    offlineNotices: [
      for (final item in json['offline'] as List? ?? const [])
        if ((item as Map)['teks'] case final String text when text.isNotEmpty)
          text,
    ],
    log: [
      for (final entry in json['log'] as List? ?? const [])
        EwsLogEntry.fromJson(entry as Map<String, dynamic>),
    ],
    thresholds: {
      for (final MapEntry(:key, :value)
          in (json['ambang'] as Map<String, dynamic>? ?? const {}).entries)
        key: EwsThreshold.fromJson(value as Map<String, dynamic>),
    },
  );
}

/// 24.0 jadi "24", 12.35 jadi "12,35".
String formatNumber(double value) => value
    .toStringAsFixed(2)
    .replaceFirst(RegExp(r'\.?0+$'), '')
    .replaceAll('.', ',');

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'Mei',
  'Jun',
  'Jul',
  'Agu',
  'Sep',
  'Okt',
  'Nov',
  'Des',
];

/// "06-11-2026 18:44" dari server jadi "18.44" bila hari ini, selain itu
/// "6 Nov, 18.44".
String shortTime(String raw, {DateTime? now}) {
  final match = RegExp(
    r'^(\d{1,2})-(\d{1,2})-(\d{4}) (\d{1,2}):(\d{2})',
  ).firstMatch(raw);
  if (match == null) return raw;
  final day = int.parse(match[1]!);
  final month = int.parse(match[2]!);
  final year = int.parse(match[3]!);
  if (month < 1 || month > 12) return raw;

  final clock = '${match[4]!.padLeft(2, '0')}.${match[5]}';
  final today = now ?? DateTime.now();
  if (day == today.day && month == today.month && year == today.year) {
    return clock;
  }
  return '$day ${_months[month - 1]}, $clock';
}
