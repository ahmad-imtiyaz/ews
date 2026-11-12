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

/// Balasan asli desalumeneng.id, 13 November 2026 (diambil 02.17 WIB). Satu
/// wilayah bersensor (Titik Area 2 = EWS-02) yang berhenti mengirim saat
/// Waspada, dan EWS-01 di "titik" tanpa sensor.
const ewsLiveJson = r'''
{
  "utama": {
    "status": "Waspada",
    "warna": "kuning",
    "lokasi": "Titik Area 2",
    "pemicu": "Kemiringan 9,9°",
    "waktu": "12-11-2026 20:33",
    "saran": "Tanah mulai jenuh air, hujan deras, atau lereng mulai bergerak. Hindari lereng dan siapkan jalur evakuasi."
  },
  "wilayah": [
    {
      "id": 1,
      "nama": "Titik Area 2",
      "poligon": [
        [
          -7.186448,
          109.591973
        ],
        [
          -7.186262,
          109.591157
        ],
        [
          -7.18783,
          109.591357
        ],
        [
          -7.187723,
          109.591529
        ]
      ],
      "lintang": -7.186625,
      "bujur": 109.591824,
      "status": "Waspada",
      "warna": "kuning",
      "pemicu": "Kemiringan 9,9°",
      "waktu": "12-11-2026 20:33",
      "offline": true,
      "kondisi_tak_diketahui": true,
      "sensor": {
        "kelembapan_tanah": {
          "nama": "Kelembapan tanah",
          "ikon": "tanah",
          "nilai": 0,
          "teks": "0%",
          "level": 0,
          "kata": "Normal",
          "warna": "hijau"
        },
        "intensitas_hujan": {
          "nama": "Intensitas hujan",
          "ikon": "hujan",
          "nilai": 0,
          "teks": "0%",
          "level": 0,
          "kata": "Normal",
          "warna": "hijau"
        },
        "kemiringan": {
          "nama": "Kemiringan",
          "ikon": "miring",
          "nilai": 9.9,
          "teks": "9,9°",
          "level": 1,
          "kata": "Waspada",
          "warna": "kuning"
        },
        "kelembapan_udara": {
          "nama": "Kelembapan udara",
          "ikon": "udara",
          "nilai": 97.9,
          "teks": "97,9%",
          "level": null,
          "kata": "Hanya informasi",
          "warna": "kosong"
        }
      }
    }
  ],
  "titik": [
    {
      "id": 1,
      "nama": "Titik Area 1",
      "jenis": "alarm",
      "jenis_teks": "EWS alarm",
      "lintang": -7.18539,
      "bujur": 109.588069,
      "poligon": [
        [
          -7.185772,
          109.588701
        ],
        [
          -7.18506,
          109.58775
        ],
        [
          -7.185356,
          109.587502
        ],
        [
          -7.186111,
          109.588447
        ]
      ]
    }
  ],
  "offline": [
    {
      "nama": "Titik Area 2",
      "waktu": "12-11-2026 20:33",
      "saat_waspada": true,
      "teks": "Alat di Titik Area 2 berhenti mengirim data (terakhir 12-11-2026 20:33 WIB) saat kondisi Waspada. Kondisi lereng sekarang tidak diketahui, jadi jangan anggap sudah aman. Hindari lereng."
    }
  ],
  "log": [
    {
      "waktu": "12-11-2026 19:38",
      "wilayah": "Titik Area 2",
      "status": "Awas",
      "warna": "merah",
      "keterangan": "Kabel EWS putus, Kemiringan 9,9°"
    }
  ],
  "ambang": {
    "kelembapan_tanah": {
      "waspada": 50,
      "validasi": 80
    },
    "intensitas_hujan": {
      "waspada": 40,
      "validasi": 70
    },
    "kemiringan": {
      "waspada": 5,
      "validasi": 15
    }
  }
}
''';
