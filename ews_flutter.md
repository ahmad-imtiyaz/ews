# Menghubungkan aplikasi Flutter ke data sensor EWS

Dokumen ini untuk yang membuat aplikasi Flutter. Isinya: alamat untuk mengambil data, arti setiap
field, aturan ambang (threshold) supaya Flutter bisa memberi label Normal/Waspada sendiri, dan contoh
kode Dart yang bisa langsung disalin.

Ringkasnya: Flutter **tidak** membaca alat ESP32 secara langsung. Alur datanya:

```
ESP32 ──POST /api/sensor──▶ Server Laravel (simpan + nilai status) ──GET /api/ews/data──▶ Flutter
```

Flutter cukup memanggil `GET /api/ews/data` tiap 10 detik. Endpoint ini publik (tanpa login, tanpa kunci).

> Jangan pernah memasang `EWS_API_KEY` di aplikasi Flutter. Kunci itu hanya untuk alat. Aplikasi HP
> bisa dibongkar dan kuncinya dicuri, lalu orang bisa mengirim data palsu.

---

## 1. Alamat yang dipakai Flutter

| Fungsi | Metode | Alamat | Kunci? |
|---|---|---|---|
| Data terbaru semua wilayah + 4 sensor + ambang | `GET` | `/api/ews/data` | tidak |
| Data grafik satu sensor | `GET` | `/api/ews/grafik?wilayah=1&sensor=kelembapan_tanah&rentang=24j` | tidak |
| ~~Kirim data sensor~~ / ~~tes koneksi~~ | `POST /api/sensor`, `GET /api/ping` | | khusus alat, **bukan untuk Flutter** |

Alamat dasar (`BASE_URL`) saat uji coba:

| Flutter dijalankan di | `BASE_URL` | Catatan |
|---|---|---|
| Emulator Android | `http://10.0.2.2:8000` | `10.0.2.2` = laptop Anda dilihat dari emulator |
| HP sungguhan (satu WiFi dengan laptop) | `http://192.168.x.x:8000` | Jalankan server dengan `php artisan serve --host=0.0.0.0`, lalu cek IP laptop dengan `ipconfig` |
| Flutter web / Windows desktop | `http://127.0.0.1:8000` | |
| Produksi | `https://DOMAIN-DESA` | wajib https |

Android menolak `http://` (tanpa s) secara bawaan. Untuk uji coba lokal saja, tambahkan
`android:usesCleartextTraffic="true"` di tag `<application>` pada `android/app/src/main/AndroidManifest.xml`.
Hapus lagi saat rilis karena server produksi memakai https.

---

## 2. Isi `GET /api/ews/data`

Contoh asli dari server lokal (dipotong; `wilayah` bisa berisi lebih dari satu):

```json
{
  "utama": {
    "status": "Aman", "warna": "hijau", "lokasi": "Lereng Kebun Kopi",
    "pemicu": "Semua sensor normal", "waktu": "06-11-2026 18:44",
    "saran": "Semua sensor normal. Tetap pantau halaman ini saat hujan."
  },
  "wilayah": [
    {
      "id": 1,
      "nama": "Lereng Kebun Kopi",
      "poligon": [[-7.1685, 109.5485], [-7.1685, 109.5515], [-7.1705, 109.552]],
      "status": "Aman", "warna": "hijau", "pemicu": null,
      "waktu": "06-11-2026 18:44",
      "offline": true,
      "sensor": {
        "kelembapan_tanah": { "nama": "Kelembapan tanah", "ikon": "tanah",  "nilai": 30, "teks": "30%", "level": 0,    "kata": "Normal",          "warna": "hijau" },
        "intensitas_hujan": { "nama": "Intensitas hujan", "ikon": "hujan",  "nilai": 20, "teks": "20%", "level": 0,    "kata": "Normal",          "warna": "hijau" },
        "kemiringan":       { "nama": "Kemiringan",       "ikon": "miring", "nilai": 10, "teks": "10°", "level": 0,    "kata": "Normal",          "warna": "hijau" },
        "kelembapan_udara": { "nama": "Kelembapan udara", "ikon": "udara",  "nilai": 40, "teks": "40%", "level": null, "kata": "Hanya informasi", "warna": "kosong" }
      }
    }
  ],
  "offline": [ { "nama": "Lereng Kebun Kopi", "waktu": "06-11-2026 18:44" } ],
  "log": [
    { "waktu": "06-11-2026 18:14", "wilayah": "Lereng Kebun Kopi", "status": "Waspada", "warna": "kuning", "keterangan": "Kemiringan 20°" }
  ],
  "ambang": {
    "kelembapan_tanah": { "waspada": 50, "validasi": 80 },
    "intensitas_hujan": { "waspada": 40, "validasi": 70 },
    "kemiringan":       { "waspada": 15, "validasi": 20 }
  }
}
```

