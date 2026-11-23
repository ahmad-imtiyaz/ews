import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import 'sign_category.dart';

const cnnModelAsset = 'assets/models/cnn_longsor.tflite';
const cnnLabelsAsset = 'assets/models/labels.txt';
const cnnInputSize = 224;
const imageConfidenceThreshold = 0.6;

// Semua ambang di bawah diuji 19 November 2026 dengan 16 foto lapangan dari
// Kajian Pemetaan Bencana Desa Lumeneng 2024. Tiap foto juga dirusak buatan
// (diredupkan, digelapkan seperti malam, dibuat terlalu terang, diberi kabut,
// ditutup jari, diperkecil, diburamkan, digoyang) lalu disimpan ulang sebagai
// JPEG.

/// Foto dari kamera HP paling kecil 1080 piksel. Lebar 400 sudah sulit dibaca
/// petugas.
const _minShortSide = 600;

// Penilai gelap dan terang: dua regresi logistik atas [_exposureMeasures],
// dilatih 24 November 2026 dengan SPAQ (Fang dkk., CVPR 2020; boleh untuk
// pendidikan dan riset): foto dari 66 HP dengan nilai mutu pencahayaan dari
// penilai manusia. Di bawah 30 dianggap buruk, 40 ke atas baik. Aturan lama
// (median di bawah 30, atau median 200 ke atas, atau 25% putih terbakar)
// memberi peringatan pada 5,1% foto baik dan menangkap 52% foto gelap serta
// 84% foto terang. Sekarang 2% foto baik untuk tiap arah, 66% foto gelap dan
// 84% foto terang tertangkap. Langit putih di sepertiga atas foto lebih
// ringan bobotnya daripada subjek yang terbakar. Lihat tool/fit_exposure.py.
const _darkBias = 3.5790;
const _darkWeights = {
  'e_mean': -0.00995,
  'e_p02': -0.00491,
  'e_p05': -0.00838,
  'e_p50': -0.00982,
  'e_p95': -0.00425,
  'e_p98': -0.00366,
  'e_low': 1.17608,
  'e_high': -0.01977,
  'e_topHigh': -0.58128,
  'e_topP50': -0.00321,
  'e_restHigh': 2.19771,
  'e_restLow': 1.88148,
  'e_restP50': -0.01045,
  'e_restP95': -0.00305,
  'e_centerP50': -0.00251,
  'e_centerMean': -0.00147,
  'e_centerHigh': 5.87362,
  'e_centerLow': 0.57886,
};
const _brightBias = -9.9990;
const _brightWeights = {
  'e_mean': 0.00552,
  'e_p02': 0.00691,
  'e_p05': 0.00568,
  'e_p50': 0.00335,
  'e_p95': 0.00574,
  'e_p98': 0.00389,
  'e_low': -0.42982,
  'e_high': 0.97803,
  'e_topHigh': 0.63740,
  'e_topP50': 0.00195,
  'e_restHigh': 0.98328,
  'e_restLow': -0.53276,
  'e_restP50': 0.00374,
  'e_restP95': 0.00464,
  'e_centerP50': 0.00397,
  'e_centerMean': 0.00550,
  'e_centerHigh': 1.13516,
  'e_centerLow': -1.10269,
};

// Ubin bertekstur foto asli paling sedikit 61% (foto tajam blur dataset
// Kwentar: 5% terbawah 30%), foto tertutup jari dan dinding polos 0%. Foto
// goyang di ruang redup bisa 3–5%, dan itu harus disebut buram.
const _plainDetailBelow = 0.02;

// Titik hitam foto asli paling tinggi 61, foto berkabut 163 ke atas dengan
// kontras 29–70. Kontras foto asli paling rendah 96.
const _hazeBlackFrom = 120.0;
const _hazeContrast = 80.0;

// Foto berkabut 0% putih terbakar, foto terlalu terang 13–61%.
const _hazeClippedBelow = 0.05;

// Hanya untuk membedakan foto polos (dinding, lensa tertutup jari) dari foto
// buram: foto polos yang tidak buram bernilai 62 ke atas di ukuran lama
// [_blurScore]. Foto asli 76–84.
const _plainSharpFrom = 62.0;

