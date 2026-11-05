pi --session 01a19c56-c422-7606-8575-50ed0a260630

# Project Brief — Aplikasi EWS Longsor untuk KKN

## 1. Tujuan dokumen dan cara melanjutkan sesi

Dokumen ini menyimpan konteks percakapan agar sesi pengembangan berikutnya memahami maksud pengguna tanpa mengulang pembahasan dari awal.

Sebelum merancang atau mengubah aplikasi:
1. Baca brief ini dan periksa kondisi kode terkini. Dokumen ini menjelaskan kebutuhan dan arah rancangan, bukan bukti fitur sudah diimplementasikan.
2. Bedakan **kebutuhan terkonfirmasi**, **usulan rancangan**, dan **keputusan terbuka** di bawah.
3. Lanjutkan dengan satu alur kecil yang bisa diperiksa hasilnya; jelaskan asumsi sebelum mengunci pilihan teknis.
4. Jika pengguna mengubah kebutuhan atau menyetujui usulan, perbarui bagian terkait agar brief tidak menjadi catatan usang.

Bahasa komunikasi dan dokumentasi produk: bahasa Indonesia. Pengguna membutuhkan bantuan berpikir sekaligus implementasi bertahap, bukan langsung pembangunan seluruh isi dokumen referensi.

## 2. Kebutuhan yang sudah dikonfirmasi pengguna

### Konteks dan prioritas

- Aplikasi dibangun dengan **Flutter** untuk kegiatan **KKN**.
- Fokusnya adalah **Early Warning System (EWS) tanah longsor**, terhubung dengan perangkat lapangan berbasis ESP.
- Halaman paling penting adalah **peta dengan log aktivitas di bawah peta**.
- Pelaporan warga merupakan fitur unggulan yang paling membingungkan pengguna dan membutuhkan perhatian khusus.
- **NLP dan CNN wajib diterapkan** sebagai bagian luaran; keduanya bukan sekadar fitur opsional yang boleh dihilangkan dari arah proyek.
- Batas waktu yang disampaikan: **“20 hari, aplikasi ini harus ada progres.”** Pengguna belum menyebut tanggal mulai atau menyatakan bahwa seluruh sistem harus siap operasional dalam 20 hari.
- **Belum ada dataset** contoh laporan bahasa lokal dan foto lapangan berlabel.

### Integrasi perangkat EWS

Rencana sensor yang disebut pengguna:
- Kelembapan udara.
- Kelembapan tanah.
- pH tanah.
- Sensor utama pendeteksi tanda/pergerakan yang berkaitan dengan longsor; jenis dan cara kerjanya belum dijelaskan.

Aplikasi diharapkan menerima data perangkat, kemungkinan melalui API. Perubahan kondisi di titik terpasang perlu terhubung dengan peta, perubahan warna, dan notifikasi.

Status kesiapan ESP, jumlah perangkat, kontrak data, interval pengiriman, konektivitas, dan ambang sensor **belum dikonfirmasi**.

### Pelaporan warga

- Mengikuti gagasan NLP dan CNN pada dokumen referensi di bagian 3.
- Warga bisa menulis dengan bahasa sehari-hari, khususnya bahasa Jawa lokal **Lumeneng, Pekalongan** sebagaimana disebut pengguna.
- Pengguna menginginkan keterangan tersebut dapat dibakukan menjadi bahasa Indonesia setelah laporan dikirim.
- Foto laporan ikut diperiksa; pengguna membutuhkan penjelasan mengenai perbedaan foto buram/jelas dan analisis isi foto.

### Pengembangan berikutnya

Desa mungkin membutuhkan pelaporan/pengaduan umum dari warga kepada kepala desa. Pengguna menyatakan fitur ini **coming soon / nanti dahulu**, bukan prioritas tahap sekarang.

## 3. Referensi dan batas maknanya

Dokumen lokal yang diberikan pengguna:

`C:\Users\ALBA\Downloads\Penerapan_NLP_CNN_Aplikasi_EWS_imtiyaz.docx`