### 2.1 Bagian `utama` (kotak status besar di atas)

Kondisi **terburuk** dari semua wilayah.

| Field | Tipe | Arti |
|---|---|---|
| `status` | `"Aman"` / `"Waspada"` / `"Awas"` / `null` | `null` = belum ada data sama sekali |
| `warna` | `"hijau"` / `"kuning"` / `"merah"` / `"kosong"` | |
| `lokasi` | teks / `null` | wilayah dengan kondisi terburuk |
| `pemicu` | teks / `null` | penyebab, mis. `"Intensitas hujan 80%, Kemiringan 21°"` |
| `waktu` | teks `d-m-Y H:i` (WIB) / `null` | waktu bacaan terakhir |
| `saran` | teks | saran untuk warga sesuai warna |

### 2.2 Bagian `wilayah[]` (satu per lokasi alat)

| Field | Tipe | Arti |
|---|---|---|
| `id` | angka | ID wilayah (dipakai untuk endpoint grafik) |
| `nama` | teks | mis. `"Lereng Kebun Kopi"` |
| `poligon` | daftar `[lintang, bujur]` | batas wilayah untuk peta (`flutter_map`) |
| `status`, `warna`, `pemicu` | seperti `utama` | status wilayah ini |
| `waktu` | teks / `null` | kapan alat terakhir mengirim |
| `offline` | `true`/`false` | `true` = alat tidak mengirim ≥ 15 menit. Tampilkan "Alat tidak mengirim data" |
| `sensor` | objek | 4 sensor, lihat 2.3 |

### 2.3 Bagian `sensor` (4 kartu sensor)

Kuncinya selalu empat ini, urutannya sama dengan di web:

| Kunci | Nama | Satuan | Rentang nilai | Ikut menentukan status? |
|---|---|---|---|---|
| `kelembapan_tanah` | Kelembapan tanah | `%` | 0 – 100 | ya |
| `intensitas_hujan` | Intensitas hujan | `%` | 0 – 100 (0 = papan sensor kering, 100 = basah kuyup) | ya |
| `kemiringan` | Kemiringan | `°` | −90 – 90 (dinilai dari nilai **mutlak**: −12° sama dengan 12°) | ya |
| `kelembapan_udara` | Kelembapan udara | `%` | 0 – 100 | **tidak**, hanya informasi |

Isi tiap sensor:

| Field | Tipe | Arti |
|---|---|---|
| `nama` | teks | judul kartu |
| `ikon` | `tanah` / `hujan` / `miring` / `udara` | nama ikon (pilih ikon Flutter sendiri, lihat bagian 5) |
| `nilai` | angka / `null` | angka mentah. `null` = sensor tidak mengirim. **Bisa datang sebagai `30` (bilangan bulat) atau `30.5`**, jadi di Dart selalu baca sebagai `num` lalu `.toDouble()` |
| `teks` | teks | angka siap tampil, sudah pakai koma dan satuan: `"9,9°"`, `"30%"` |
| `level` | `0` / `1` / `2` / `null` | 0 = Normal, 1 = Waspada, 2 = Lewat batas, `null` = tidak dinilai/tidak ada data |
| `kata` | teks | `"Normal"`, `"Waspada"`, `"Lewat batas"`, `"Hanya informasi"`, `"Tidak ada data"` |
| `warna` | `hijau` / `kuning` / `kosong` | warna label |