// Penilai buram: regresi logistik atas ukuran [_axisBlur] dan [_coherence] di
// tiga ukuran foto, dilatih 24 November 2026 dengan blur dataset Kwentar
// (CC0): 277 adegan dari puluhan HP, masing-masing difoto tajam, tidak fokus,
// dan goyang. Fotonya diproses dulu seperti image_picker di menu Lapor (sisi
// panjang 1600, JPEG 85), karena noise yang tersisa di ukuran itu terbaca
// tajam. Diuji silang per adegan: foto tajam yang disebut buram 3,6%, tidak
// fokus tertangkap 94%, goyang tertangkap 91%. Buram ringan sengaja dibiarkan
// lolos. Yang masih sering lolos: goyang di rumput atau daun yang sangat rapat,
// dan permukaan polos yang luas (dinding, plastik) kadang terbaca buram. Untuk
// melatih ulang lihat tool/fit_blur.py.
const _blurBias = -7.1967;
const _blurWeights = {
  's1_peakMax': 2.0183,
  's1_peakMin': 1.6380,
  's2_wholeMax': 5.4545,
  's2_wholeMin': 3.5065,
  's2_peakMax': 3.8745,
  's2_peakMin': 2.6695,
  's2_edge': -4.0644,
  's4_wholeMax': 4.3411,
  's4_wholeMin': 3.7152,
  's4_peakMax': 5.0388,
  's4_peakMin': 3.9269,
  's2_coh': 1.7801,
  's4_coh': 0.9335,
  's2_cohMed': -1.2442,
  's4_cohMed': -0.8979,
};

// Goyang di ruang redup dengan lampu menyala lolos dari model: lampu yang
// tercoreng jadi garis tipis bertepi tegas (contoh nyata 24 November 2026,
// tajam 66,6). Garis yang hampir semuanya searah ([_coherence] s2 0,45 ke
// atas) ditambah nilai tajam yang sudah ragu menangkapnya. Di data Kwentar
// foto tajam yang disebut buram naik dari 3,6% ke 5,1%, goyang tertangkap dari
// 92% ke 93,5%; pengguna memilih ini.
const _streakFrom = 0.45;
const _streakSharpBelow = 70.0;

/// [PhotoQuality.sharpness] di bawah ini berarti buram.
const _blurBelow = 50.0;

/// Sisi panjang versi kecil untuk mengukur ketajaman, kira-kira ukuran foto
/// saat dilihat petugas di layar HP. Memperkecil lebih jauh menyembunyikan
/// buram: goyang 20 piksel di foto 4000 piksel tinggal 2 piksel di lebar 400.
const _analysisLongSide = 1024;

/// Masalah foto yang disampaikan ke pelapor dan petugas. Sarannya tidak
/// menyuruh mendekat ke lereng.
enum PhotoIssue {
  unclear(
    'Tidak jelas',
    'Bersihkan lensa, jangan tertutup jari, dan arahkan ke tanda yang '
        'dilaporkan.',
  ),
  dark('Terlalu gelap', 'Nyalakan lampu kilat atau tunggu lebih terang.'),
  bright('Terlalu terang', 'Jangan menghadap matahari atau lampu.'),
  blurry('Buram', 'Pegang HP diam, lalu ketuk layar di bagian yang difoto.'),
  lowResolution(
    'Resolusi rendah',
    'Pakai foto langsung dari kamera, bukan tangkapan layar.',
  );

  const PhotoIssue(this.label, this.tip);

  final String label;
  final String tip;
}

class PhotoQuality {
  const PhotoQuality({
    required this.width,
    required this.height,
    required this.brightness,
    required this.sharpness,
    this.fineSharpness = 100,
    this.coherence = 0,
    this.darkness = 0,
    this.glare = 0,
    this.median = 128,
    this.blackLevel = 0,
    this.contrast = 255,
    this.clipped = 0,
    this.detail = 1,
  });

  final int width;
  final int height;

  /// Rata-rata kecerahan 0–255.
  final double brightness;

  /// 0–100, makin kecil makin buram, di bawah 50 disebut buram. Lihat
  /// [_blurWeights].
  final double sharpness;

  /// Ketajaman cara lama ([_blurScore]), hanya untuk membedakan foto polos
  /// dari foto buram.
  final double fineSharpness;

