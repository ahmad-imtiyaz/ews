# Push notifikasi EWS ke HP warga (untuk server Laravel)

Aplikasi EWS Lumeneng sudah siap menerima peringatan dari server lewat Firebase Cloud Messaging (FCM). Yang belum ada hanya pengirimnya di server. Selama server belum mengirim, notifikasi baru muncul saat warga membuka aplikasi, karena hanya aplikasi yang mengecek `GET /api/ews/data`, dan Android menghentikan aplikasi yang tidak dibuka.

Kalau server yang mengirim, Android sendiri yang menampilkan notifikasi. Notifikasi tetap muncul walaupun aplikasi tertutup, selama HP tersambung internet (data atau WiFi).

```text
ESP → Laravel (status wilayah berubah) → FCM (topik warga-lumeneng) → semua HP warga
```

### Perubahan 25 November 2026: Waspada sebagian sensor tanpa suara

Warga terganggu karena HP berbunyi setiap kali satu sensor saja menyentuh batas Waspada. Mulai aplikasi versi berikutnya:

- Waspada **berbunyi** hanya bila **semua sensor yang punya ambang** (kelembapan tanah, intensitas hujan, kemiringan) sudah level 1 atau 2, dan alatnya masih mengirim. Kelembapan udara tidak punya ambang, jadi tidak ikut dihitung.
- Waspada dari sebagian sensor tetap dikirim, tapi lewat channel senyap baru **`ews_waspada_senyap_v1`**.
- Alat tidak mengirim data tetap lewat `ews_offline_v1` (senyap). Pastikan server tidak mengirimnya lewat channel lain atau tanpa `channel_id`, karena itu berbunyi.
- Awas tidak berubah, selalu berbunyi.

Yang perlu diubah di server ada di bagian 3 dan 5. Aplikasi membaca `channel_id` untuk menentukan bunyi, jadi `data.status` tetap `waspada` untuk keduanya.

## 1. Yang perlu disiapkan

| Hal | Nilai |
|---|---|
| Project Firebase | `ews-lumeneng` |
| Topik | `warga-lumeneng` (semua HP berlangganan otomatis saat aplikasi dibuka) |
| API | FCM HTTP v1. API lama (server key) sudah dimatikan Google. |
| Kunci | File service account JSON dari pemilik project Firebase |

**Kunci service account:** pemilik project membuatnya di Firebase Console → Project settings → Service accounts → *Generate new private key*, lalu mengirimkannya secara pribadi. Simpan file ini hanya di server, di luar folder `public/`, dan jangan masukkan ke git. Siapa pun yang memegang file ini bisa mengirim notifikasi ke semua HP warga.

## 2. Pasang paket

```bash
composer require kreait/laravel-firebase
```

`.env`:

```dotenv
FIREBASE_CREDENTIALS=/path/aman/di/server/ews-lumeneng-service-account.json
```

## 3. Kapan mengirim

Kirim **hanya saat tingkat peringatan satu wilayah berubah**, jangan setiap ada bacaan sensor. Tingkatnya dihitung dari status wilayah dan `level` sensor, sama dengan yang dikirim di `/api/ews/data`:

| Tingkat | Kapan | Kirim? | `data.status` | `channel_id` | Suara |
|---|---|---|---|---|---|
| `awas` | Status Awas | Ya, langsung | `awas` | `ews_awas_v3` | Awas |
| `waspada_semua` | Status Waspada, **semua** sensor berambang level 1 atau 2, alat masih mengirim | Ya | `waspada` | `ews_waspada_v3` | Waspada |
| `waspada` | Status Waspada selain di atas (sebagian sensor, ada sensor tanpa nilai, atau alat diam) | Ya | `waspada` | `ews_waspada_senyap_v1` | Tanpa suara |
| `offline` | Alat berhenti mengirim data (masuk `offline[]`) | Disarankan | `offline` | `ews_offline_v1` | Tanpa suara |
| `aman` | Aman / Normal | **Tidak** | | | |