Judul: **Penerapan NLP dan CNN pada Aplikasi — Sistem Peringatan Dini (EWS) Mitigasi Tanah Longsor Terintegrasi Aplikasi Seluler dan Website**.

Ringkasan berikut berasal dari pembacaan teks dokumen:
- Bagian 3: NLP membersihkan/menormalisasi bahasa, mengklasifikasikan tanda kejadian, mengambil informasi lokasi, dan menilai urgensi.
- Bagian 4: kelayakan foto diperiksa terlebih dahulu; CNN mengenali isi foto seperti retakan, longsoran, rembesan, pohon miring, atau tidak relevan.
- Bagian 5: hasil teks dan foto dicocokkan dan digabung menjadi informasi laporan.
- Bagian 6: laporan foto tanpa teks dapat diproses melalui pemeriksaan metadata, OCR, atau pembuatan deskripsi foto.
- Bagian 7: laporan, data sensor, peta, dan penyampaian peringatan dihubungkan dalam satu alur.
- Bagian 8: model memerlukan data latih berlabel dan evaluasi.
- Bagian 9: angka skor, bobot, ambang, serta nama model merupakan **contoh**, bukan parameter yang sudah tervalidasi untuk lokasi proyek.

Dokumen menyebut pilihan seperti IndoBERT, MobileNet/ResNet, Firebase, WhatsApp, dan chatbot. Penyebutan tersebut **belum berarti pengguna sudah memilih teknologi itu atau meminta semuanya dibangun pada tahap awal**.

## 4. Arah produk yang diusulkan

**Status: rekomendasi hasil diskusi, belum seluruhnya disetujui sebagai spesifikasi final.**

> Aplikasi pemantauan dan pelaporan dini longsor berbasis peta: sensor memberi hasil pengukuran, warga memberi informasi kejadian, NLP dan CNN membantu analisis, dan petugas memverifikasi serta menindaklanjuti laporan.

Pembagian peran yang diusulkan:
- **Warga:** melihat informasi pemantauan, mengirim laporan, dan mengikuti perkembangan laporannya.
- **Petugas/admin:** memeriksa laporan, melihat hasil analisis dan data sensor, lalu mencatat hasil verifikasi/tindak lanjut. Identitas pihak yang menjalankan peran ini perlu disepakati dengan desa/tim.
- **AI:** membantu mengolah informasi, bukan menetapkan kebenaran laporan atau menjamin keamanan wilayah.

Fokus tahap awal adalah alur EWS longsor, bukan aplikasi pengaduan desa serba guna.

## 5. Istilah yang perlu dibedakan

- **Titik pantau:** lokasi perangkat sensor tertentu.
- **Zona:** area dengan batas yang ditentukan dan dasar keterwakilan pemantauan yang jelas; bukan otomatis seluruh area sekitar sensor.
- **Lokasi kejadian:** tempat kejadian yang dilaporkan, yang bisa berbeda dari posisi ponsel pelapor.
- **Data sensor:** pengukuran dengan satuan, identitas perangkat, serta waktu pengukuran/penerimaan yang jelas.
- **Status koneksi/kesegaran data:** apakah data masih tersedia dan cukup baru untuk dipakai.
- **Status pemantauan:** hasil aturan kondisi yang telah disepakati; berbeda dari status koneksi.
- **Hasil AI:** dugaan kategori, pembakuan teks, dan keyakinan model; berbeda dari hasil verifikasi.
- **Status laporan:** tahap penanganan laporan oleh sistem/petugas.
- **Log aktivitas:** catatan kejadian/perubahan status, bukan hanya daftar angka sensor mentah.

## 6. Rancangan pengalaman aplikasi yang diusulkan

### 6.1 Peta sebagai halaman utama