  /// Seberapa searah garis-garis di foto, 0–1. Lihat [_coherence].
  final double coherence;

  /// 0–100, 50 ke atas terlalu gelap. Lihat [_darkWeights].
  final double darkness;

  /// 0–100, 50 ke atas terlalu terang. Lihat [_brightWeights].
  final double glare;

  /// Kecerahan tengah 0–255: separuh foto lebih gelap dari ini.
  final double median;

  /// Kecerahan 5% piksel tergelap, 0–255. Kabut dan lensa berembun
  /// mengangkatnya: bagian yang seharusnya hitam jadi abu-abu.
  final double blackLevel;

  /// Jarak [blackLevel] ke kecerahan 5% piksel tercerah, 0–255.
  final double contrast;

  /// Bagian foto yang putih terbakar (kecerahan 250 ke atas), 0–1.
  final double clipped;

  /// Bagian foto yang punya garis atau tekstur, 0–1. Lihat [_blurScore].
  final double detail;

  bool get isLowResolution => (width < height ? width : height) < _minShortSide;
  bool get isDark => darkness >= 50;

  /// Foto pudar karena kabut atau lensa berembun cukup disebut tidak jelas.
  bool get isTooBright => !isDark && !isUnclear && glare >= 50;

  /// Hampir tanpa garis, tapi bukan karena buram: nilai tajamnya cuma dari
  /// noise kamera. Lensa tertutup jari, dinding, atau tanah polos.
  bool get isPlain =>
      detail < _plainDetailBelow && fineSharpness >= _plainSharpFrom;

  /// Pudar seperti tertutup kabut atau lensa berembun.
  bool get isHazy => blackLevel >= _hazeBlackFrom && contrast < _hazeContrast;

  /// Foto gelap disebut gelap saja karena itu penyebabnya. Foto terlalu terang
  /// juga tampak pudar, tapi bedanya ada bagian yang putih terbakar; kabut dan
  /// lensa berembun hampir tidak punya.
  bool get isUnclear =>
      !isDark && (isPlain || (isHazy && clipped < _hazeClippedBelow));

  /// Foto gelap dan foto polos tidak dinilai buram: ukurannya terkacau noise.
  bool get _sharpnessCounts => !isDark && !isUnclear;
  bool get isBlurry =>
      _sharpnessCounts &&
      (sharpness < _blurBelow ||
          (coherence >= _streakFrom && sharpness < _streakSharpBelow));

  List<PhotoIssue> get issues => [
    if (isUnclear) PhotoIssue.unclear,
    if (isDark) PhotoIssue.dark,
    if (isTooBright) PhotoIssue.bright,
    if (isBlurry) PhotoIssue.blurry,
    if (isLowResolution) PhotoIssue.lowResolution,
  ];

  /// Mis. "Buram, Terlalu gelap".
  String get issueText => issues.map((issue) => issue.label).join(', ');

  bool get isClear => issues.isEmpty;

  @override
  String toString() =>
      'PhotoQuality(${width}x$height, median ${median.round()}, hitam '
      '${blackLevel.round()}, kontras ${contrast.round()}, terbakar '
      '${(clipped * 100).round()}%, detail ${(detail * 100).round()}%, '
      'tajam ${sharpness.toStringAsFixed(1)}, tajam lama '
      '${fineSharpness.toStringAsFixed(1)}, searah '
      '${coherence.toStringAsFixed(2)}, gelap ${darkness.round()}, terang '
      '${glare.round()})';
}

class PreparedPhoto {
  const PreparedPhoto(this.quality, this.cnnInput);

  final PhotoQuality quality;

  /// Piksel 224 x 224 x 3, nilai 0–1, siap dimasukkan ke CNN.
  final Float32List cnnInput;
}

/// Dekode, cek kelayakan, dan siapkan tensor CNN di isolate terpisah agar
/// tampilan tidak tersendat.
Future<PreparedPhoto?> preparePhoto(Uint8List bytes) =>
    Isolate.run(() => _prepare(bytes));

