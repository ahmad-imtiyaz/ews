import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../analysis/photo_collage.dart';
import '../analysis/report.dart';
import '../analysis/text_analyzer.dart';
import '../app_theme.dart';
import '../config.dart';
import '../services/whatsapp_sender.dart';
import '../widgets/section_card.dart';
import '../widgets/top_bar.dart';

String _decimal(double value) => value.toStringAsFixed(2).replaceAll('.', ',');

class ReportResultScreen extends StatefulWidget {
  const ReportResultScreen({
    super.key,
    required this.report,
    required this.cnnInstalled,
    required this.trainingSize,
  });

  final ReportAnalysis report;
  final bool cnnInstalled;
  final int trainingSize;

  @override
  State<ReportResultScreen> createState() => _ReportResultScreenState();
}

class _ReportResultScreenState extends State<ReportResultScreen> {
  late final _standardized = TextEditingController(
    text: widget.report.text?.standardized ?? '',
  );
  bool _sharing = false;
  bool _shared = false;
  bool _textCopied = false;

  /// Dibuat sekali saat pertama dikirim, dipakai lagi untuk "Kirim lagi".
  String? _collagePath;

  @override
  void dispose() {
    _standardized.dispose();
    super.dispose();
  }

  Future<void> _share() async {
    setState(() => _sharing = true);
    final report = widget.report;
    var paths = [for (final photo in report.photos) photo.path];

    // WhatsApp memasang teks di setiap foto, jadi 3 foto menjadi 3 laporan.
    // Foto digabung menjadi satu gambar agar laporan tetap satu pesan.
    if (paths.length > 1) {
      try {
        _collagePath ??= await buildCollage(paths);
      } catch (_) {
        _collagePath = null;
      }
      if (_collagePath != null) paths = [_collagePath!];
    }
    final message = buildReportMessage(
      report,
      _standardized.text,
      photosCombined: paths.length == 1 && report.photos.length > 1,
    );

    // Bila penggabungan gagal, teks juga disalin agar bisa ditempel.
    _textCopied = paths.length > 1;
    if (_textCopied) {
      await Clipboard.setData(ClipboardData(text: message));
    }
    final opened = await WhatsAppSender.send(text: message, imagePaths: paths);
    if (!mounted) return;
    if (opened) {
      setState(() {
        _sharing = false;
        _shared = true;
      });
      return;
    }

    // WhatsApp tidak terpasang: pakai menu bagikan HP.
    ShareResultStatus? status;
    try {
      final result = await SharePlus.instance.share(
        ShareParams(
          text: message,
          subject: 'Laporan tanda longsor',
          files: paths.isEmpty ? null : [for (final path in paths) XFile(path)],
        ),
      );
      status = result.status;
    } catch (_) {
      status = null;
    }
    if (!mounted) return;
    setState(() {
      _sharing = false;
      if (status != null && status != ShareResultStatus.dismissed) {
        _shared = true;
      }
    });
    if (status == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Menu bagikan belum bisa dibuka.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final report = widget.report;

    return Scaffold(
      appBar: const TopBar(title: 'Hasil analisis', backLabel: 'Ubah'),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          MediaQuery.paddingOf(context).bottom + 24,
        ),
        children: [
          _StandardizedCard(report: report, controller: _standardized),
          const SizedBox(height: 16),
          if (report.text != null) ...[
            _NlpCard(text: report.text!, trainingSize: widget.trainingSize),
            const SizedBox(height: 16),
          ],
          _PhotoCard(report: report, cnnInstalled: widget.cnnInstalled),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Pencocokan teks dan foto',
            children: [
              Text(report.match.label, style: textTheme.bodyLarge),
              const SizedBox(height: 4),
              Text(
                'Hasil otomatis hanya membantu petugas. Yang menentukan '
                'tetap pemeriksaan di lapangan.',
                style: textTheme.bodyMedium?.copyWith(color: AppColors.inkSoft),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Lokasi dan waktu',
            children: [
              InfoRow(
                label: 'Lokasi HP',
                value: report.location?.coordinates ?? 'Tidak tersedia',
              ),
              if (report.text?.place != null)
                InfoRow(label: 'Tempat disebut', value: report.text!.place!),
              InfoRow(label: 'Waktu', value: formatReportTime(report.time)),
            ],
          ),
          const SizedBox(height: 20),
          if (_shared) ...[
            _SharedNotice(textCopied: _textCopied),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Buat laporan baru'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _sharing ? null : _share,
              child: const Text('Kirim lagi'),
            ),
          ] else ...[
            FilledButton.icon(
              onPressed: _sharing ? null : _share,
              icon: const Icon(Icons.send_outlined, size: 18),
              label: const Text('Kirim ke petugas lewat WhatsApp'),
            ),
            const SizedBox(height: 8),
            Text(
              'Dikirim ke WhatsApp penanggung jawab '
              '${localPhone(reportWhatsAppNumber)}.'
              '${report.photos.length > 1 ? ' ${report.photos.length} foto '
                        'digabung jadi satu gambar bernomor agar laporan '
                        'masuk dalam satu pesan.' : ''}',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(color: AppColors.inkSoft),
            ),
          ],
        ],
      ),
    );
  }
}

