# EWS Lumeneng

Aplikasi Android peringatan dini tanah longsor untuk warga Desa Lumeneng,
Kecamatan Paninggaran, Kabupaten Pekalongan. Dibuat oleh tim KKN 2026.

Tiga menu:

- **Beranda**: peta desa dengan area pantau alat EWS di Sikembang (warna ikut
  status) dan catatan perubahan status terbaru.
- **Sensor**: bacaan sensor alat EWS (kelembapan tanah, intensitas hujan,
  kemiringan, kelembapan udara) dan riwayat status.
- **Lapor**: warga melaporkan tanda longsor dengan cerita dan foto. Teks dibaca
  model NLP, foto diperiksa model CNN, lalu laporan dikirim lewat WhatsApp ke
  penanggung jawab.

## Alur data

```
Alat ESP32 ──POST──▶ Server Laravel (desalumeneng.id) ──GET /api/ews/data──▶ Aplikasi
                            └──── Firebase Cloud Messaging (topik warga-lumeneng) ──▶ HP warga
```

Status (Aman, Waspada, Awas) selalu ditentukan server, tidak dihitung di
aplikasi. Format data ada di [ews_flutter.md](ews_flutter.md), kiriman
notifikasi di [docs/laravel-push-notifikasi.md](docs/laravel-push-notifikasi.md).
Server Laravel ada di repo terpisah.

## Saat kondisi buruk

Aplikasi ini dipakai di desa dengan sinyal yang sering putus, jadi perilaku
berikut sengaja dijaga dan dites:

| Keadaan | Yang terjadi |
| --- | --- |
| Dibuka tanpa sinyal | Data server terakhir dibaca dari HP (`EwsCache`), splash tidak menunggu. |
| Data lebih dari 15 menit (`ewsStaleAfter`) | Normal tidak lagi tampil aman (abu-abu, garis putus), ada catatan "Belum tersambung ke server". Waspada dan Awas tetap tampil. |
| Sinyal HP putus | Tidak membunyikan peringatan. Begitu tersambung lagi, status dicatat di lonceng tanpa bunyi. |
| Waspada dari sebagian sensor | Notifikasi muncul tanpa bunyi. HP baru berbunyi bila semua sensor yang punya ambang sudah Waspada (`MonitoringData.ringsPhone`), atau saat Awas. |
| Alat EWS berhenti mengirim | Notifikasi muncul tanpa bunyi dan getar, juga bila bacaan terakhirnya Waspada. |
| Server mengubah bentuk JSON | Data lama tetap tampil, galat dikirim ke Crashlytics. |
| Aplikasi ditutup | Riwayat lonceng (50 terakhir) tetap tersimpan. |
| Galat yang tidak tertangkap | Dicatat ke Firebase Crashlytics (hanya build release). |

## Menjalankan

Butuh Flutter stable (lihat versi di `.github/workflows/ci.yml`) dan
`android/app/google-services.json` dari Firebase Console. File itu tidak masuk
repo karena repo ini publik.

```sh
flutter pub get
flutter run
```

Mencoba server lain tanpa mengubah kode:

```sh
flutter run --dart-define=EWS_BASE_URL=http://192.168.1.17:8000
```

Pengaturan lain (nomor WhatsApp penanggung jawab, wilayah server yang terhubung
ke alat, interval pengambilan data) ada di [lib/config.dart](lib/config.dart).

## Tes

```sh
flutter analyze
flutter test
```

Keduanya juga dijalankan GitHub Actions di setiap push dan pull request.

## Struktur

```
lib/
  analysis/   NLP teks laporan, CNN foto, isi pesan laporan
  data/       bentuk data server, status Beranda, peta desa (GeoJSON)
  screens/    halaman; Beranda dipecah ke screens/home/
  services/   pengambilan data, simpanan HP, notifikasi, lokasi, WhatsApp
  widgets/    komponen yang dipakai beberapa halaman
assets/
  peta/       batas desa, zona rawan longsor, area pantau EWS
  models/     model TFLite untuk foto
  nlp/        kamus dan model teks
tool/         skrip pembuat aset (logo, splash, peta dari kajian, latih CNN)
```

Zona rawan longsor dan batas desa ditelusuri dari gambar di Kajian Pemetaan
Bencana Desa Lumeneng 2024 (LPBI NU Kabupaten Pekalongan dan Ringan Tangan
Indonesia) dengan `tool/peta_dari_kajian.dart`. Ini perkiraan; ganti dengan
file GIS asli bila sudah didapat.

## Sebelum rilis ke Play Store

- Build release masih ditandatangani dengan kunci debug
  (`android/app/build.gradle.kts`). Buat keystore sendiri dan simpan di luar repo.
- Siapkan kebijakan privasi (aplikasi memakai lokasi dan foto). Isinya bisa
  mengikuti bagian "Data dan privasi" di halaman Tentang.
- Naikkan `version` di `pubspec.yaml`.
