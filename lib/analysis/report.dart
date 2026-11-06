import 'dart:typed_data';

import 'photo_analyzer.dart';
import 'sign_category.dart';
import 'text_analyzer.dart';

class ReportLocation {
  const ReportLocation(this.latitude, this.longitude, this.accuracy);

  final double latitude;
  final double longitude;

  /// Perkiraan galat GPS dalam meter.
  final double accuracy;

  String get coordinates =>
      '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';
  String get mapsUrl =>
      'https://maps.google.com/?q=${latitude.toStringAsFixed(6)},'
      '${longitude.toStringAsFixed(6)}';
}

enum MatchOutcome {
  supported('Teks dan foto saling mendukung'),
  different('Teks dan foto berbeda, perlu dicek petugas'),
  uncertain('Belum bisa dicocokkan, salah satu hasil belum yakin'),
  noCnn('Foto belum dianalisis CNN, petugas memeriksa fotonya'),
  textOnly('Hanya keterangan teks, tanpa foto'),
  photoOnly('Hanya foto, tanpa keterangan');

  const MatchOutcome(this.label);

  final String label;
}

class ReportPhoto {
  const ReportPhoto({
    required this.path,
    required this.bytes,
    this.quality,
    this.cnn,
  });

  final String path;
  final Uint8List bytes;

  /// `null` bila file foto tidak bisa dibaca.
  final PhotoQuality? quality;

  /// `null` bila model CNN belum dipasang atau foto tidak bisa dibaca.
  final CnnResult? cnn;
}

class ReportAnalysis {
  const ReportAnalysis({
    required this.time,
    required this.story,
    this.reporterChoice,
    this.photos = const [],
    this.location,
    this.text,
  });

  final DateTime time;
  final String story;

  /// Pilihan warga, hanya keterangan tambahan. `null` berarti belum tahu.
  final SignCategory? reporterChoice;
  final List<ReportPhoto> photos;
  final ReportLocation? location;
  final TextAnalysis? text;

  bool get hasPhoto => photos.isNotEmpty;

  /// Cocok bila salah satu foto yang yakin menunjukkan tanda yang sama dengan
  /// teks. Foto lain boleh berbeda, misalnya foto suasana sekitar.
  MatchOutcome get match {
    if (!hasPhoto) return MatchOutcome.textOnly;
    final textResult = text;
    if (textResult == null) return MatchOutcome.photoOnly;
    final results = [for (final photo in photos) ?photo.cnn];
    if (results.isEmpty) return MatchOutcome.noCnn;
    final confident = results.where((r) => r.isConfident).toList();
    if (!textResult.isConfident || confident.isEmpty) {
      return MatchOutcome.uncertain;
    }
    return confident.any((r) => r.category == textResult.category)
        ? MatchOutcome.supported
        : MatchOutcome.different;
  }
}

String formatReportTime(DateTime time) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(time.day)}-${two(time.month)}-${time.year} '
      '${two(time.hour)}.${two(time.minute)}';
}

/// Pesan untuk penanggung jawab. [standardized] bisa sudah dikoreksi pelapor.
String buildReportMessage(ReportAnalysis report, String standardized) {
  final text = report.text;
  final location = report.location;
  final photoIssues = [
    for (final (index, photo) in report.photos.indexed)
      if (photo.quality == null)
        'foto ${index + 1} tidak bisa dibaca'
      else if (!photo.quality!.isClear)
        'foto ${index + 1} ${photo.quality!.issues.join(', ').toLowerCase()}',
  ];
  final photoGuesses = [
    for (final (index, photo) in report.photos.indexed)
      if (photo.cnn != null)
        'foto ${index + 1} ${photo.cnn!.category.label.toLowerCase()}'
            '${photo.cnn!.isConfident ? '' : ' (belum yakin)'}',
  ];

  final lines = <String>[
    '*LAPORAN TANDA LONGSOR - EWS Lumeneng*',
    'Waktu: ${formatReportTime(report.time)}',
    if (location != null) ...[
      'Lokasi HP pelapor: ${location.coordinates} '
          '(akurasi ±${location.accuracy.round()} m)',
      location.mapsUrl,
    ] else
      'Lokasi HP pelapor: tidak tersedia',
    if (text?.place != null) 'Tempat yang disebut: ${text!.place}',
    '',
    '*Keterangan:*',
    if (standardized.trim().isEmpty) '-' else standardized.trim(),
    if (report.story.trim().isNotEmpty) ...[
      '',
      '_Tulisan asli pelapor:_ ${report.story.trim()}',
    ],
    '',
    'Yang dilihat pelapor: ${report.reporterChoice?.label ?? 'Belum tahu'}',
    if (text != null)
      'Dugaan dari teks: ${text.category == null ? 'belum dikenali' : '${text.category!.label}${text.isConfident ? '' : ' (belum yakin)'}'}, '
          'urgensi ${text.urgency.label.toLowerCase()}',
    if (report.hasPhoto)
      'Foto: ${report.photos.length} terlampir'
          '${photoIssues.isEmpty ? '' : ' (${photoIssues.join('; ')})'}',
    if (photoGuesses.isNotEmpty) 'Dugaan dari foto: ${photoGuesses.join('; ')}',
    if (report.hasPhoto && text != null) 'Pencocokan: ${report.match.label}',
    '',
    'Hasil otomatis belum diverifikasi. Mohon diperiksa petugas.',
  ];
  return lines.join('\n');
}
