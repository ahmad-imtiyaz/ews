import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import 'sign_category.dart';

const cnnModelAsset = 'assets/models/cnn_longsor.tflite';
const cnnLabelsAsset = 'assets/models/labels.txt';
const cnnInputSize = 224;
const imageConfidenceThreshold = 0.6;

// Ambang awal kelayakan foto. Perlu diuji ulang dengan foto lapangan.
const _minShortSide = 320;
const _darkBelow = 45.0;
const _brightAbove = 215.0;
const _blurBelow = 60.0;

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

  /// Varians Laplacian pada versi kecil foto. Makin kecil makin buram.
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

  final small = img.grayscale(img.copyResize(photo, width: 400));
  final w = small.width;
  final h = small.height;
  final luminance = Float64List(w * h);
  var sum = 0.0;
  for (final pixel in small) {
    final value = pixel.r.toDouble();
    luminance[pixel.y * w + pixel.x] = value;
    sum += value;
  }

  var lapSum = 0.0;
  var lapSquares = 0.0;
  var count = 0;
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final i = y * w + x;
      final lap =
          luminance[i - 1] +
          luminance[i + 1] +
          luminance[i - w] +
          luminance[i + w] -
          4 * luminance[i];
      lapSum += lap;
      lapSquares += lap * lap;
      count++;
    }
  }
  final lapMean = count == 0 ? 0.0 : lapSum / count;
  final sharpness = count == 0 ? 0.0 : lapSquares / count - lapMean * lapMean;

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
      brightness: sum / (w * h),
      sharpness: sharpness,
    ),
    input,
  );
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
