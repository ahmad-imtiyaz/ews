import 'dart:math';
import 'dart:typed_data';

import 'package:ews/analysis/photo_analyzer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

// Foto buatan 2048 x 1536: ratusan bulatan bertepi tegas, ditambah sedikit
// noise seperti sensor kamera. Buram dinyatakan dalam persen lebar foto, sama
// dengan uji foto lapangan yang dipakai menentukan ambang.
const _w = 2048, _h = 1536;

Float32List _texture() {
  final rnd = Random(1);
  final g = Float32List(_w * _h)..fillRange(0, _w * _h, 128);
  for (var n = 0; n < 1500; n++) {
    final cx = rnd.nextInt(_w), cy = rnd.nextInt(_h), r = 6 + rnd.nextInt(55);
    final value = 30.0 + rnd.nextInt(190);
    for (var y = max(0, cy - r); y < min(_h, cy + r); y++) {
      for (var x = max(0, cx - r); x < min(_w, cx + r); x++) {
        if ((x - cx) * (x - cx) + (y - cy) * (y - cy) <= r * r) {
          g[y * _w + x] = value;
        }
      }
    }
  }
  return g;
}

/// Rata-rata [kernel] sepanjang (dx, dy), tepi diulang.
Float32List _smear(Float32List g, List<double> kernel, int dx, int dy) {
  final r = kernel.length ~/ 2;
  final out = Float32List(_w * _h);
  for (var y = 0; y < _h; y++) {
    for (var x = 0; x < _w; x++) {
      var s = 0.0;
      for (var k = -r; k <= r; k++) {
        final xx = (x + k * dx).clamp(0, _w - 1);
        final yy = (y + k * dy).clamp(0, _h - 1);
        s += kernel[k + r] * g[yy * _w + xx];
      }
      out[y * _w + x] = s;
    }
  }
  return out;
}

Float32List _gaussian(Float32List g, double sigma) {
  final r = (3 * sigma).ceil();
  final k = [for (var i = -r; i <= r; i++) exp(-i * i / (2 * sigma * sigma))];
  final sum = k.reduce((a, b) => a + b);
  final normalized = [for (final v in k) v / sum];
  return _smear(_smear(g, normalized, 1, 0), normalized, 0, 1);
}

Float32List _motion(Float32List g, int length, {bool diagonal = false}) {
  final steps = diagonal ? (length / sqrt2).round() | 1 : length | 1;
  return _smear(g, List.filled(steps, 1 / steps), 1, diagonal ? 1 : 0);
}

Float32List _sharpCenter(Float32List sharp, Float32List blurred) {
  final out = Float32List.fromList(blurred);
  for (var y = (_h * 0.325).round(); y < (_h * 0.675).round(); y++) {
    for (var x = (_w * 0.325).round(); x < (_w * 0.675).round(); x++) {
      out[y * _w + x] = sharp[y * _w + x];
    }
  }
  return out;
}

/// [noise] simpangan terbesar noise sensor. 4 untuk foto biasa, sekitar 22
/// untuk foto di tempat redup.
img.Image _image(Float32List g, {double noise = 4}) {
  final rnd = Random(2);
  final image = img.Image(width: _w, height: _h);
  for (var y = 0; y < _h; y++) {
    for (var x = 0; x < _w; x++) {
      final n = (rnd.nextDouble() + rnd.nextDouble() - 1) * noise;
      final v = (g[y * _w + x] + n).round().clamp(0, 255);
      image.setPixelRgb(x, y, v, v, v);
    }
  }
  return image;
}

Future<PhotoQuality> _quality(Float32List g, {double noise = 4}) async {
  final jpeg = img.encodeJpg(_image(g, noise: noise), quality: 88);
  return (await preparePhoto(Uint8List.fromList(jpeg)))!.quality;
}