Server **sudah** menghitung `level`, `kata`, dan `warna`. Kalau Flutter ingin menghitung sendiri dengan ambang
miliknya, ikuti bagian 3.

### 2.4 Bagian `offline`, `log`, `ambang`

- `offline[]`: daftar wilayah yang alatnya diam ≥ 15 menit (`nama`, `waktu`).
- `log[]`: 10 **perubahan** status terakhir (bukan tiap kiriman): `waktu`, `wilayah`, `status`, `warna`, `keterangan`.
- `ambang`: batas yang sedang berlaku di server (diatur admin di Admin → Ambang batas sensor).
  Hanya 3 sensor; `kelembapan_udara` memang tidak punya ambang.

---

## 3. Ambang (threshold) di Flutter

Aturannya sama persis dengan server (`app/Services/Ews/PenilaianStatus.php`):

| Kondisi | Level | Kata | Warna |
|---|---|---|---|
| `nilai` kosong (`null`) | – | Tidak ada data | abu-abu |
| sensor tanpa ambang (kelembapan udara) | – | Hanya informasi | abu-abu |
| nilai < `waspada` | 0 | Normal | hijau |
| `waspada` ≤ nilai < `validasi` | 1 | Waspada | kuning |
| nilai ≥ `validasi` | 2 | Lewat batas | kuning (status wilayah tetap Waspada, admin diminta memeriksa) |

Untuk `kemiringan`, bandingkan **nilai mutlaknya** (`nilai.abs()`).

Angka ambang saat ini di server lokal:

| Sensor | Waspada | Validasi |
|---|---|---|
| Kelembapan tanah | 50 % | 80 % |
| Intensitas hujan | 40 % | 70 % (sementara, belum dikalibrasi) |
| Kemiringan | 15° | 20° (sementara, belum dikalibrasi) |

Saran: jadikan angka di Flutter sebagai **cadangan** saja, dan pakai `ambang` dari JSON bila ada.
Dengan begitu, saat admin mengubah ambang di web, aplikasi ikut berubah tanpa perlu rilis ulang.

### Penting: status wilayah (Aman/Waspada/Awas) ambil dari server

Flutter boleh menghitung label tiap **sensor**. Tetapi status **wilayah**, terutama **Awas**, harus diambil
dari field `status` server, karena Awas hanya muncul dari kabel EWS putus atau persetujuan admin.
Flutter tidak punya informasi itu, jadi tidak bisa menghitungnya sendiri.

---

## 4. Contoh kode Dart

### 4.1 Pasang paket

Di folder proyek Flutter:

1. `flutter pub add http` → menambah paket untuk memanggil alamat web.
2. `flutter pub get` → mengunduh paketnya. Seharusnya selesai tanpa pesan merah.

### 4.2 Model data (`lib/ews/model_ews.dart`)

