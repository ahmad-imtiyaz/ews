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

// Median foto asli paling rendah 40 (tajuk hutan, isinya tetap jelas),
// diredupkan setengah 39 ke atas. Foto malam 3–20.
const _darkMedianBelow = 30.0;

// Foto asli: median paling tinggi 126, putih terbakar paling banyak 6%. Foto
// terlalu terang: median 203 ke atas atau 13–61% terbakar.
const _brightMedianFrom = 200.0;
const _clippedFrom = 0.25;

// Ubin bertekstur foto asli paling sedikit 61% (foto tajam blur dataset
// Kwentar: 5% terbawah 30%), foto tertutup jari dan dinding polos 0%. Foto
// goyang di ruang redup bisa 3–5%, dan itu harus disebut buram.
const _plainDetailBelow = 0.02;

// Titik hitam foto asli paling tinggi 61, foto berkabut 163 ke atas dengan
// kontras 29–70. Kontras foto asli paling rendah 96.
const _hazeBlackFrom = 120.0;
const _hazeContrast = 80.0;

// Hanya untuk membedakan foto polos (dinding, lensa tertutup jari) dari foto
// buram: foto polos yang tidak buram bernilai 62 ke atas di ukuran lama
// [_blurScore]. Foto asli 76–84.
const _plainSharpFrom = 62.0;

// Penilai buram: regresi logistik atas ukuran [_axisBlur] di tiga ukuran
// foto, dilatih 24 November 2026 dengan blur dataset Kwentar (CC0): 277
// adegan dari puluhan HP, masing-masing difoto tajam, tidak fokus, dan
// goyang. Diuji silang per adegan: foto tajam yang disebut buram 3,6%, tidak
// fokus tertangkap 96%, goyang tertangkap 91% (aturan sebelumnya 6,9%, 91%,
// 85%). Buram ringan sengaja dibiarkan lolos sebagai jelas. Yang masih sering
// lolos: goyang di rumput atau daun yang sangat rapat, dan permukaan polos
// yang luas (dinding, plastik) kadang terbaca buram. Untuk melatih ulang
// lihat tool/fit_blur.py.
const _blurBias = -7.3868;
const _blurWeights = {
  's1_peakMax': 2.2476,
  's1_peakMin': 1.6390,
  's2_wholeMax': 5.3981,
  's2_wholeMin': 3.0263,
  's2_peakMax': 3.9474,
  's2_peakMin': 2.7619,
  's2_edge': -3.8540,
  's4_wholeMax': 4.2621,
  's4_wholeMin': 2.7079,
  's4_peakMax': 5.1453,
  's4_peakMin': 4.0945,
};

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
  bool get isDark => median < _darkMedianBelow;
  bool get isTooBright =>
      !isDark && (median >= _brightMedianFrom || clipped >= _clippedFrom);

  /// Hampir tanpa garis, tapi bukan karena buram: nilai tajamnya cuma dari
  /// noise kamera. Lensa tertutup jari, dinding, atau tanah polos.
  bool get isPlain =>
      detail < _plainDetailBelow && fineSharpness >= _plainSharpFrom;

  /// Pudar seperti tertutup kabut atau lensa berembun.
  bool get isHazy => blackLevel >= _hazeBlackFrom && contrast < _hazeContrast;

  /// Foto gelap disebut gelap saja karena itu penyebabnya. Foto terlalu terang
  /// juga tampak pudar, tapi cukup disebut terlalu terang.
  bool get isUnclear => !isDark && (isPlain || (isHazy && !isTooBright));

  /// Foto gelap dan foto polos tidak dinilai buram: ukurannya terkacau noise.
  bool get _sharpnessCounts => !isDark && !isUnclear;
  bool get isBlurry => _sharpnessCounts && sharpness < _blurBelow;

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
      '${fineSharpness.toStringAsFixed(1)})';
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

/// Ukuran ketajaman mentah untuk menyetel [_blurWeights] dengan data uji
/// berlabel (test/photo_dataset_eval_test.dart).
Future<Map<String, double>?> blurFeatures(Uint8List bytes) => Isolate.run(() {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final full = _luminance(img.bakeOrientation(decoded), _analysisLongSide);
  return {
    'noise': _noiseSigma(full.luminance, full.width, full.height),
    ..._blurMeasures(full.luminance, full.width, full.height),
  };
});

/// [_axisBlur] di ukuran analisis (s1), setengahnya (s2), dan seperempatnya
/// (s4). Noise kamera di tempat redup terbaca tajam di s1, di s4 sudah rata.
/// Ubin ikut diperkecil supaya menutup bagian foto yang sama.
Map<String, double> _blurMeasures(Float32List g, int w, int h) => {
  for (final (name, factor) in const [('s1', 1), ('s2', 2), ('s4', 4)])
    for (final MapEntry(:key, :value)
        in (factor == 1
                ? _axisBlur(g, w, h)
                : switch (_shrink(g, w, h, factor)) {
                    final small => _axisBlur(
                      small.luminance,
                      small.width,
                      small.height,
                      tile: 64 ~/ factor,
                    ),
                  })
            .entries)
      '${name}_$key': value,
};

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
