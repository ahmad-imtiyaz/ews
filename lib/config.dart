/// Nomor WhatsApp penanggung jawab yang menerima laporan warga.
/// Tulis seperti biasa (08..., +62..., atau 62...); spasi dan tanda hubung
/// boleh. Setelah diganti, build ulang aplikasinya.
const reportWhatsAppNumber = '081226498705';

/// Batas foto per laporan. Lima cukup untuk dekat, jauh, dan sekitar tanpa
/// memberatkan sinyal desa saat dikirim lewat WhatsApp.
const maxReportPhotos = 5;

/// Alamat server Laravel EWS, tanpa garis miring di akhir. Endpoint
/// `/api/ews/data` publik, jadi aplikasi tidak memegang kunci apa pun. Untuk
/// mencoba server lain tanpa mengubah kode:
/// `flutter run --dart-define=EWS_BASE_URL=http://192.168.1.17:8000`.
const ewsBaseUrl = String.fromEnvironment(
  'EWS_BASE_URL',
  defaultValue: 'https://desalumeneng.id',
);

/// Wilayah bersensor di server (`wilayah[].id`) dan alat di peta yang
/// diwakilinya. Server menamainya "Titik Area 2", di aplikasi EWS-02. EWS-01
/// belum mengirim data, jadi belum ada di sini dan tampil "Tidak ada data".
const ewsDeviceOfArea = {1: 'EWS-02'};

/// Data di server berubah paling cepat tiap ±8 detik, jadi mengambil lebih
/// sering hanya menghabiskan kuota.
const ewsRefreshInterval = Duration(seconds: 10);
