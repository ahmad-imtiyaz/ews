import 'dart:io';
import 'dart:typed_data';

import 'package:ews/analysis/photo_analyzer.dart';
import 'package:ews/analysis/report.dart';
import 'package:ews/analysis/sign_category.dart';
import 'package:ews/analysis/text_analyzer.dart';
import 'package:flutter_test/flutter_test.dart';

ReportPhoto _photo({double sharpness = 80, CnnResult? cnn}) => ReportPhoto(
  path: 'foto.jpg',
  bytes: Uint8List(0),
  quality: PhotoQuality(
    width: 1600,
    height: 1200,
    brightness: 120,
    sharpness: sharpness,
  ),
  cnn: cnn,
);

void main() {
  test('pesan menyebut jumlah foto dan foto yang buram', () {
    final report = ReportAnalysis(
      time: DateTime(2026, 11, 6, 10, 42),
      story: 'lemah bengkah',
      photos: [_photo(), _photo(sharpness: 40), _photo()],
    );

    final message = buildReportMessage(report, 'Tanah retak.');

    expect(message, contains('Foto: 3 terlampir (foto 2 kemungkinan buram)'));
    expect(message, contains('Tanah retak.'));
  });

  test('satu foto yang cocok cukup untuk saling mendukung', () {
    final analyzer = TextAnalyzer.fromCsv(
      dictionaryCsv: File(dictionaryAsset).readAsStringSync(),
      examplesCsv: File(examplesAsset).readAsStringSync(),
    );
    final text = analyzer.analyze('lemahe bengkah dawa neng pinggir dalan');
    const retakan = CnnResult({
      SignCategory.retakan: 0.9,
      SignCategory.tidakRelevan: 0.1,
    });
    const sekitar = CnnResult({
      SignCategory.retakan: 0.2,
      SignCategory.tidakRelevan: 0.8,
    });

    ReportAnalysis report(List<ReportPhoto> photos) => ReportAnalysis(
      time: DateTime(2026),
      story: text.original,
      text: text,
      photos: photos,
    );

    expect(text.category, SignCategory.retakan);
    expect(
      report([_photo(cnn: sekitar), _photo(cnn: retakan)]).match,
      MatchOutcome.supported,
    );
    expect(report([_photo(cnn: sekitar)]).match, MatchOutcome.different);
    expect(report([_photo(), _photo()]).match, MatchOutcome.noCnn);
  });
}