PreparedPhoto? _prepare(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final photo = img.bakeOrientation(decoded);

  final (:luminance, :width, :height) = _luminance(photo, _analysisLongSide);
  var sum = 0.0;
  final histogram = Int32List(256);
  for (final value in luminance) {
    sum += value;
    histogram[value.round().clamp(0, 255)]++;
  }
  double percentile(double p) {
    final target = p * luminance.length;
    var seen = 0;
    for (var v = 0; v < 256; v++) {
      seen += histogram[v];
      if (seen >= target) return v.toDouble();
    }
    return 255;
  }

  var clipped = 0;
  for (var v = 250; v < 256; v++) {
    clipped += histogram[v];
  }
  final (:blur, :detail) = _blurScore(luminance, width, height);
  final features = _blurMeasures(luminance, width, height);
  final z = _blurWeights.entries.fold(
    _blurBias,
    (sum, weight) => sum + weight.value * features[weight.key]!,
  );
  final exposure = _exposureMeasures(luminance, width, height);

  final square = img.copyResizeCropSquare(photo, size: cnnInputSize);
  final input = Float32List(cnnInputSize * cnnInputSize * 3);
  var offset = 0;
  for (final pixel in square) {
    input[offset++] = pixel.r / 255;
    input[offset++] = pixel.g / 255;
    input[offset++] = pixel.b / 255;
  }

  return PreparedPhoto(
    PhotoQuality(
      width: photo.width,
      height: photo.height,
      brightness: sum / luminance.length,
      sharpness: 100 / (1 + exp(z)),
      fineSharpness: (1 - blur) * 100,
      coherence: features['s2_coh']!,
      darkness: _chance(_darkBias, _darkWeights, exposure),
      glare: _chance(_brightBias, _brightWeights, exposure),
      median: percentile(0.5),
      blackLevel: percentile(0.05),
      contrast: percentile(0.95) - percentile(0.05),
      clipped: clipped / luminance.length,
      detail: detail,
    ),
    input,
  );
}

/// Luminansi foto, diperkecil dengan rata-rata kotak sampai sisi panjangnya
/// [longSide]. Dirata-rata, bukan diambil piksel terdekat, supaya bintik
/// noise sensor tidak membuat foto buram terbaca tajam.
({Float32List luminance, int width, int height}) _luminance(
  img.Image photo,
  int longSide,
) {
  final rgb = photo.format == img.Format.uint8 && photo.numChannels == 3
      ? photo
      : photo.convert(format: img.Format.uint8, numChannels: 3);
  final bytes = rgb.getBytes(order: img.ChannelOrder.rgb);
  final sw = rgb.width, sh = rgb.height;
  final scale = max(1.0, max(sw, sh) / longSide);
  final w = max(1, (sw / scale).round()), h = max(1, (sh / scale).round());

  final out = Float32List(w * h);
  for (var y = 0; y < h; y++) {
    final y0 = y * sh ~/ h, y1 = max(y0 + 1, (y + 1) * sh ~/ h);
    for (var x = 0; x < w; x++) {
      final x0 = x * sw ~/ w, x1 = max(x0 + 1, (x + 1) * sw ~/ w);
      var sum = 0.0;
      for (var yy = y0; yy < y1; yy++) {
        var i = (yy * sw + x0) * 3;
        for (var xx = x0; xx < x1; xx++, i += 3) {
          sum += 0.299 * bytes[i] + 0.587 * bytes[i + 1] + 0.114 * bytes[i + 2];
        }
      }
      out[y * w + x] = sum / ((y1 - y0) * (x1 - x0));
    }
  }
  return (luminance: out, width: w, height: h);
}

/// [g] diperkecil [factor] kali dengan rata-rata kotak.
({Float32List luminance, int width, int height}) _shrink(
  Float32List g,
  int w,
  int h,
  int factor,
) {
  final sw = max(1, w ~/ factor), sh = max(1, h ~/ factor);
  final out = Float32List(sw * sh);
  for (var y = 0; y < sh; y++) {
    for (var x = 0; x < sw; x++) {
      var sum = 0.0;
      for (var yy = y * factor; yy < (y + 1) * factor; yy++) {
        for (var xx = x * factor; xx < (x + 1) * factor; xx++) {
          sum += g[min(yy, h - 1) * w + min(xx, w - 1)];
        }
      }
      out[y * sw + x] = sum / (factor * factor);
    }
  }
  return (luminance: out, width: sw, height: sh);
}

