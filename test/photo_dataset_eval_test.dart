// Menilai photo_analyzer dengan kumpulan foto berlabel di luar repo, mis.
// blur dataset Kwentar (CC0): folder sharp, defocused_blurred, motion_blurred.
//
//   $env:EWS_DATA_UJI = 'D:\FLUTTER\data_uji\kwentar'
//   flutter test test/photo_dataset_eval_test.dart
//
// Tanpa EWS_DATA_UJI tes ini dilewati, jadi CI tidak terpengaruh. Hasil per
// foto disimpan ke hasil.csv di folder data itu.
//
// EWS_SEPERTI_APLIKASI=1 memproses tiap foto seperti image_picker di menu
// Lapor dulu (sisi panjang paling 1600 piksel, JPEG kualitas 85). Foto asli
// HP 3000–4000 piksel jauh lebih bersih dari noise setelah diperkecil ke
// ukuran analisis, jadi angka tanpa ini terlalu optimis.
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ews/analysis/photo_analyzer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

const _parallel = 6;

/// Sama dengan pickImage(maxWidth: 1600, maxHeight: 1600, imageQuality: 85)
/// di report_screen.dart.
Future<Uint8List> _likePicker(Uint8List bytes) => Isolate.run(() {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;
  final photo = img.bakeOrientation(decoded);
  final scale =
      1600 / (photo.width > photo.height ? photo.width : photo.height);
  final resized = scale >= 1
      ? photo
      : img.copyResize(
          photo,
          width: (photo.width * scale).round(),
          height: (photo.height * scale).round(),
          interpolation: img.Interpolation.linear,
        );
  return img.encodeJpg(resized, quality: 85);
});

void main() {
  final root = Platform.environment['EWS_DATA_UJI'];

  test(
    'nilai photo_analyzer pada data uji berlabel',
    () async {
      final folders =
          Directory(root!).listSync().whereType<Directory>().toList()
            ..sort((a, b) => a.path.compareTo(b.path));

      final rows = <String>[
        'label,file,issues,median,clipped,detail,sharpness,fine',
      ];
      final summary = StringBuffer();
      // EWS_FITUR=1 juga menyimpan ukuran mentah ke fitur.csv untuk menyetel
      // ambang.
      final exportFeatures = Platform.environment['EWS_FITUR'] == '1';
      final likeApp = Platform.environment['EWS_SEPERTI_APLIKASI'] == '1';
      final featureRows = <String>[];
      List<String>? featureNames;

      for (final folder in folders) {
        final label = folder.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
        final files =
            folder
                .listSync()
                .whereType<File>()
                .where(
                  (f) => RegExp(
                    r'\.(jpe?g|png)$',
                    caseSensitive: false,
                  ).hasMatch(f.path),
                )
                .toList()
              ..sort((a, b) => a.path.compareTo(b.path));

        final counts = <String, int>{};
        for (var i = 0; i < files.length; i += _parallel) {
          final batch = files.skip(i).take(_parallel).toList();
          final bytes = await Future.wait([
            for (final file in batch)
              file.readAsBytes().then(
                (raw) => likeApp ? _likePicker(raw) : Future.value(raw),
              ),
          ]);
          final results = await Future.wait(bytes.map(preparePhoto));
          if (exportFeatures) {
            final measured = await Future.wait(bytes.map(photoFeatures));
            for (final (j, values) in measured.indexed) {
              if (values == null) continue;
              featureNames ??= values.keys.toList();
              featureRows.add(
                [
                  label,
                  batch[j].uri.pathSegments.last,
                  for (final key in featureNames)
                    values[key]!.toStringAsFixed(4),
                ].join(','),
              );
            }
          }
          for (final (j, prepared) in results.indexed) {
            final name = batch[j].uri.pathSegments.last;
            final q = prepared?.quality;
            final verdict = q == null
                ? 'tidak terbaca'
                : q.isClear
                ? 'jelas'
                : q.issueText;
            counts[verdict] = (counts[verdict] ?? 0) + 1;
            rows.add(
              q == null
                  ? '$label,$name,tidak terbaca,,,,,'
                  : [
                      label,
                      name,
                      verdict.replaceAll(',', ';'),
                      q.median.round(),
                      q.clipped.toStringAsFixed(3),
                      q.detail.toStringAsFixed(2),
                      q.sharpness.toStringAsFixed(1),
                      q.fineSharpness.toStringAsFixed(1),
                    ].join(','),
            );
          }
        }

        summary.writeln('$label (${files.length} foto)');
        final sorted = counts.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        for (final MapEntry(:key, :value) in sorted) {
          final share = (100 * value / files.length).toStringAsFixed(0);
          summary.writeln('  $key: $value ($share%)');
        }
      }

      File('$root/hasil.csv').writeAsStringSync(rows.join('\n'));
      if (featureNames case final names?) {
        File('$root/fitur.csv').writeAsStringSync(
          ['label,file,${names.join(',')}', ...featureRows].join('\n'),
        );
      }
      // ignore: avoid_print
      print(summary);
    },
    skip: root == null ? 'EWS_DATA_UJI belum diisi' : false,
    timeout: const Timeout(Duration(hours: 1)),
  );
}
