/// Nomor WhatsApp penanggung jawab yang menerima laporan warga.
/// Tulis seperti biasa (08..., +62..., atau 62...); spasi dan tanda hubung
/// boleh. Setelah diganti, build ulang aplikasinya.
const reportWhatsAppNumber = '081226498705';

/// Batas foto per laporan. Lima cukup untuk dekat, jauh, dan sekitar tanpa
/// memberatkan sinyal desa saat dikirim lewat WhatsApp.
const maxReportPhotos = 5;

/// Alamat server Laravel EWS, tanpa garis miring di akhir. Selama kosong,
/// menu Sensor memakai data contoh (lib/data/ews_sample.dart) yang ditandai
/// jelas di layar. Produksi wajib https. Bisa diisi di sini, atau saat build
/// tanpa mengubah kode:
/// `flutter run --dart-define=EWS_BASE_URL=https://alamat-server`.
/// Untuk server di laptop, jalankan `php artisan serve --host=0.0.0.0` lalu
/// pakai IP laptop, mis. `http://192.168.1.17:8000`.
const ewsBaseUrl = String.fromEnvironment('EWS_BASE_URL');

/// Data di server berubah paling cepat tiap ±8 detik, jadi mengambil lebih
/// sering hanya menghabiskan kuota.
const ewsRefreshInterval = Duration(seconds: 10);
