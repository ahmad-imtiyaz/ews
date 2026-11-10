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

// Ambang awal kecerahan dan resolusi. Perlu diuji ulang dengan foto lapangan.
const _minShortSide = 320;
const _darkBelow = 45.0;
const _brightAbove = 215.0;

// Ambang buram diuji dengan 19 foto lapangan dari Kajian Pemetaan Bencana Desa
// Lumeneng 2024, masing-masing juga diburamkan buatan lalu disimpan ulang
// sebagai JPEG. Foto asli bernilai 73–83 (satu yang memang buram 61,6), buram
// sedang (sigma 0,2% lebar foto) paling tinggi 58, goyang (gerak 0,6% lebar)
// paling tinggi 60,4. Di bawah 62 semua versi buram sedang, berat, dan goyang
// tertangkap; 17 dari 19 foto dekat yang subjeknya tajam dan latarnya kabur
// tetap lolos. Ukuran lama (varians Laplacian di lebar 400, ambang 60)
// meloloskan 15 dari 19 buram sedang dan semua foto goyang.
const _blurBelow = 62.0;

/// Sisi panjang versi kecil untuk mengukur ketajaman, kira-kira ukuran foto
/// saat dilihat petugas di layar HP. Memperkecil lebih jauh menyembunyikan
/// buram: goyang 20 piksel di foto 4000 piksel tinggal 2 piksel di lebar 400.
const _analysisLongSide = 1024;

class PhotoQuality {
  const PhotoQuality({
    required this.width,
    required this.height,
    required this.brightness,
    required this.sharpness,
  });

  final int width;
  final int height;

  /// Rata-rata kecerahan 0–255.
  final double brightness;

  /// 0–100, makin kecil makin buram. Lihat [_blurScore].
  final double sharpness;

  bool get isLowResolution => (width < height ? width : height) < _minShortSide;
  bool get isDark => brightness < _darkBelow;
  bool get isTooBright => brightness > _brightAbove;
  bool get isBlurry => sharpness < _blurBelow;

  List<String> get issues => [
    if (isBlurry) 'Kemungkinan buram',
    if (isDark) 'Terlalu gelap',
    if (isTooBright) 'Terlalu terang',
    if (isLowResolution) 'Resolusi rendah',
  ];

  bool get isClear => issues.isEmpty;
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
  for (final value in luminance) {
    sum += value;
  }

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
      sharpness: (1 - _blurScore(luminance, width, height)) * 100,
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
double _blurScore(Float32List g, int w, int h) {
  const tile = 64;
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
  for (var t = 0; t < counts.length; t++) {
    for (var k = 0; k < 4; k++) {
      total[k] += sums[t * 4 + k];
    }
    final n = counts[t];
    // Ubin polos (langit, dinding) tidak bisa dinilai tajam atau buram.
    final gradient = (sums[t * 4] + sums[t * 4 + 2]) / (2 * max(1, n));
    if (n > tile * tile / 2 && gradient >= minGradient) {
      tiles.add(
        blurOf(sums[t * 4], sums[t * 4 + 1], sums[t * 4 + 2], sums[t * 4 + 3]),
      );
    }
  }
  final whole = blurOf(total[0], total[1], total[2], total[3]);
  if (tiles.isEmpty) return whole;
  tiles.sort();
  final sharpest = tiles[(0.1 * (tiles.length - 1)).round()];
  return min(whole, sharpest + 0.08);
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
