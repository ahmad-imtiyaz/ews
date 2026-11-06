import 'dart:io';
import 'dart:isolate';

import 'package:image/image.dart' as img;

const _width = 1600;
const _gap = 8;
const _labelSize = 64;

/// Foto per baris. Lima foto masih cukup besar untuk dilihat petugas.
List<int> _rowsFor(int count) => switch (count) {
  1 => const [1],
  2 => const [2],
  3 => const [1, 2],
  4 => const [2, 2],
  _ => const [2, 3],
};

/// Menggabungkan beberapa foto menjadi satu gambar bernomor, supaya laporan
/// masuk ke WhatsApp sebagai satu pesan dengan satu keterangan.
/// Mengembalikan path file JPEG di folder sementara aplikasi.
Future<String> buildCollage(List<String> paths) =>
    Isolate.run(() => _build(paths));

String _build(List<String> paths) {
  final photos = [
    for (final path in paths)
      if (img.decodeImage(File(path).readAsBytesSync()) case final decoded?)
        img.bakeOrientation(decoded),
  ];
  if (photos.isEmpty) throw StateError('Tidak ada foto yang bisa dibaca.');

  final rows = _rowsFor(photos.length.clamp(1, 5));
  final heights = [
    for (final count in rows)
      ((_width - _gap * (count - 1)) / count * (count == 1 ? 0.5625 : 0.75))
          .round(),
  ];
  final height = heights.fold(0, (a, b) => a + b) + _gap * (heights.length - 1);

  final canvas = img.Image(width: _width, height: height);
  img.fill(canvas, color: img.ColorRgb8(255, 255, 255));

  var index = 0;
  var y = 0;
  for (final (row, count) in rows.indexed) {
    final cellWidth = ((_width - _gap * (count - 1)) / count).floor();
    final cellHeight = heights[row];
    for (var column = 0; column < count && index < photos.length; column++) {
      final x = column * (cellWidth + _gap);
      img.compositeImage(
        canvas,
        _cover(photos[index], cellWidth, cellHeight),
        dstX: x,
        dstY: y,
      );
      _label(canvas, index + 1, x, y);
      index++;
    }
    y += cellHeight + _gap;
  }

  final file = File(
    '${Directory.systemTemp.path}/laporan_gabungan_'
    '${DateTime.now().millisecondsSinceEpoch}.jpg',
  );
  file.writeAsBytesSync(img.encodeJpg(canvas, quality: 85));
  return file.path;
}

/// Potong tengah agar foto memenuhi sel tanpa gepeng.
img.Image _cover(img.Image photo, int width, int height) {
  final scale = [
    width / photo.width,
    height / photo.height,
  ].reduce((a, b) => a > b ? a : b);
  final resized = img.copyResize(
    photo,
    width: (photo.width * scale).ceil(),
    height: (photo.height * scale).ceil(),
  );
  return img.copyCrop(
    resized,
    x: (resized.width - width) ~/ 2,
    y: (resized.height - height) ~/ 2,
    width: width,
    height: height,
  );
}

void _label(img.Image canvas, int number, int x, int y) {
  final left = x + 12;
  final top = y + 12;
  img.fillRect(
    canvas,
    x1: left,
    y1: top,
    x2: left + _labelSize,
    y2: top + _labelSize,
    color: img.ColorRgb8(255, 255, 255),
    radius: 12,
  );
  img.drawString(
    canvas,
    '$number',
    font: img.arial48,
    x: left + 19,
    y: top + 8,
    color: img.ColorRgb8(17, 17, 17),
  );
}