class _StandardizedCard extends StatelessWidget {
  const _StandardizedCard({required this.report, required this.controller});

  final ReportAnalysis report;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    if (report.text == null) {
      return SectionCard(
        title: 'Keterangan',
        children: [
          Text(
            'Tidak ada cerita. Petugas akan melihat fotonya saja.',
            style: textTheme.bodyLarge,
          ),
        ],
      );
    }

    return SectionCard(
      title: 'Laporan dalam bahasa Indonesia',
      children: [
        TextField(
          controller: controller,
          minLines: 2,
          maxLines: 6,
          style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.panel,
            contentPadding: const EdgeInsets.all(12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.border),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Bisa diperbaiki bila ada kata yang kurang pas.',
          style: textTheme.bodyMedium?.copyWith(color: AppColors.inkSoft),
        ),
        const SizedBox(height: 12),
        Text('Tulisan asli', style: textTheme.labelLarge),
        const SizedBox(height: 2),
        Text(report.story, style: textTheme.bodyLarge),
      ],
    );
  }
}

class _NlpCard extends StatelessWidget {
  const _NlpCard({required this.text, required this.trainingSize});

  final TextAnalysis text;
  final int trainingSize;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final category = text.category;
    final confidence = text.confidence;
    final changed = text.changedTokens;

    final categoryText = category == null
        ? 'Belum dikenali'
        : text.isConfident
        ? category.label
        : '${category.label} (belum yakin)';

    final ranked = text.probabilities.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return SectionCard(
      title: 'Analisis teks (NLP)',
      children: [
        InfoRow(label: 'Jenis tanda', value: categoryText),
        if (confidence != null)
          InfoRow(label: 'Keyakinan', value: _decimal(confidence)),
        InfoRow(
          label: 'Urgensi',
          value: text.urgencyMarkers.isEmpty
              ? text.urgency.label
              : '${text.urgency.label} (${text.urgencyMarkers.join(', ')})',
        ),
        InfoRow(label: 'Tempat disebut', value: text.place ?? '-'),
        if (text.unknownWords.isNotEmpty)
          InfoRow(
            label: 'Belum ada di kamus',
            value: text.unknownWords.join(', '),
          ),
        // Daftar kata bisa panjang, jadi memakai lebar kartu penuh, bukan
        // kolom nilai yang sempit.
        if (changed.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Kata dibakukan',
            style: textTheme.bodyLarge?.copyWith(color: AppColors.inkSoft),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (final token in changed) _WordChange(token)],
          ),
        ],
        const Divider(height: 24),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            minTileHeight: 44,
            childrenPadding: const EdgeInsets.only(bottom: 4),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            title: Text('Lihat langkah NLP', style: textTheme.labelLarge),
            children: [
              _Step('1. Case folding', text.caseFolded),
              _Step(
                '2. Tokenisasi',
                '[${text.tokens.map((t) => t.original.toLowerCase()).join(', ')}]',
              ),
              _Step(
                '3. Normalisasi kamus lokal',
                '[${text.tokens.where((t) => t.normalized.isNotEmpty).map((t) => t.normalized.toLowerCase()).join(', ')}]',
              ),
              _Step(
                '4. Hapus stopword, stemming, tandai penyangkalan',
                '[${text.features.join(', ')}]',
              ),
              _Step(
                '5. Klasifikasi Naive Bayes',
                ranked.isEmpty
                    ? 'Tidak ada kata yang dikenal model.'
                    : ranked
                          .take(3)
                          .map((e) => '${e.key.label}: ${_decimal(e.value)}')
                          .join('\n'),
              ),
              Text(
                'Model dilatih dari $trainingSize contoh awal buatan tim, '
                'belum dari laporan warga. Angka keyakinan belum teruji.',
                style: textTheme.bodyMedium?.copyWith(color: AppColors.inkSoft),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Satu kata asli dan bentuk bakunya, misalnya "mburi → belakang".
class _WordChange extends StatelessWidget {
  const _WordChange(this.token);

  final NlpToken token;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyLarge;
    final normalized = token.normalized;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(text: token.original.toLowerCase()),
              if (normalized.isEmpty)
                TextSpan(
                  text: token.merged ? ' (digabung)' : ' (dibuang)',
                  style: const TextStyle(color: AppColors.inkSoft),
                )
              else
                TextSpan(
                  text: ' → $normalized',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
            ],
          ),
          style: style,
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step(this.title, this.body);

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: textTheme.labelLarge),
          const SizedBox(height: 2),
          Text(body, style: textTheme.bodyLarge),
        ],
      ),
    );
  }
}