/// Keburaman 0 (tajam) sampai 1 (buram), cara Crété-Roffet dkk. 2007 ("The
/// blur effect"): foto diburamkan lagi dengan kotak 11 piksel, lalu dihitung
/// berapa bagian beda antarpiksel yang hilang. Foto yang sudah buram hampir
/// tidak berubah. Tidak seperti varians Laplacian, nilainya tidak ikut naik
/// di foto yang penuh rumput, daun, atau tanah gembur.
///
/// Dihitung juga per ubin 64 piksel. Foto dekat yang subjeknya tajam tetapi
/// latarnya kabur tetap lolos bila 10% ubin bertekstur yang paling tajam
/// jelas; +0,08 karena ubin tertajam foto mana pun memang lebih rendah dari
/// nilai seluruh foto.
///
/// [detail] adalah bagian ubin utuh yang bertekstur. Langit, dinding, atau
/// lensa tertutup jari hampir tidak punya.
({double blur, double detail}) _blurScore(
  Float32List g,
  int w,
  int h, {
  int tile = 64,
}) {
  const minGradient = 2.0;
  final tilesX = (w / tile).ceil(), tilesY = (h / tile).ceil();
  // Per ubin: beda asli dan beda yang hilang, mendatar lalu tegak.
  final sums = Float64List(tilesX * tilesY * 4);
  final counts = Int32List(tilesX * tilesY);
  final blurred = Float32List(w * h);

  for (final horizontal in const [true, false]) {
    _boxBlur(g, blurred, w, h, horizontal);
    final axis = horizontal ? 0 : 2;
    for (var y = 1; y < h; y++) {
      final tileRow = (y ~/ tile) * tilesX;
      for (var x = 1; x < w; x++) {
        final i = y * w + x;
        final j = horizontal ? i - 1 : i - w;
        final original = (g[i] - g[j]).abs();
        final reblurred = (blurred[i] - blurred[j]).abs();
        final t = tileRow + x ~/ tile;
        sums[t * 4 + axis] += original;
        if (original > reblurred) {
          sums[t * 4 + axis + 1] += original - reblurred;
        }
        if (horizontal) counts[t]++;
      }
    }
  }

  double blurOf(double dh, double lostH, double dv, double lostV) =>
      max(dh == 0 ? 1.0 : (dh - lostH) / dh, dv == 0 ? 1.0 : (dv - lostV) / dv);

  final total = Float64List(4);
  final tiles = <double>[];
  var fullTiles = 0;
  for (var t = 0; t < counts.length; t++) {
    for (var k = 0; k < 4; k++) {
      total[k] += sums[t * 4 + k];
    }
    final n = counts[t];
    if (n <= tile * tile / 2) continue;
    fullTiles++;
    // Ubin polos (langit, dinding) tidak bisa dinilai tajam atau buram.
    final gradient = (sums[t * 4] + sums[t * 4 + 2]) / (2 * n);
    if (gradient >= minGradient) {
      tiles.add(
        blurOf(sums[t * 4], sums[t * 4 + 1], sums[t * 4 + 2], sums[t * 4 + 3]),
      );
    }
  }
  final whole = blurOf(total[0], total[1], total[2], total[3]);
  final detail = fullTiles == 0 ? 0.0 : tiles.length / fullTiles;
  if (tiles.isEmpty) return (blur: whole, detail: detail);
  tiles.sort();
  final sharpest = tiles[(0.1 * (tiles.length - 1)).round()] + 0.08;
  return (blur: min(whole, sharpest), detail: detail);
}

/// Peluang 0–100 dari regresi logistik.
double _chance(
  double bias,
  Map<String, double> weights,
  Map<String, double> x,
) =>
    100 /
    (1 +
        exp(
          -weights.entries.fold(
            bias,
            (sum, weight) => sum + weight.value * x[weight.key]!,
          ),
        ));

