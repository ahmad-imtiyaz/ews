import 'dart:io';

import 'package:ews/analysis/photo_collage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  late Directory folder;

  setUp(() => folder = Directory.systemTemp.createTempSync('kolase_'));
  tearDown(() => folder.deleteSync(recursive: true));

  List<String> photos(int count) => [
    for (var i = 0; i < count; i++)
      (File('${folder.path}/foto_$i.jpg')..writeAsBytesSync(
            img.encodeJpg(
              img.fill(
                img.Image(width: 800 + i * 100, height: 600),
                color: img.ColorRgb8(40 * i, 120, 200),
              ),
            ),
          ))
          .path,
  ];

  test(
    'tiga foto menjadi satu gambar: satu lebar di atas, dua di bawah',
    () async {
      final path = await buildCollage(photos(3));
      final collage = img.decodeJpg(File(path).readAsBytesSync())!;

      expect(collage.width, 1600);
      // 1600 x 9/16 di atas, (1600 - 8) / 2 x 3/4 di bawah, celah 8.
      expect(collage.height, 900 + 8 + 597);
      File(path).deleteSync();
    },
  );

  test('lima foto tetap satu gambar', () async {
    final path = await buildCollage(photos(5));
    final collage = img.decodeJpg(File(path).readAsBytesSync())!;

    expect(collage.width, 1600);
    expect(collage.height, greaterThan(800));
    File(path).deleteSync();
  });
}