**Status: disetujui pengguna, sudah dibuat dengan data contoh.** Aplikasi dibuka dengan animasi splash sekitar 3 detik (tanah retak, sirene, warga melapor), bisa dilewati dengan ketukan, dilewati otomatis saat status Awas, lalu masuk ke Peta tanpa login. Animasinya dibuat oleh `tool/generate_splash.py`. Gaya visualnya hitam putih, warna hanya untuk status, dengan ukuran teks standar dan susunan mengikuti `gambaran.webp`: peta dalam kartu dengan dropdown mode Peta, Satelit, dan Medan, lalu catatan di bawahnya. Peringatan hanya memakai notifikasi bawaan HP dengan suara khusus (`tool/generate_notification_sounds.py`), tanpa pop up dan tanpa kartu status di atas peta, dan riwayatnya ada di lonceng pojok kanan atas. Di dalam aplikasi, kondisi terbaca dari marker dan catatan. Notifikasi saat aplikasi tertutup wajib ada dan memakai Firebase Cloud Messaging (project `ews-lumeneng`, paket `id.kkn.ewslumeneng`, topik `warga-lumeneng`). Server harus mengirim kiriman berjenis notifikasi dengan prioritas tinggi dan channel `ews_awas_v1` atau `ews_waspada_v1`. Server pengirim belum dibuat. Arah ini menggantikan gaya kertas dan nila di `stitch-prompt.md`.

Susunan utama:
1. Ringkasan kondisi dan waktu pembaruan.
2. Peta yang menampilkan titik sensor serta lokasi laporan dengan ikon berbeda.
3. Log aktivitas terbaru di bawah peta.
4. Tombol **Buat laporan** yang mudah dijangkau.

Ketuk titik sensor untuk melihat nama/lokasi perangkat, status pemantauan, nilai dan satuan sensor, waktu data terakhir, serta riwayat singkat.

Contoh log, seluruhnya ilustrasi:
- `10.42 — EWS-01 berubah menjadi Waspada`.
- `10.39 — Laporan retakan masuk, menunggu verifikasi`.
- `10.35 — EWS-02 tidak mengirim data`.
- `10.20 — Petugas memverifikasi laporan di Dusun A`.

**Rekomendasi tahap awal:** perubahan warna diterapkan pada marker titik sensor. Pewarnaan wilayah/poligon menunggu definisi zona dan dasar penetapan statusnya.

Hijau/kuning/merah dapat dipakai untuk kategori pemantauan yang disepakati. Data tidak tersedia atau kedaluwarsa harus ditampilkan secara berbeda, misalnya abu-abu. Nilai terakhir yang sudah kedaluwarsa tidak boleh ditampilkan seolah merupakan kondisi normal terkini. Warna perlu disertai label agar maknanya jelas.

### 6.2 Formulir laporan

Usulan masukan:
- Lokasi kejadian: usulan GPS, dapat dikoreksi pelapor.
- Jenis tanda yang terlihat: pilihan sederhana, termasuk pilihan belum tahu/lainnya.
- Keterangan: menerima bahasa sehari-hari atau bahasa lokal.
- Foto pendukung jika tersedia dan aman diambil.

Pilihan kategori warga adalah keterangan tambahan, bukan label kebenaran untuk melatih atau mengevaluasi model tanpa pemeriksaan.

Setelah dikirim, tampilkan konfirmasi penerimaan dan status penanganan. Analisis AI dapat menyusul; kegagalan analisis tidak boleh membuat laporan yang sudah diterima menghilang.

Contoh status usulan:

`Diterima → Menunggu verifikasi → Terverifikasi / Belum dapat dikonfirmasi → Ditindaklanjuti sesuai hasil pemeriksaan`

Detail laporan dapat memuat teks asli, hasil pembakuan, hasil NLP, kelayakan foto, hasil CNN, dan catatan petugas. Warga tidak perlu memahami istilah teknis atau persentase model untuk melapor.

### 6.3 Kebutuhan layar, bukan susunan tab final

- Peta dan log.
- Buat laporan.
- Riwayat serta detail laporan.
- Detail titik sensor.
- Pemeriksaan laporan untuk petugas.