```dart
class Ambang {
  const Ambang(this.waspada, this.validasi);
  final double waspada;
  final double validasi;

  factory Ambang.fromJson(Map<String, dynamic> j) =>
      Ambang((j['waspada'] as num).toDouble(), (j['validasi'] as num).toDouble());
}

class SensorEws {
  SensorEws({
    required this.kunci,
    required this.nama,
    required this.ikon,
    required this.nilai,
    required this.teks,
    required this.level,
    required this.kata,
    required this.warna,
  });

  final String kunci; // kelembapan_tanah, intensitas_hujan, kemiringan, kelembapan_udara
  final String nama;
  final String ikon;
  final double? nilai;
  final String teks;
  final int? level;
  final String kata;
  final String warna;

  factory SensorEws.fromJson(String kunci, Map<String, dynamic> j) => SensorEws(
        kunci: kunci,
        nama: j['nama'] as String,
        ikon: j['ikon'] as String,
        // Server bisa mengirim 30 (int) atau 30.5 (double).
        nilai: (j['nilai'] as num?)?.toDouble(),
        teks: j['teks'] as String,
        level: j['level'] as int?,
        kata: j['kata'] as String,
        warna: j['warna'] as String,
      );
}

class WilayahEws {
  WilayahEws({
    required this.id,
    required this.nama,
    required this.poligon,
    required this.status,
    required this.warna,
    required this.pemicu,
    required this.waktu,
    required this.offline,
    required this.sensor,
  });

  final int id;
  final String nama;
  final List<List<double>> poligon; // [lintang, bujur]
  final String? status;
  final String warna;
  final String? pemicu;
  final String? waktu;
  final bool offline;
  final List<SensorEws> sensor;

  factory WilayahEws.fromJson(Map<String, dynamic> j) => WilayahEws(
        id: j['id'] as int,
        nama: j['nama'] as String,
        poligon: (j['poligon'] as List? ?? [])
            .map((t) => (t as List).map((n) => (n as num).toDouble()).toList())
            .toList(),
        status: j['status'] as String?,
        warna: j['warna'] as String,
        pemicu: j['pemicu'] as String?,
        waktu: j['waktu'] as String?,
        offline: j['offline'] as bool? ?? false,
        sensor: (j['sensor'] as Map<String, dynamic>)
            .entries
            .map((e) => SensorEws.fromJson(e.key, e.value as Map<String, dynamic>))
            .toList(),
      );
}

class DataEws {
  DataEws({required this.utama, required this.wilayah, required this.log, required this.ambang});

  final Map<String, dynamic> utama;
  final List<WilayahEws> wilayah;
  final List<Map<String, dynamic>> log;
  final Map<String, Ambang> ambang;

  factory DataEws.fromJson(Map<String, dynamic> j) => DataEws(
        utama: j['utama'] as Map<String, dynamic>,
        wilayah: (j['wilayah'] as List)
            .map((w) => WilayahEws.fromJson(w as Map<String, dynamic>))
            .toList(),
        log: (j['log'] as List).cast<Map<String, dynamic>>(),
        ambang: (j['ambang'] as Map<String, dynamic>)
            .map((k, v) => MapEntry(k, Ambang.fromJson(v as Map<String, dynamic>))),
      );
}
```

### 4.3 Ambang di Flutter (`lib/ews/ambang_ews.dart`)

```dart
import 'model_ews.dart';

enum LevelSensor { kosong, informasi, normal, waspada, lewatBatas }

// Cadangan bila server tidak mengirim `ambang`. Samakan dengan Admin → Ambang batas sensor.
const ambangCadangan = <String, Ambang>{
  'kelembapan_tanah': Ambang(50, 80),
  'intensitas_hujan': Ambang(40, 70),
  'kemiringan': Ambang(15, 20),
  // kelembapan_udara sengaja tidak ada: hanya informasi.
};

LevelSensor hitungLevel(String kunci, double? nilai, Map<String, Ambang> ambang) {
  if (nilai == null) return LevelSensor.kosong;
  final batas = ambang[kunci] ?? ambangCadangan[kunci];
  if (batas == null) return LevelSensor.informasi;

  // Kemiringan miring ke kiri (−) atau kanan (+) sama bahayanya.
  final v = kunci == 'kemiringan' ? nilai.abs() : nilai;
  if (v >= batas.validasi) return LevelSensor.lewatBatas;
  if (v >= batas.waspada) return LevelSensor.waspada;
  return LevelSensor.normal;
}

String kataLevel(LevelSensor lv) => switch (lv) {
      LevelSensor.kosong => 'Tidak ada data',
      LevelSensor.informasi => 'Hanya informasi',
      LevelSensor.normal => 'Normal',
      LevelSensor.waspada => 'Waspada',
      LevelSensor.lewatBatas => 'Lewat batas',
    };

// 24.0 -> "24", 12.35 -> "12,35" (tampilan Indonesia memakai koma).
String angka(double v) {
  var s = v.toStringAsFixed(2);
  s = s.replaceFirst(RegExp(r'\.?0+$'), '');
  return s.replaceAll('.', ',');
}
```

### 4.4 Mengambil data (`lib/ews/api_ews.dart`)

