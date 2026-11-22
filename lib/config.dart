/// Nomor WhatsApp cadangan untuk laporan warga. Nomor yang dipakai diatur
/// dari web Laravel (`/api/ews/pelaporan`); nomor ini hanya dipakai bila HP
/// belum pernah berhasil mengambilnya dari server.
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
/// diwakilinya. Server menamainya "Titik Area 2", di aplikasi cukup "EWS".
/// Wilayah server yang tidak ada di sini tidak ditampilkan.
const ewsDeviceOfArea = {1: 'EWS'};

/// Data di server berubah paling cepat tiap ±8 detik, jadi mengambil lebih
/// sering hanya menghabiskan kuota.
const ewsRefreshInterval = Duration(seconds: 10);

/// Data yang terakhir berhasil diambil lebih lama dari ini dianggap lama:
/// Normal tidak lagi tampil aman. Sama dengan batas server menandai alat
/// berhenti mengirim.
const ewsStaleAfter = Duration(minutes: 15);