Susunan navigasi, autentikasi, dan apakah tampilan petugas berada di aplikasi yang sama atau dashboard terpisah belum dipilih.

## 7. NLP: ruang lingkup realistis

**Usulan target:** memahami ungkapan lokal terkait tanda longsor, bukan membangun penerjemah umum seluruh dialek Lumeneng dalam 20 hari.

Contoh dari dokumen referensi, bukan hasil validasi dialek lokal:

> `lemah e bengkah neng mburi omah pak RT, saiki tambah amba`
>
> Hasil pembakuan: `Tanah retak di belakang rumah Pak RT, sekarang semakin lebar.`

Alur usulan:
1. Simpan teks asli tanpa menggantinya dengan hasil AI.
2. Normalisasi kata dan frasa lokal memakai kamus yang divalidasi penutur setempat.
3. Jalankan model klasifikasi teks untuk mengenali tanda kejadian.
4. Simpan dan tampilkan hasil pembakuan serta kategori sebagai hasil bantuan analisis.
5. Arahkan hasil yang tidak jelas ke pemeriksaan petugas; sediakan jalur koreksi hasil pembakuan.

Kamus normalisasi adalah baseline/tahap praproses, bukan bukti model telah memahami seluruh bahasa lokal. Jika memakai model seperti IndoBERT, kebutuhan pelatihan, data berlabel, dan evaluasinya tetap harus dipenuhi.

Pertahankan makna penyangkalan, waktu, dan perubahan. `Tanah retak` berbeda dengan `tanah tidak retak`; pembuangan stopword atau stemming bukan langkah wajib untuk setiap jenis model.

Lokasi GPS/pin dan informasi tempat dari teks saling membantu. Ungkapan seperti `belakang rumah Pak RT` memerlukan rujukan lokal; tidak otomatis bisa dipetakan oleh model.

## 8. Foto: kelayakan dan CNN merupakan proses berbeda

### Pemeriksaan kelayakan

Periksa file dapat dibaca, format, resolusi, pencahayaan, dan ketajaman. Deteksi buram dapat memakai pengolahan citra sederhana; pemeriksaan ini sendiri tidak membuktikan penerapan CNN.

Foto buram tidak berarti laporan palsu. Terima laporan dan tandai keterbatasan buktinya; tawarkan pengambilan ulang hanya jika aman.

### Klasifikasi CNN

CNN bertujuan mengenali isi foto, bukan sekadar membedakan foto jelas dan buram.

Dokumen mengusulkan beberapa kelas. Untuk prototipe, pertimbangkan sedikit kelas yang benar-benar didukung data, misalnya retakan, longsoran, dan tidak relevan; hasil juga dapat dinyatakan **belum yakin**. Daftar kelas final belum disepakati.

MobileNet dengan transfer learning adalah kandidat, bukan model longsor lokal siap pakai. CNN wajib benar-benar dijalankan bila fitur dinyatakan telah mengimplementasikan CNN; hasil simulasi harus ditandai sebagai simulasi.

Foto jelas belum membuktikan kejadian benar, baru terjadi, atau berada di lokasi pelapor. Metadata EXIF bisa tidak tersedia atau tidak dapat dipercaya sebagai satu-satunya bukti. Skor keyakinan kategori bukan probabilitas terjadinya longsor atau ukuran tingkat bahaya.

## 9. Verifikasi, penggabungan informasi, dan keselamatan