Sensor berambang adalah sensor yang ada di `ambang`: kelembapan tanah, intensitas hujan, dan kemiringan. Sensor yang `nilai`-nya kosong dianggap belum Waspada.

Aturan supaya HP warga tidak berbunyi terus:

1. Simpan tingkat terakhir tiap wilayah, termasuk `aman`, misalnya di kolom tabel wilayah atau di cache.
2. Kirim kalau tingkat baru berbeda dari tingkat yang tersimpan.
3. Turun dari `waspada_semua` ke `waspada` (status masih Waspada) **tidak** dikirim dan tidak disimpan. Peringatan yang berbunyi sudah sampai, dan sensor yang naik-turun di sekitar ambang tidak boleh membunyikan HP berkali-kali. Tingkat baru dihitung ulang dari awal setelah status keluar dari Waspada.
4. Untuk `waspada`, `waspada_semua`, dan `offline`: jangan kirim tingkat yang sama untuk wilayah yang sama lebih dari sekali dalam 10 menit. Ini menahan status yang bolak-balik Aman ↔ Waspada setiap kali sensor membaca.
5. Untuk Awas: selalu kirim, tanpa jeda.

Status Aman tidak perlu dikirim. Android memakai suara channel yang disebut di pesan. Aplikasi sudah mencatat kembali Normal di lonceng saat dibuka.

## 4. Isi pesan

Semua kolom di bawah wajib, kecuali yang ditandai opsional. Isi `data` harus berupa string.

```json
{
  "topic": "warga-lumeneng",
  "notification": {
    "title": "Awas: EWS Sikembang",
    "body": "Kemiringan tanah 12,4°. Segera menjauh dari lereng dan ikuti arahan petugas. (20.33)"
  },
  "data": {
    "status": "awas",
    "wilayah_id": "1"
  },
  "android": {
    "priority": "high",
    "ttl": "21600s",
    "notification": {
      "channel_id": "ews_awas_v3",
      "sound": "ews_awas",
      "tag": "ews-wilayah-1",
      "notification_priority": "PRIORITY_MAX",
      "visibility": "PUBLIC"
    }
  }
}
```

Kenapa tiap kolom dibutuhkan:

- `notification.title` / `body`: teks yang dibaca warga. Tanpa `notification`, Android tidak menampilkan apa pun saat aplikasi tertutup, jadi jangan kirim pesan yang hanya berisi `data`.
- `data.status`: dibaca aplikasi untuk ikon dan riwayat lonceng. Nilainya `awas`, `waspada`, atau `offline`, huruf kecil.
- `android.priority: high`: tanpa ini, Android bisa menunda pesan saat HP diam atau layar mati (mode Doze).
- `channel_id`: menentukan suara (awas.mp3 / waspada.mp3 / tanpa suara) dan prioritas. Harus persis `ews_awas_v3`, `ews_waspada_v3`, `ews_waspada_senyap_v1`, atau `ews_offline_v1`. Kalau salah atau kosong, Android memakai channel Waspada, yang berbunyi. Aplikasi yang sedang dibuka juga membaca kolom ini untuk menentukan bunyi.
- `sound`: hanya dipakai Android 7 ke bawah. Isi `ews_awas` atau `ews_waspada`. Untuk Waspada senyap dan `offline`, jangan kirim kolom ini.
- `tag`: satu tag per wilayah, jadi peringatan baru untuk wilayah yang sama menggantikan yang lama dan tidak menumpuk.
- `ttl` 6 jam: HP yang mati atau tanpa sinyal lebih dari 6 jam tidak menerima peringatan yang sudah basi. Karena pesan bisa terlambat sampai, cantumkan jam kejadian di `body`.
- `visibility: PUBLIC`: isi peringatan tetap terbaca di layar kunci.

Nama wilayah: wilayah id 1 ("Titik Area 2") adalah satu-satunya alat, di aplikasi disebut **EWS Sikembang** (tanpa nomor). Pakai nama itu di judul, karena nama itu yang dikenal warga di aplikasi.

Isi teks peringatan yang dibaca warga sebaiknya disepakati dengan perangkat desa atau BPBD.