void main() {
  late Float32List sharp;
  setUpAll(() => sharp = _texture());

  test('foto tajam tidak dianggap buram', () async {
    final quality = await _quality(sharp);
    expect(quality.isBlurry, isFalse, reason: '${quality.sharpness}');
    expect(quality.issues, isEmpty);
  });

  test('buram sedang (sigma 0,2% lebar) tertangkap', () async {
    final quality = await _quality(_gaussian(sharp, _w * 0.002));
    expect(quality.isBlurry, isTrue, reason: '${quality.sharpness}');
    expect(quality.issues, [PhotoIssue.blurry]);
  });

  test('sedikit tidak fokus disebut agak buram', () async {
    final quality = await _quality(_gaussian(sharp, _w * 0.0007));
    expect(quality.issues, [PhotoIssue.slightlyBlurry], reason: '$quality');
  });

  // Seperti foto nyata yang dulu lolos: goyang berat di dalam rumah. Noise
  // kamera membuatnya terbaca tajam di ukuran biasa.
  test('foto goyang di tempat redup tetap disebut buram', () async {
    final shaken = _motion(sharp, (_w * 0.03).round());
    final quality = await _quality(
      Float32List.fromList([for (final v in shaken) v * 0.75]),
      noise: 22,
    );
    expect(quality.issues, [PhotoIssue.blurry], reason: '$quality');
  });

  test('foto tajam di tempat redup dengan noise tidak disebut buram', () async {
    final quality = await _quality(
      Float32List.fromList([for (final v in sharp) v * 0.75]),
      noise: 22,
    );
    expect(quality.isBlurry, isFalse, reason: '$quality');
  });

  test('foto malam disebut gelap saja, bukan buram', () async {
    final quality = await _quality(
      Float32List.fromList([for (final v in sharp) v * 0.12]),
    );
    expect(quality.issues, [PhotoIssue.dark], reason: '$quality');
  });

  test('foto yang diredupkan tetap jelas', () async {
    final quality = await _quality(
      Float32List.fromList([for (final v in sharp) v * 0.55]),
    );
    expect(quality.issues, isEmpty, reason: '$quality');
  });

  test('foto terlalu terang', () async {
    final quality = await _quality(
      Float32List.fromList([for (final v in sharp) v * 2 + 60]),
    );
    expect(quality.issues, [PhotoIssue.bright], reason: '$quality');
  });

  test('foto berkabut disebut tidak jelas', () async {
    final quality = await _quality(
      Float32List.fromList([for (final v in sharp) v * 0.3 + 160]),
    );
    expect(quality.issues, [PhotoIssue.unclear], reason: '$quality');
  });

  test('lensa tertutup atau dinding polos disebut tidak jelas', () async {
    final quality = await _quality(
      Float32List(_w * _h)..fillRange(0, _w * _h, 90),
    );
    expect(quality.issues, [PhotoIssue.unclear], reason: '$quality');
  });

  test('foto kecil disebut resolusi rendah', () async {
    final small = img.copyResize(_image(sharp), width: 400);
    final jpeg = img.encodeJpg(small, quality: 88);
    final quality = (await preparePhoto(Uint8List.fromList(jpeg)))!.quality;
    expect(quality.issues, [PhotoIssue.lowResolution], reason: '$quality');
  });

  test('foto goyang mendatar dan miring tertangkap', () async {
    final length = (_w * 0.006).round();
    final flat = await _quality(_motion(sharp, length));
    final diagonal = await _quality(_motion(sharp, length, diagonal: true));
    expect(flat.isBlurry, isTrue, reason: '${flat.sharpness}');
    expect(diagonal.isBlurry, isTrue, reason: '${diagonal.sharpness}');
  });

  test('foto dekat: subjek tajam, latar kabur, tidak dianggap buram', () async {
    final background = _gaussian(sharp, _w * 0.006);
    final quality = await _quality(_sharpCenter(sharp, background));
    expect(quality.isBlurry, isFalse, reason: '$quality');
  });
}