Rekomendasi awal:
- Tampilkan hasil NLP dan CNN berdampingan sebagai bantuan pemeriksaan.
- Hasil yang tampak sesuai dapat ditandai saling mendukung; hasil berbeda memerlukan tinjauan, bukan penolakan otomatis.
- Perbedaan kategori tidak selalu berarti kontradiksi: teks menyebut rembesan dan foto menunjukkan retakan bisa sama-sama benar.
- Laporan yang belum diverifikasi tidak langsung mengubah wilayah menjadi merah atau menyalakan peringatan publik.
- Bobot penggabungan, indeks laporan/sensor, urgensi, dan ambang bahaya harus ditentukan serta diuji, bukan disalin dari contoh angka dokumen.
- Hubungan kelembapan, pH, dan sensor utama terhadap tingkat bahaya perlu dibahas dengan tim perangkat serta pihak yang memahami kondisi lapangan. Jenis sensor saja belum cukup untuk menyimpulkan risiko.
- Data kosong, koneksi terputus, atau model tidak yakin ditampilkan sebagai keterbatasan informasi, bukan kondisi aman.
- Kesepakatan penerbitan peringatan dan pihak yang berwenang harus jelas sebelum penggunaan nyata.
- Notifikasi ponsel bergantung pada jaringan dan kondisi perangkat. Fungsi sirene/peringatan lokal perlu dirancang agar tidak bergantung pada keberhasilan notifikasi aplikasi.
- Panduan pelaporan mengutamakan keselamatan; jangan mendorong warga mendekati lereng berbahaya demi foto.

## 10. Arsitektur awal yang direkomendasikan

```text
ESP + sensor → server → penyimpanan/status/log → Flutter dan notifikasi

Laporan Flutter → server → penyimpanan laporan + foto
                        → NLP dan CNN
                        → hasil analisis → pemeriksaan petugas
```

Pembagian tanggung jawab:
- **Flutter:** peta, formulir, pemilihan lokasi, riwayat, hasil analisis, dan penerimaan notifikasi.
- **Server:** menerima data perangkat/laporan, menyimpan data, menjalankan analisis AI, menerapkan aturan status yang disepakati, dan mencatat log.
- **ESP:** pembacaan sensor dan fungsi perangkat lapangan.

Pilihan ini menghindari aplikasi harus mengakses tiap ESP secara langsung. HTTP atau MQTT untuk perangkat masih merupakan pilihan terbuka. Penyedia peta, backend, database, penyimpanan foto, autentikasi, dan pengiriman notifikasi belum diputuskan.

Saat menyepakati kontrak data, minimal pastikan identitas perangkat/laporan, lokasi, nilai dan satuan pengukuran, waktu, serta status penerimaan/analisis tidak ambigu. Hindari menganggap data simulasi sebagai data lapangan.

## 11. Rencana progres 20 hari yang diusulkan

Rencana berikut merupakan pembagian target, bukan janji sistem telah andal untuk keselamatan publik.

| Hari relatif | Fokus | Bukti progres yang diperiksa |
| --- | --- | --- |
| 1–3 | Sepakati alur, sensor, kategori awal, dan pihak verifikasi; mulai data lokal | Brief/alur disepakati, contoh kontrak data, contoh teks/foto terkumpul |
| 4–7 | Peta, detail titik, log, dan formulir | Alur tampilan berjalan dengan data simulasi yang diberi label |
| 8–11 | Integrasi data dan penyimpanan laporan | Satu ESP atau simulator mengirim data; laporan dan foto tersimpan; petugas dapat memeriksa |
| 12–16 | Analisis awal | Normalisasi, model NLP, pemeriksaan kelayakan foto, dan CNN terhubung sesuai kesiapan data |
| 17–20 | Pengujian dan demo utuh | Alur end-to-end berjalan; kegagalan koneksi/model ditangani dan keterbatasan tercatat |

Pengumpulan serta pelabelan data berjalan **sejak hari pertama secara paralel**, bukan menunggu antarmuka selesai. Jika data belum memadai, jelaskan keterbatasan model dan progres aktual secara jujur; jangan mengganti kewajiban AI dengan label tampilan palsu.

### Data dan evaluasi

