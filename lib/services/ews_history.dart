import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import '../data/ews_data.dart';

/// Empat sensor alat EWS, urutannya sama dengan kartu di menu Sensor.
const ewsSensorKeys = [
  'kelembapan_tanah',
  'intensitas_hujan',
  'kemiringan',
  'kelembapan_udara',
];

class PastReading {
  const PastReading({
    required this.key,
    required this.name,
    required this.unit,
    required this.value,
    required this.threshold,
  });

  final String key;
  final String name;
  final String unit;

  /// `null` bila alat tidak mengirim sensor ini saat itu.
  final double? value;

  /// `null` untuk kelembapan udara, yang tidak ikut menentukan status.
  final EwsThreshold? threshold;

  /// Kemiringan dinilai dari nilai mutlaknya, sama dengan server.
  double? get judged => key == 'kemiringan' ? value?.abs() : value;

  SensorLevel get level {
    final judged = this.judged;
    final threshold = this.threshold;
    if (judged == null || threshold == null) return SensorLevel.notRated;
    if (judged >= threshold.validasi) return SensorLevel.lewatBatas;
    if (judged >= threshold.waspada) return SensorLevel.waspada;
    return SensorLevel.normal;
  }

  String get text =>
      value == null ? 'Tidak ada data' : '${formatNumber(value!)}$unit';
}

/// Bacaan sensor dalam satu blok waktu dari `GET /api/ews/grafik`.
class PastReadings {
  const PastReadings({
    required this.from,
    required this.step,
    required this.readings,
  });

  final DateTime from;

  /// 1 menit, 10 menit, atau 1 jam, tergantung seberapa lama kejadiannya.
  final Duration step;
  final List<PastReading> readings;
}

/// Server hanya menyimpan grafik sampai 7 hari ke belakang.
class TooOldForHistory implements Exception {
  const TooOldForHistory();
}

/// Bacaan keempat sensor pada blok waktu yang memuat [at]. Server mengirim
/// nilai tertinggi tiap blok, jadi makin lama kejadiannya makin kasar
/// bloknya.
///
/// Jam dari server (WIB) dibaca sebagai jam HP, sama dengan bagian lain
/// aplikasi, karena semua HP warga memakai WIB.
Future<PastReadings> fetchReadingsAt(
  DateTime at, {
  http.Client? client,
  String baseUrl = ewsBaseUrl,
  int areaId = 1,
}) async {
  final age = clock.now().difference(at);
  final (range, step) = switch (age) {
    < const Duration(minutes: 55) => ('1j', const Duration(minutes: 1)),
    < const Duration(hours: 23, minutes: 50) => (
      '24j',
      const Duration(minutes: 10),
    ),
    < const Duration(days: 6, hours: 23) => ('7h', const Duration(hours: 1)),
    _ => throw const TooOldForHistory(),
  };

  // Blok server dimulai di kelipatan langkahnya, mis. 17.40 untuk 17.43.
  final ms = at.millisecondsSinceEpoch;
  final from = DateTime.fromMillisecondsSinceEpoch(
    ms - ms % step.inMilliseconds,
  );

  final api = client ?? http.Client();
  try {
    return PastReadings(
      from: from,
      step: step,
      readings: await Future.wait([
        for (final key in ewsSensorKeys)
          _fetchOne(api, baseUrl, areaId, key, range, from),
      ]),
    );
  } finally {
    if (client == null) api.close();
  }
}

Future<PastReading> _fetchOne(
  http.Client client,
  String baseUrl,
  int areaId,
  String key,
  String range,
  DateTime from,
) async {
  final response = await client
      .get(
        Uri.parse('$baseUrl/api/ews/grafik').replace(
          queryParameters: {
            'wilayah': '$areaId',
            'sensor': key,
            'rentang': range,
          },
        ),
        headers: {'Accept': 'application/json'},
      )
      .timeout(const Duration(seconds: 15));
  if (response.statusCode != 200) {
    throw http.ClientException(
      'Server membalas kode ${response.statusCode}',
      response.request?.url,
    );
  }

  final json =
      jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  final threshold = json['ambang'];
  // Blok tanpa kiriman tidak ada di daftar, atau ada dengan nilai null.
  final point = [
    for (final point in json['titik'] as List? ?? const [])
      point as Map<String, dynamic>,
  ].where((point) => point['t'] == from.millisecondsSinceEpoch).firstOrNull;

  return PastReading(
    key: key,
    name: json['sensor'] as String? ?? key,
    unit: json['satuan'] as String? ?? '',
    value: (point?['y'] as num?)?.toDouble(),
    threshold: threshold is Map<String, dynamic>
        ? EwsThreshold.fromJson(threshold)
        : null,
  );
}
