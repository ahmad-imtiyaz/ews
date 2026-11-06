import 'dart:io';

import 'package:ews/analysis/sign_category.dart';
import 'package:ews/analysis/text_analyzer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late TextAnalyzer analyzer;

  setUpAll(() {
    analyzer = TextAnalyzer.fromCsv(
      dictionaryCsv: File(dictionaryAsset).readAsStringSync(),
      examplesCsv: File(examplesAsset).readAsStringSync(),
      placesCsv: File(placesAsset).readAsStringSync(),
    );
  });

  test('contoh dokumen dibakukan dan diklasifikasikan', () {
    final result = analyzer.analyze(
      'lemah e bengkah neng mburi omah pak RT, saiki tambah amba',
    );

    expect(
      result.standardized,
      'Tanahnya retak di belakang rumah Pak RT, sekarang makin lebar.',
    );
    expect(result.category, SignCategory.retakan);
    expect(result.place, 'belakang rumah Pak RT');
    expect(result.urgency, Urgency.tinggi);
  });

  test('akhiran -e menempel dibakukan menjadi -nya', () {
    final result = analyzer.analyze('banyune metu saka pereng');
    expect(result.standardized, 'Airnya keluar dari lereng.');
    expect(result.category, SignCategory.rembesan);
  });

  test('penyangkalan tetap dipertahankan', () {
    final result = analyzer.analyze('lemahe ora bengkah');
    expect(result.standardized, 'Tanahnya tidak retak.');
    expect(result.features, contains('tidak_retak'));
  });

  test('nama yang tidak ada di kamus tetap seperti aslinya', () {
    final result = analyzer.analyze('wit neng omah Pak Darto doyong');
    expect(result.standardized, 'Pohon di rumah Pak Darto miring.');
    expect(result.category, SignCategory.pohonMiring);
  });

  test('bahasa Indonesia biasa tetap dikenali', () {
    final result = analyzer.analyze('terdengar suara gemuruh dari bukit');
    expect(result.category, SignCategory.gemuruh);
  });

  test('kata yang tidak dikenal sama sekali tidak dipaksa masuk kategori', () {
    final result = analyzer.analyze('qwerty asdf');
    expect(result.category, isNull);
    expect(result.isConfident, isFalse);
  });

  test('huruf acak dirapikan dan kata Pekalongan dibakukan', () {
    final result = analyzer.analyze(
      'lUr iNi dAlAn nAng tIkUnGaN kAlIbEnInG aNa lEmAh lOnGsOr nUtUpI '
      'aSpAl, mEnDiNg mUtEr bAe dIsIt sOaLe lIcIn bAnGeT.',
    );

    expect(
      result.standardized,
      'Ini jalan di tikungan Kalibening ada tanah longsor menutupi aspal, '
      'lebih baik memutar saja dulu soalnya licin sekali.',
    );
    expect(result.category, SignCategory.longsoran);
    expect(result.place, 'tikungan Kalibening');
    expect(result.urgency, Urgency.tinggi);
  });

  test('caps lock tetap dibakukan, singkatan pendek tetap kapital', () {
    expect(
      analyzer.analyze('LEMAHE BENGKAH NENG MBURI OMAH').standardized,
      'Tanahnya retak di belakang rumah.',
    );
    expect(
      analyzer.analyze('lapor ke BPBD, tanah retak').standardized,
      'Lapor ke BPBD, tanah retak.',
    );
  });
}
