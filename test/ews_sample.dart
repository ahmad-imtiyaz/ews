/// Contoh balasan `GET /api/ews/data`, mengikuti ews_flutter.md, dengan dua
/// wilayah supaya keadaan offline dan nilai kosong ikut teruji.
const ewsSampleJson = '''
{
  "utama": {
    "status": "Waspada", "warna": "kuning", "lokasi": "Lereng Kebun Kopi",
    "pemicu": "Kelembapan tanah 55%", "waktu": "06-11-2026 18:44",
    "saran": "Siapkan tas siaga dan pantau terus halaman ini."
  },
  "wilayah": [
    {
      "id": 1,
      "nama": "Lereng Kebun Kopi",
      "poligon": [[-7.1685, 109.5485], [-7.1685, 109.5515], [-7.1705, 109.552]],
      "status": "Waspada", "warna": "kuning", "pemicu": "Kelembapan tanah 55%",
      "waktu": "06-11-2026 18:44",
      "offline": false,
      "sensor": {
        "kelembapan_tanah": { "nama": "Kelembapan tanah", "ikon": "tanah",  "nilai": 55, "teks": "55%", "level": 1, "kata": "Waspada", "warna": "kuning" },
        "intensitas_hujan": { "nama": "Intensitas hujan", "ikon": "hujan",  "nilai": 20.5, "teks": "20,5%", "level": 0, "kata": "Normal", "warna": "hijau" },
        "kemiringan":       { "nama": "Kemiringan",       "ikon": "miring", "nilai": -9.9, "teks": "-9,9°", "level": 0, "kata": "Normal", "warna": "hijau" },
        "kelembapan_udara": { "nama": "Kelembapan udara", "ikon": "udara",  "nilai": 40, "teks": "40%", "level": null, "kata": "Hanya informasi", "warna": "kosong" }
      }
    },
    {
      "id": 2,
      "nama": "Tebing Dusun B",
      "poligon": [],
      "status": "Aman", "warna": "hijau", "pemicu": null,
      "waktu": "05-11-2026 07:15",
      "offline": true,
      "sensor": {
        "kelembapan_tanah": { "nama": "Kelembapan tanah", "ikon": "tanah",  "nilai": 30, "teks": "30%", "level": 0, "kata": "Normal", "warna": "hijau" },
        "intensitas_hujan": { "nama": "Intensitas hujan", "ikon": "hujan",  "nilai": null, "teks": "-", "level": null, "kata": "Tidak ada data", "warna": "kosong" },
        "kemiringan":       { "nama": "Kemiringan",       "ikon": "miring", "nilai": 21, "teks": "21°", "level": 2, "kata": "Lewat batas", "warna": "kuning" },
        "kelembapan_udara": { "nama": "Kelembapan udara", "ikon": "udara",  "nilai": 88, "teks": "88%", "level": null, "kata": "Hanya informasi", "warna": "kosong" }
      }
    }
  ],
  "offline": [ { "nama": "Tebing Dusun B", "waktu": "05-11-2026 07:15" } ],
  "log": [
    { "waktu": "06-11-2026 18:44", "wilayah": "Lereng Kebun Kopi", "status": "Waspada", "warna": "kuning", "keterangan": "Kelembapan tanah 55%" },
    { "waktu": "06-11-2026 06:02", "wilayah": "Lereng Kebun Kopi", "status": "Aman", "warna": "hijau", "keterangan": "Semua sensor normal" }
  ],
  "ambang": {
    "kelembapan_tanah": { "waspada": 50, "validasi": 80 },
    "intensitas_hujan": { "waspada": 40, "validasi": 70 },
    "kemiringan":       { "waspada": 15, "validasi": 20 }
  }
}
''';