## 5. Contoh kode

`app/Services/EwsPush.php`:

```php
<?php

namespace App\Services;

use Illuminate\Support\Facades\Log;
use Kreait\Firebase\Contract\Messaging;
use Kreait\Firebase\Messaging\CloudMessage;
use Throwable;

class EwsPush
{
    private const TOPIC = 'warga-lumeneng';

    public function __construct(private Messaging $messaging) {}

    /**
     * @param string $tingkat 'awas' | 'waspada_semua' | 'waspada' | 'offline'
     */
    public function send(int $wilayahId, string $tingkat, string $title, string $body): void
    {
        $status = $tingkat === 'waspada_semua' ? 'waspada' : $tingkat;
        $channel = match ($tingkat) {
            'awas' => 'ews_awas_v3',
            'waspada_semua' => 'ews_waspada_v3',
            'waspada' => 'ews_waspada_senyap_v1',
            'offline' => 'ews_offline_v1',
        };
        $sound = match ($tingkat) {
            'awas' => 'ews_awas',
            'waspada_semua' => 'ews_waspada',
            default => null,
        };

        $message = CloudMessage::fromArray([
            'topic' => self::TOPIC,
            'notification' => [
                'title' => $title,
                'body' => $body,
            ],
            'data' => [
                'status' => $status,
                'wilayah_id' => (string) $wilayahId,
            ],
            'android' => [
                'priority' => 'high',
                'ttl' => '21600s',
                'notification' => array_filter([
                    'channel_id' => $channel,
                    'sound' => $sound,
                    'tag' => "ews-wilayah-{$wilayahId}",
                    'notification_priority' => 'PRIORITY_MAX',
                    'visibility' => 'PUBLIC',
                ]),
            ],
        ]);

        try {
            $this->messaging->send($message);
            Log::info('EWS push terkirim', compact('wilayahId', 'tingkat', 'title'));
        } catch (Throwable $e) {
            // Gagal kirim tidak boleh menghentikan penyimpanan data sensor.
            Log::error('EWS push gagal', ['wilayahId' => $wilayahId, 'error' => $e->getMessage()]);
        }
    }
}
```

Dipanggil di tempat status wilayah dihitung, setelah data sensor disimpan. Nama model dan kolom di bawah hanya contoh, sesuaikan dengan yang sudah ada:

```php
$status = $statusHasilHitung;        // mis. 'Aman', 'Waspada', 'Awas', 'Offline'

// Level sensor berambang (kelembapan tanah, intensitas hujan, kemiringan),
// sama dengan `level` di /api/ews/data. null = sensor tidak mengirim.
$semuaSensorWaspada = collect($levelSensorBerambang)
    ->every(fn (?int $level) => $level !== null && $level >= 1);

$baru = match (true) {
    $status === 'Awas' => 'awas',
    $status === 'Waspada' && $semuaSensorWaspada && !$alatDiam => 'waspada_semua',
    $status === 'Waspada' => 'waspada',
    $status === 'Offline' => 'offline',
    default => 'aman',
};
$lama = $wilayah->tingkat_terakhir;  // null untuk wilayah baru

// Masih Waspada tapi sensornya turun lagi: peringatan berbunyi sudah sampai.
$turunDalamWaspada = $lama === 'waspada_semua' && $baru === 'waspada';

if ($baru !== $lama && !$turunDalamWaspada) {
    $wilayah->update(['tingkat_terakhir' => $baru]);

    $jeda = Cache::has("ews-push:{$wilayah->id}:{$baru}");

    if ($baru === 'awas' || ($baru !== 'aman' && !$jeda)) {
        Cache::put("ews-push:{$wilayah->id}:{$baru}", true, now()->addMinutes(10));

        $alat = [1 => 'EWS Sikembang'][$wilayah->id] ?? $wilayah->nama;
        $jam = now()->format('H.i');
        [$judul, $isi] = match ($baru) {
            'awas' => ["Awas: {$alat}", "{$pemicu}. Segera menjauh dari lereng dan ikuti arahan petugas. ({$jam})"],
            'waspada_semua' => ["Waspada: {$alat}", "Semua sensor menyentuh batas Waspada. {$pemicu}. Siapkan diri dan pantau kabar dari petugas. ({$jam})"],
            'waspada' => ["Waspada: {$alat}", "{$pemicu}. Pantau kabar dari petugas. ({$jam})"],
            'offline' => ["{$alat} tidak mengirim data", "Kondisi sekarang belum diketahui, jangan anggap sudah aman. ({$jam})"],
        };

        app(EwsPush::class)->send($wilayah->id, $baru, $judul, $isi);
    }
}
```