class _PhotoCard extends StatelessWidget {
  const _PhotoCard({required this.report, required this.cnnInstalled});

  final ReportAnalysis report;
  final bool cnnInstalled;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    if (!report.hasPhoto) {
      return SectionCard(
        title: 'Analisis foto (CNN)',
        children: [Text('Tidak ada foto.', style: textTheme.bodyLarge)],
      );
    }

    return SectionCard(
      title: 'Analisis foto (CNN)',
      children: [
        for (final (index, photo) in report.photos.indexed) ...[
          if (index > 0) const Divider(height: 24),
          _PhotoResult(number: index + 1, photo: photo),
        ],
        if (!cnnInstalled) ...[
          const SizedBox(height: 12),
          Text(
            'Model CNN belum dipasang karena belum ada foto lapangan berlabel '
            'untuk melatihnya. Foto tetap dikirim untuk dilihat petugas.',
            style: textTheme.bodyMedium?.copyWith(color: AppColors.inkSoft),
          ),
        ],
      ],
    );
  }
}

class _PhotoResult extends StatelessWidget {
  const _PhotoResult({required this.number, required this.photo});

  final int number;
  final ReportPhoto photo;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final soft = textTheme.bodyMedium?.copyWith(color: AppColors.inkSoft);
    final quality = photo.quality;
    final cnn = photo.cnn;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.memory(
            photo.bytes,
            width: 84,
            height: 84,
            fit: BoxFit.cover,
            cacheWidth: 250,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Foto $number', style: textTheme.labelLarge),
              const SizedBox(height: 2),
              Text(
                quality == null
                    ? 'Tidak bisa dibaca'
                    : quality.isClear
                    ? 'Cukup jelas'
                    : quality.issues.join(', '),
                style: textTheme.bodyLarge,
              ),
              if (quality != null)
                Text(
                  '${quality.width} x ${quality.height}, kecerahan '
                  '${quality.brightness.round()}, ketajaman '
                  '${quality.sharpness.round()}',
                  style: soft,
                ),
              if (cnn != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Isi foto: ${cnn.category.label}'
                  '${cnn.isConfident ? '' : ' (belum yakin)'}, '
                  'keyakinan ${_decimal(cnn.confidence)}',
                  style: textTheme.bodyLarge,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SharedNotice extends StatelessWidget {
  const _SharedNotice({required this.textCopied});

  final bool textCopied;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.ink),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.check_circle_outline),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${textCopied ? 'Teks laporan juga sudah disalin. Bila tidak '
                          'muncul di WhatsApp, tekan lama kolom pesan lalu '
                          'Tempel. ' : ''}'
                'Pastikan pesannya sudah terkirim di WhatsApp. Bila tanda '
                'makin parah, segera menjauh dan hubungi petugas desa.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