/// Ukuran mentah untuk menyetel penilai buram dan pencahayaan dengan data uji
/// berlabel (test/photo_dataset_eval_test.dart).
Future<Map<String, double>?> photoFeatures(Uint8List bytes) => Isolate.run(() {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final full = _luminance(img.bakeOrientation(decoded), _analysisLongSide);
  return {
    'noise': _noiseSigma(full.luminance, full.width, full.height),
    ..._blurMeasures(full.luminance, full.width, full.height),
    ..._exposureMeasures(full.luminance, full.width, full.height),
  };
});

/// Kecerahan per bagian foto. Langit mendung di sepertiga atas sering putih
/// terbakar padahal isinya jelas, jadi bagian atas dan sisanya dipisah.
Map<String, double> _exposureMeasures(Float32List g, int w, int h) {
  ({
    double p02,
    double p05,
    double p50,
    double p95,
    double p98,
    double mean,
    double low,
    double high,
  })
  stats(int x0, int y0, int x1, int y1) {
    final histogram = Int32List(256);
    var sum = 0.0;
    for (var y = y0; y < y1; y++) {
      for (var x = x0; x < x1; x++) {
        final v = g[y * w + x];
        sum += v;
        histogram[v.round().clamp(0, 255)]++;
      }
    }
    final n = max(1, (x1 - x0) * (y1 - y0));
    double at(double p) {
      var seen = 0;
      for (var v = 0; v < 256; v++) {
        seen += histogram[v];
        if (seen >= p * n) return v.toDouble();
      }
      return 255;
    }

    var low = 0, high = 0;
    for (var v = 0; v <= 5; v++) {
      low += histogram[v];
    }
    for (var v = 250; v < 256; v++) {
      high += histogram[v];
    }
    return (
      p02: at(0.02),
      p05: at(0.05),
      p50: at(0.5),
      p95: at(0.95),
      p98: at(0.98),
      mean: sum / n,
      low: low / n,
      high: high / n,
    );
  }

  final all = stats(0, 0, w, h);
  final top = stats(0, 0, w, h ~/ 3);
  final rest = stats(0, h ~/ 3, w, h);
  final center = stats(w ~/ 4, h ~/ 4, w * 3 ~/ 4, h * 3 ~/ 4);
  return {
    'e_mean': all.mean,
    'e_p02': all.p02,
    'e_p05': all.p05,
    'e_p50': all.p50,
    'e_p95': all.p95,
    'e_p98': all.p98,
    'e_low': all.low,
    'e_high': all.high,
    'e_topHigh': top.high,
    'e_topP50': top.p50,
    'e_restHigh': rest.high,
    'e_restLow': rest.low,
    'e_restP50': rest.p50,
    'e_restP95': rest.p95,
    'e_centerP50': center.p50,
    'e_centerMean': center.mean,
    'e_centerHigh': center.high,
    'e_centerLow': center.low,
  };
}

/// [_axisBlur] di ukuran analisis (s1), setengahnya (s2), dan seperempatnya
/// (s4). Noise kamera di tempat redup terbaca tajam di s1, di s4 sudah rata.
/// Ubin ikut diperkecil supaya menutup bagian foto yang sama.
Map<String, double> _blurMeasures(Float32List g, int w, int h) {
  final out = <String, double>{};
  for (final (name, factor) in const [('s1', 1), ('s2', 2), ('s4', 4)]) {
    final scaled = factor == 1
        ? (luminance: g, width: w, height: h)
        : _shrink(g, w, h, factor);
    final tile = 64 ~/ factor;
    final measures = {
      ..._axisBlur(scaled.luminance, scaled.width, scaled.height, tile: tile),
      ..._coherence(scaled.luminance, scaled.width, scaled.height, tile: tile),
    };
    for (final MapEntry(:key, :value) in measures.entries) {
      out['${name}_$key'] = value;
    }
  }
  return out;
}