`tingkat_terakhir` menggantikan `status_terakhir` dari versi sebelumnya panduan ini. Kalau kolom lama sudah ada, isinya bisa dipakai sebagai awal: `Waspada` jadi `waspada`, sisanya huruf kecil.

Kalau request dari ESP harus cepat dibalas, panggil `send()` dari job antrian (`dispatch(...)`), supaya ESP tidak menunggu Firebase.

## 6. Perintah tes

`app/Console/Commands/EwsTestPush.php`:

```php
<?php

namespace App\Console\Commands;

use App\Services\EwsPush;
use Illuminate\Console\Command;

class EwsTestPush extends Command
{
    protected $signature = 'ews:test-push {tingkat=waspada : awas | waspada_semua | waspada | offline}';
    protected $description = 'Kirim notifikasi uji ke semua HP warga';

    public function handle(EwsPush $push): int
    {
        $tingkat = $this->argument('tingkat');
        $push->send(1, $tingkat, '[UJI] ' . ucfirst($tingkat) . ': EWS Sikembang', 'Ini hanya uji coba sistem, bukan peringatan sungguhan.');
        $this->info("Terkirim: {$tingkat}");

        return self::SUCCESS;
    }
}
```

```bash
php artisan ews:test-push awas
```

Pesan uji ini sampai ke **semua** HP warga. Kalau aplikasi sudah dipakai warga, beri tahu dulu sebelum menguji, dan selalu awali judul dengan `[UJI]`.

## 7. Cara memastikan sudah benar

Di HP Android yang aplikasinya sudah pernah dibuka minimal sekali dengan internet:

1. Tutup aplikasi sepenuhnya: geser keluar dari daftar aplikasi terbaru. Jangan pakai "Paksa berhenti" di Setelan, karena Android memblokir semua notifikasi untuk aplikasi yang dipaksa berhenti.
2. Jalankan `php artisan ews:test-push awas`.
3. Notifikasi harus muncul dalam beberapa detik dengan suara Awas, juga saat layar terkunci.
4. Ulangi dengan `waspada_semua`. Suaranya harus berbeda.
5. Ulangi dengan `waspada` dan `offline`. Notifikasi muncul **tanpa suara dan tanpa getar**.
6. Buka aplikasi saat status Awas sedang berlangsung. HP tidak boleh berbunyi dua kali untuk kejadian yang sama, karena aplikasi sudah menyaring kiriman server dan cek datanya sendiri.

Kalau langkah 3 gagal: cek log Laravel (`EWS push gagal`), pastikan `channel_id` persis sama, dan pastikan aplikasi EWS tidak dibatasi penghemat baterai di HP (Oppo/Realme/Vivo/Xiaomi sering membatasinya).

## 8. Batasan

- Push butuh internet. Peringatan utama di lapangan tetap sirene, bukan HP.
- HP yang belum pernah membuka aplikasi versi terbaru belum berlangganan topik.
- Channel `ews_waspada_senyap_v1` baru dibuat oleh aplikasi versi sesudah 1.0.1, saat dibuka. Di HP yang masih versi 1.0.1, Android tidak menemukan channel itu dan memakai channel Waspada yang berbunyi, jadi Waspada sebagian sensor masih berbunyi sampai aplikasinya diperbarui dan dibuka sekali.
- iPhone belum didukung. Untuk iPhone, project Firebase perlu kunci APNs dari akun Apple Developer.