- Kumpulkan contoh bahasa lokal dengan bantuan penutur setempat dan tetapkan label berdasarkan pemeriksaan manusia.
- Gunakan foto yang sesuai konteks, berizin, dan ditinjau labelnya. Hindari mengekspos identitas/lokasi pribadi di tampilan publik tanpa kebutuhan dan persetujuan yang jelas.
- Pisahkan data pelatihan dan pengujian; foto asal yang sama, hasil augmentasinya, dan contoh sangat mirip dari kejadian yang sama jangan bocor antar-kelompok.
- Catat kesalahan per kategori; ukur kinerja dengan data uji yang tersedia dan laporkan keterbatasannya. Jangan mengarang akurasi atau menganggap jumlah data sedikit cukup untuk penggunaan lapangan.

### Skenario penerimaan prototipe

1. Data masuk dari satu perangkat/simulator, titik peta diperbarui, dan perubahan relevan tercatat di log.
2. Data kedaluwarsa atau perangkat terputus terlihat berbeda dari kondisi normal.
3. Laporan bahasa lokal dan foto tersimpan; teks asli tetap tersedia bersama hasil analisis.
4. NLP dan CNN benar-benar berjalan pada versi yang dinyatakan terintegrasi; hasil tidak yakin atau gagal tetap dapat diperiksa petugas.
5. Foto buram tidak menghapus laporan atau membuat laporan otomatis dinyatakan palsu.
6. Petugas mencatat hasil verifikasi dan warga dapat melihat pembaruan penanganan.
7. Perubahan status yang disepakati dapat didemokan pada peta/log/notifikasi; simulasi dibedakan dari peringatan nyata.

## 12. Fitur yang diusulkan untuk ditunda

Selain pengaduan umum desa yang memang ditunda oleh pengguna, rekomendasi penundaan tahap awal adalah:
- Integrasi WhatsApp/SMS.
- Chatbot dan rekomendasi jalur evakuasi otomatis.
- OCR dan image captioning untuk foto tanpa keterangan.
- Penggabungan risiko otomatis penuh yang langsung mengendalikan alarm publik.
- Pewarnaan zona sebelum batas dan dasar statusnya jelas.

Foto tanpa teks tetap bisa diterima untuk pemeriksaan petugas bila alur tersebut didukung. Jika kelak memakai captioning, deskripsi yang dihasilkan dari foto bukan bukti independen kedua dari foto yang sama.

## 13. Keputusan terbuka sebelum implementasi terkait

Tanyakan pada saat keputusan tersebut diperlukan, bukan menganggap jawabannya sudah ada:
- Apa jenis sensor utama longsor, output, satuan, dan aturan kondisi yang direkomendasikan tim perangkat?
- ESP sudah tersedia atau belum? Ada berapa titik, koordinat, koneksi, dan interval kirim?
- Siapa penanggung jawab backend, perangkat, AI, data lokal, serta verifikasi lapangan?
- Apa tanggal mulai dan bentuk progres yang wajib ditunjukkan pada hari ke-20?
- Siapa calon petugas dan siapa yang berwenang menerbitkan/mencabut peringatan?
- Apakah aplikasi digunakan warga umum, petugas, atau keduanya; bagaimana akses, privasi, dan autentikasinya?
- Pilihan peta, backend, protokol, database, dan deployment apa yang sesuai kemampuan serta anggaran tim?
- Kategori NLP/CNN apa yang realistis didukung data awal? Apa kriteria evaluasi bersama dosen/tim?
- Apakah tahap awal cukup mewarnai titik atau ada batas zona yang sudah ditetapkan?

## 14. Alur demo yang menjadi arah kerja

> Data sensor masuk → titik peta diperbarui → perubahan tercatat di log → warga mengirim keterangan lokal dan foto → NLP membantu pembakuan/klasifikasi → kelayakan foto dan CNN dianalisis → petugas memverifikasi → warga melihat perkembangan laporan.

Inti maksud pengguna: **peta dan log sebagai pusat aplikasi, integrasi ESP sebagai sumber pemantauan, serta pelaporan berbantuan NLP dan CNN sebagai fitur unggulan.** Progres 20 hari harus terlihat dan dapat diuji, sambil tetap jujur tentang kesiapan dataset, model, dan keselamatan penggunaan.