/// Seberapa searah garis-garis di foto, 0 (segala arah) sampai 1 (satu arah),
/// dari tensor struktur. Goyang mencoreng semuanya ke arah goyangan, termasuk
/// lampu yang jadi garis tipis bertepi tegas. Foto tajam biasa punya garis ke
/// segala arah. [coh] untuk seluruh foto, [cohMed] median ubin bertekstur.
Map<String, double> _coherence(Float32List g, int w, int h, {int tile = 64}) {
  final tilesX = (w / tile).ceil(), tilesY = (h / tile).ceil();
  final sums = Float64List(tilesX * tilesY * 3);
  var xx = 0.0, yy = 0.0, xy = 0.0;
  for (var y = 1; y < h - 1; y++) {
    final tileRow = (y ~/ tile) * tilesX;
    for (var x = 1; x < w - 1; x++) {
      final i = y * w + x;
      final gx = (g[i + 1] - g[i - 1]) / 2;
      final gy = (g[i + w] - g[i - w]) / 2;
      final t = (tileRow + x ~/ tile) * 3;
      sums[t] += gx * gx;
      sums[t + 1] += gy * gy;
      sums[t + 2] += gx * gy;
      xx += gx * gx;
      yy += gy * gy;
      xy += gx * gy;
    }
  }
  double of(double a, double b, double c) =>
      a + b == 0 ? 0 : sqrt((a - b) * (a - b) + 4 * c * c) / (a + b);
  // Ubin polos hanya berisi noise yang arahnya acak.
  final pixels = (tile * tile).toDouble();
  final tiles = <double>[
    for (var t = 0; t < tilesX * tilesY; t++)
      if ((sums[t * 3] + sums[t * 3 + 1]) / pixels >= 4)
        of(sums[t * 3], sums[t * 3 + 1], sums[t * 3 + 2]),
  ]..sort();
  return {
    'coh': of(xx, yy, xy),
    'cohMed': tiles.isEmpty ? 0 : tiles[tiles.length ~/ 2],
  };
}

/// Simpangan noise sensor (Immerkær 1996): selisih tiap piksel dengan
/// tetangganya yang tidak dijelaskan oleh garis atau permukaan halus.
double _noiseSigma(Float32List g, int w, int h) {
  var sum = 0.0;
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final i = y * w + x;
      final v =
          g[i - w - 1] -
          2 * g[i - w] +
          g[i - w + 1] -
          2 * g[i - 1] +
          4 * g[i] -
          2 * g[i + 1] +
          g[i + w - 1] -
          2 * g[i + w] +
          g[i + w + 1];
      sum += v.abs();
    }
  }
  return sqrt(pi / 2) * sum / (6 * (w - 2) * (h - 2));
}

/// Seperti [_blurScore], tapi dinilai di empat arah (mendatar, tegak, dan dua
/// diagonal). Goyang mengaburkan satu arah saja, sudutnya bisa miring, dan
/// arah lainnya tetap bergaris. Per arah: nilai seluruh foto, ubin tertajam
/// 3% dan 10%, lalu dirangkum jadi arah terburam (Max) dan tertajam (Min).
/// [edgeFrom]: beda antarpiksel yang dihitung sebagai garis kuat.
Map<String, double> _axisBlur(
  Float32List g,
  int w,
  int h, {
  int tile = 64,
  double edgeFrom = 8,
}) {
  const minGradient = 2.0;
  const radius = 5;
  const directions = [(1, 0), (0, 1), (1, 1), (1, -1)];
  final tilesX = (w / tile).ceil(), tilesY = (h / tile).ceil();
  final nTiles = tilesX * tilesY;
  // Per arah per ubin: beda asli dan beda yang hilang.
  final sums = Float64List(directions.length * nTiles * 2);
  final counts = Int32List(nTiles);
  final hv = Float64List(nTiles);
  final blurred = Float32List(w * h);
  var edges = 0.0;

  for (final (d, (dx, dy)) in directions.indexed) {
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var sum = 0.0;
        for (var k = -radius; k <= radius; k++) {
          final xx = (x + k * dx).clamp(0, w - 1);
          final yy = (y + k * dy).clamp(0, h - 1);
          sum += g[yy * w + xx];
        }
        blurred[y * w + x] = sum / (2 * radius + 1);
      }
    }
    for (var y = 1; y < h; y++) {
      final py = y - dy;
      if (py < 0 || py >= h) continue;
      final tileRow = (y ~/ tile) * tilesX;
      for (var x = 1; x < w - 1; x++) {
        final px = x - dx;
        final i = y * w + x, j = py * w + px;
        final original = (g[i] - g[j]).abs();
        final reblurred = (blurred[i] - blurred[j]).abs();
        final t = tileRow + x ~/ tile;
        final o = (d * nTiles + t) * 2;
        sums[o] += original;
        if (original > reblurred) sums[o + 1] += original - reblurred;
        if (d < 2) {
          hv[t] += original;
          if (original > edgeFrom) edges++;
        }
        if (d == 0) counts[t]++;
      }
    }
  }

  final textured = <int>[
    for (var t = 0; t < nTiles; t++)
      if (counts[t] > tile * tile / 2 && hv[t] / (2 * counts[t]) >= minGradient)
        t,
  ];
  double ratio(double sum, double lost) => sum == 0 ? 1.0 : (sum - lost) / sum;
  double at(List<double> values, double share) =>
      values.isEmpty ? 1.0 : values[(share * (values.length - 1)).round()];

  final whole = <double>[], peak = <double>[], sharp = <double>[];
  for (var d = 0; d < directions.length; d++) {
    var sum = 0.0, lost = 0.0;
    for (var t = 0; t < nTiles; t++) {
      sum += sums[(d * nTiles + t) * 2];
      lost += sums[(d * nTiles + t) * 2 + 1];
    }
    whole.add(ratio(sum, lost));
    final tiles = [
      for (final t in textured)
        ratio(sums[(d * nTiles + t) * 2], sums[(d * nTiles + t) * 2 + 1]),
    ]..sort();
    peak.add(at(tiles, 0.03));
    sharp.add(at(tiles, 0.1));
  }
  double most(List<double> v) => v.reduce(max);
  double least(List<double> v) => v.reduce(min);
  return {
    'wholeMax': most(whole),
    'wholeMin': least(whole),
    'peakMax': most(peak),
    'peakMin': least(peak),
    'sharpMax': most(sharp),
    'sharpMin': least(sharp),
    'edge': edges / (2.0 * w * h),
    'textured': nTiles == 0 ? 0 : textured.length / nTiles,
  };
}