```dart
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'model_ews.dart';

class ApiEws {
  ApiEws(this.baseUrl);

  final String baseUrl; // mis. http://10.0.2.2:8000
  final _client = http.Client();
  String? _etag;
  DataEws? _terakhir;

  Future<DataEws> ambilData() async {
    final res = await _client.get(
      Uri.parse('$baseUrl/api/ews/data'),
      headers: {
        'Accept': 'application/json',
        // Kalau data belum berubah, server membalas 304 tanpa isi: hemat kuota warga.
        if (_etag != null) 'If-None-Match': _etag!,
      },
    ).timeout(const Duration(seconds: 10));

    if (res.statusCode == 304 && _terakhir != null) return _terakhir!;
    if (res.statusCode != 200) {
      throw Exception('Server membalas kode ${res.statusCode}');
    }

    _etag = res.headers['etag'];
    // utf8.decode wajib: tanpa ini simbol "°" berubah jadi huruf aneh.
    final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return _terakhir = DataEws.fromJson(json);
  }

  /// rentang: '1j' (1 jam), '24j' (24 jam), '7h' (7 hari).
  Future<Map<String, dynamic>> ambilGrafik(int wilayahId, String sensor, String rentang) async {
    final uri = Uri.parse('$baseUrl/api/ews/grafik').replace(queryParameters: {
      'wilayah': '$wilayahId',
      'sensor': sensor,
      'rentang': rentang,
    });
    final res = await _client.get(uri, headers: {'Accept': 'application/json'});
    if (res.statusCode != 200) throw Exception('Server membalas kode ${res.statusCode}');
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }
}
```

### 4.5 Tampilan 4 kartu sensor (`lib/ews/kartu_sensor.dart`)

Meniru kartu di halaman web `/ews`: ikon + nama, angka besar, label (warna + ikon + kata).

```dart
import 'package:flutter/material.dart';
import 'ambang_ews.dart';
import 'model_ews.dart';

const _ikonSensor = {
  'tanah': Icons.water_drop_outlined,
  'hujan': Icons.thunderstorm_outlined,
  'miring': Icons.landscape_outlined,
  'udara': Icons.air,
};

class KartuSensor extends StatelessWidget {
  const KartuSensor({super.key, required this.sensor, required this.ambang});

  final SensorEws sensor;
  final Map<String, Ambang> ambang;

  @override
  Widget build(BuildContext context) {
    final lv = hitungLevel(sensor.kunci, sensor.nilai, ambang);
    // Status tidak boleh hanya warna: selalu warna + ikon + kata.
    final (warna, ikon) = switch (lv) {
      LevelSensor.normal => (const Color(0xFF166534), Icons.check_circle),
      LevelSensor.waspada || LevelSensor.lewatBatas => (const Color(0xFFA16207), Icons.warning_amber_rounded),
      LevelSensor.informasi => (const Color(0xFF4B5563), Icons.info_outline),
      LevelSensor.kosong => (const Color(0xFF4B5563), Icons.help_outline),
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(_ikonSensor[sensor.ikon] ?? Icons.sensors),
              const SizedBox(width: 8),
              Flexible(child: Text(sensor.nama, style: const TextStyle(fontWeight: FontWeight.w600))),
            ]),
            const SizedBox(height: 8),
            // `teks` dari server sudah berformat koma + satuan.
            Text(sensor.teks, style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Chip(
              avatar: Icon(ikon, color: Colors.white, size: 20),
              label: Text(kataLevel(lv), style: const TextStyle(color: Colors.white)),
              backgroundColor: warna,
            ),
          ],
        ),
      ),
    );
  }
}
```

### 4.6 Halaman yang memperbarui sendiri tiap 10 detik (`lib/ews/halaman_ews.dart`)

```dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'api_ews.dart';
import 'kartu_sensor.dart';
import 'model_ews.dart';

class HalamanEws extends StatefulWidget {
  const HalamanEws({super.key});

  @override
  State<HalamanEws> createState() => _HalamanEwsState();
}

class _HalamanEwsState extends State<HalamanEws> {
  final api = ApiEws('http://10.0.2.2:8000'); // ganti sesuai tabel di bagian 1
  DataEws? data;
  String? galat;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _muat();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _muat());
  }

  Future<void> _muat() async {
    try {
      final baru = await api.ambilData();
      if (mounted) setState(() { data = baru; galat = null; });
    } catch (_) {
      // Data lama tetap ditampilkan; cukup beri tahu bahwa sedang tidak tersambung.
      if (mounted) setState(() => galat = 'Gagal memuat data. Periksa sinyal, mencoba lagi…');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = data;
    return Scaffold(
      appBar: AppBar(title: const Text('Peringatan Dini Longsor')),
      body: d == null
          ? Center(child: galat == null ? const CircularProgressIndicator() : Text(galat!))
          : RefreshIndicator(
              onRefresh: _muat,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (galat != null) Text(galat!, style: const TextStyle(color: Colors.red)),
                  for (final w in d.wilayah) ...[
                    Text('Bacaan sensor · ${w.nama}',
                        style: Theme.of(context).textTheme.titleLarge),
                    Text(w.offline
                        ? 'Alat tidak mengirim data (terakhir ${w.waktu ?? '-'} WIB)'
                        : 'Data ${w.waktu ?? '-'} WIB'),
                    const SizedBox(height: 8),
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      childAspectRatio: 0.95,
                      children: [for (final s in w.sensor) KartuSensor(sensor: s, ambang: d.ambang)],
                    ),
                    const SizedBox(height: 24),
                  ],
                  const Text(
                    'Ini alat bantu pemantauan warga, bukan peringatan resmi BPBD. '
                    'Saat ragu, utamakan keselamatan dan ikuti arahan perangkat desa.',
                    style: TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
    );
  }
}
```

---

## 5. Isi `GET /api/ews/grafik`

Parameter wajib:

| Parameter | Nilai |
|---|---|
| `wilayah` | `id` dari `wilayah[]` |
| `sensor` | `kelembapan_tanah`, `intensitas_hujan`, `kemiringan`, atau `kelembapan_udara` |
| `rentang` | `1j` (titik tiap 1 menit), `24j` (tiap 10 menit), `7h` (tiap 1 jam) |

Balasan:

```json
{
  "sensor": "Kelembapan tanah", "satuan": "%", "wilayah": "Lereng Kebun Kopi",
  "dari": 1794135657000, "sampai": 1794139257000,
  "ambang": { "waspada": 50, "validasi": 80 },
  "titik": [ { "t": 1794135660000, "y": 30.0 }, { "t": 1794135720000, "y": null } ]
}
```

- `t` = waktu dalam milidetik (`DateTime.fromMillisecondsSinceEpoch(t)`).
- `y` = nilai **tertinggi** dalam rentang titik itu. `y: null` artinya alat sempat tidak mengirim;
  putuskan garis di situ, jangan disambung.
- `ambang` = `null` untuk `kelembapan_udara`.
- Batas: 120 permintaan per menit. Paket grafik yang cocok: `fl_chart`.

---

## 6. Hal yang sering keliru

| Gejala | Penyebab | Perbaikan |
|---|---|---|
| `type 'int' is not a subtype of type 'double'` | `nilai` datang sebagai `30`, bukan `30.0` | baca `as num?` lalu `.toDouble()` |
| Muncul `Â°` alih-alih `°` | isi dibaca dengan `res.body` | pakai `utf8.decode(res.bodyBytes)` |
| `Connection refused` di emulator | memakai `127.0.0.1` | pakai `10.0.2.2` |
| HP tidak bisa tersambung | server hanya mendengarkan laptop sendiri | `php artisan serve --host=0.0.0.0`, izinkan di Windows Firewall |
| `Cleartext HTTP traffic not permitted` | Android menolak http | `usesCleartextTraffic` (uji coba saja) |
| Kemiringan −18° dianggap Normal | lupa nilai mutlak | `nilai.abs()` sebelum dibandingkan |
| Wilayah Awas tapi aplikasi bilang Aman | status wilayah dihitung sendiri | ambil `status` dari server (bagian 3) |

Data di server diperbarui paling cepat tiap ±8 detik, jadi memanggil lebih sering dari 5–10 detik
tidak membuat data lebih baru, hanya menghabiskan kuota.
