import 'dart:math';

import 'ews_data.dart';

/// Data contoh untuk menu Sensor selama alat EWS belum terpasang. Tiap kali
/// diambil, angkanya bergeser sedikit dari nilai sebelumnya dan tertarik
/// kembali ke nilai tengah, jadi naik turun tipis tanpa melompat. Rentangnya
/// di bawah batas waspada, karena contoh tidak boleh terlihat seperti
/// peringatan.
class EwsSampleFeed {
  EwsSampleFeed({Random? random}) : _random = random ?? Random();

  final Random _random;

  // Samakan dengan ambang di ews_flutter.md.
  static const thresholds = {
    'kelembapan_tanah': EwsThreshold(50, 80),
    'intensitas_hujan': EwsThreshold(40, 70),
    'kemiringan': EwsThreshold(15, 20),
  };

  final _soil = _Drift(center: 34, noise: 0.6, min: 28, max: 42);
  final _rain = _Drift(center: 12, noise: 1.5, min: 0, max: 30);
  final _tilt = _Drift(center: 2, noise: 0.2, min: -5, max: 5);
  final _air = _Drift(center: 84, noise: 0.8, min: 70, max: 95);

  Future<EwsData> next() async {
    final sensors = [
      _sensor('kelembapan_tanah', 'Kelembapan tanah', 'tanah', _soil, '%'),
      _sensor('intensitas_hujan', 'Intensitas hujan', 'hujan', _rain, '%'),
      _sensor('kemiringan', 'Kemiringan', 'miring', _tilt, '°'),
      _sensor('kelembapan_udara', 'Kelembapan udara', 'udara', _air, '%'),
    ];
    final triggered = [
      for (final s in sensors)
        if (s.level == SensorLevel.waspada || s.level == SensorLevel.lewatBatas)
          '${s.name} ${s.text}',
    ].join(', ');
    final alert = triggered.isNotEmpty;
    final status = alert ? 'Waspada' : 'Aman';
    final time = _stamp(DateTime.now());
    const place = 'Lereng Kebun Kopi';

    return EwsData(
      sample: true,
      summary: EwsSummary(
        status: status,
        location: place,
        trigger: alert ? triggered : 'Semua sensor normal',
        time: time,
        advice: alert
            ? 'Siapkan tas siaga dan pantau terus halaman ini.'
            : 'Semua sensor normal. Tetap pantau halaman ini saat hujan.',
      ),
      areas: [
        EwsArea(
          id: 1,
          name: place,
          status: status,
          trigger: alert ? triggered : null,
          time: time,
          offline: false,
          sensors: sensors,
        ),
      ],
      // Riwayat sengaja kosong: perubahan status karangan tidak ditampilkan.
      log: const [],
      thresholds: thresholds,
    );
  }

  EwsSensor _sensor(
    String key,
    String name,
    String icon,
    _Drift drift,
    String unit,
  ) {
    final value = drift.step(_random);
    final level = _level(key, value);
    return EwsSensor(
      key: key,
      name: name,
      icon: icon,
      value: value,
      text: '${formatNumber(value)}$unit',
      level: level,
      word: switch (level) {
        SensorLevel.normal => 'Normal',
        SensorLevel.waspada => 'Waspada',
        SensorLevel.lewatBatas => 'Lewat batas',
        SensorLevel.notRated => 'Hanya informasi',
      },
    );
  }

  // Aturan yang sama dengan server: kemiringan dinilai dari nilai mutlaknya.
  static SensorLevel _level(String key, double value) {
    final threshold = thresholds[key];
    if (threshold == null) return SensorLevel.notRated;
    final v = key == 'kemiringan' ? value.abs() : value;
    if (v >= threshold.validasi) return SensorLevel.lewatBatas;
    if (v >= threshold.waspada) return SensorLevel.waspada;
    return SensorLevel.normal;
  }

  static String _stamp(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.day)}-${two(t.month)}-${t.year} '
        '${two(t.hour)}:${two(t.minute)}';
  }
}

class _Drift {
  _Drift({
    required this.center,
    required this.noise,
    required this.min,
    required this.max,
  }) : _value = center;

  final double center;
  final double noise;
  final double min;
  final double max;
  double _value;

  double step(Random random) {
    final pull = (center - _value) * 0.1;
    final jitter = (random.nextDouble() * 2 - 1) * noise;
    final next = (_value + pull + jitter).clamp(min, max);
    return _value = (next * 10).roundToDouble() / 10;
  }
}