/// Rata-rata 11 piksel searah [horizontal], tepi foto diulang.
void _boxBlur(Float32List src, Float32List dst, int w, int h, bool horizontal) {
  const radius = 5;
  final length = horizontal ? w : h;
  final lines = horizontal ? h : w;
  final step = horizontal ? 1 : w;
  for (var line = 0; line < lines; line++) {
    final start = horizontal ? line * w : line;
    double at(int k) => src[start + k.clamp(0, length - 1) * step];
    var sum = 0.0;
    for (var k = -radius; k <= radius; k++) {
      sum += at(k);
    }
    for (var k = 0; k < length; k++) {
      dst[start + k * step] = sum / (2 * radius + 1);
      sum += at(k + radius + 1) - at(k - radius);
    }
  }
}

class CnnResult {
  const CnnResult(this.probabilities);

  final Map<SignCategory, double> probabilities;

  MapEntry<SignCategory, double> get _top =>
      probabilities.entries.reduce((a, b) => a.value >= b.value ? a : b);

  SignCategory get category => _top.key;
  double get confidence => _top.value;
  bool get isConfident => confidence >= imageConfidenceThreshold;
}

/// Klasifikasi isi foto memakai model CNN TFLite hasil `tool/train_cnn.py`.
class CnnClassifier {
  CnnClassifier._(this._interpreter, this._labels);

  final Interpreter _interpreter;
  final List<SignCategory> _labels;

  /// `null` bila model belum dilatih dan dipasang di `assets/models/`.
  static Future<CnnClassifier?> load() async {
    try {
      final labelText = await rootBundle.loadString(cnnLabelsAsset);
      final labels = [
        for (final line in labelText.split('\n')) ?SignCategory.fromCode(line),
      ];
      final interpreter = await Interpreter.fromAsset(cnnModelAsset);
      final outputs = interpreter.getOutputTensor(0).shape.last;
      if (labels.isEmpty || outputs != labels.length) {
        interpreter.close();
        return null;
      }
      return CnnClassifier._(interpreter, labels);
    } catch (_) {
      return null;
    }
  }

  CnnResult classify(Float32List input) {
    final output = Float32List(_labels.length);
    _interpreter.run(input.buffer.asUint8List(), output.buffer);
    return CnnResult({
      for (final (index, label) in _labels.indexed) label: output[index],
    });
  }

  void close() => _interpreter.close();
}
