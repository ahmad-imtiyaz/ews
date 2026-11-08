import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../analysis/photo_analyzer.dart';
import '../analysis/report.dart';
import '../analysis/sign_category.dart';
import '../analysis/text_analyzer.dart';
import '../app_theme.dart';
import '../config.dart';
import '../widgets/section_card.dart';
import '../widgets/top_bar.dart';
import 'report_result_screen.dart';

const _storyHint =
    'Contoh: lemah e bengkah neng mburi omah pak RT, '
    'saiki tambah amba';

class _PendingPhoto {
  const _PendingPhoto(this.file, this.bytes, this.prepared);

  final XFile file;
  final Uint8List bytes;

  /// `null` bila foto tidak bisa dibaca.
  final PreparedPhoto? prepared;
}

class ReportScreen extends StatefulWidget {
  const ReportScreen({
    super.key,
    this.locateOnStart = true,
    this.loadText = TextAnalyzer.load,
    this.loadCnn = CnnClassifier.load,
  });

  /// Dimatikan di tes karena GPS tidak tersedia.
  final bool locateOnStart;
  final Future<TextAnalyzer> Function() loadText;
  final Future<CnnClassifier?> Function() loadCnn;

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  final _story = TextEditingController();
  final _picker = ImagePicker();
  late final Future<TextAnalyzer> _nlp = widget.loadText();
  late final Future<CnnClassifier?> _cnn = widget.loadCnn();

  final _photos = <_PendingPhoto>[];
  bool _preparingPhoto = false;

  SignCategory? _choice;

  ReportLocation? _location;
  String? _locationError;
  bool _locating = false;

  bool _analyzing = false;

  bool get _canSubmit =>
      !_analyzing &&
      !_preparingPhoto &&
      (_story.text.trim().isNotEmpty || _photos.isNotEmpty);

  @override
  void initState() {
    super.initState();
    _story.addListener(() => setState(() {}));
    _nlp.ignore();
    _cnn.ignore();
    if (widget.locateOnStart) _locate();
  }

  @override
  void dispose() {
    _story.dispose();
    _cnn.then((cnn) => cnn?.close());
    super.dispose();
  }

  Future<void> _pickPhotos(ImageSource source) async {
    final remaining = maxReportPhotos - _photos.length;
    if (remaining <= 0) return;

    final List<XFile> picked;
    try {
      if (source == ImageSource.camera) {
        final photo = await _picker.pickImage(
          source: ImageSource.camera,
          maxWidth: 1600,
          maxHeight: 1600,
          imageQuality: 85,
        );
        picked = [?photo];
      } else {
        picked = await _picker.pickMultiImage(
          maxWidth: 1600,
          maxHeight: 1600,
          imageQuality: 85,
          limit: remaining,
        );
      }
    } catch (_) {
      _showMessage('Kamera atau galeri belum bisa dibuka.');
      return;
    }
    if (picked.isEmpty) return;
    if (picked.length > remaining) {
      _showMessage('Hanya $maxReportPhotos foto per laporan.');
    }

    setState(() => _preparingPhoto = true);
    final added = <_PendingPhoto>[];
    for (final file in picked.take(remaining)) {
      final bytes = await file.readAsBytes();
      PreparedPhoto? prepared;
      try {
        prepared = await preparePhoto(bytes);
      } catch (_) {
        prepared = null;
      }
      added.add(_PendingPhoto(file, bytes, prepared));
    }
    if (!mounted) return;
    setState(() {
      _photos.addAll(added);
      _preparingPhoto = false;
    });
  }

  void _removePhoto(int index) {
    setState(() => _photos.removeAt(index));
  }

  Future<void> _locate() async {
    setState(() {
      _locating = true;
      _locationError = null;
    });
    String? error;
    ReportLocation? found;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        error = 'Lokasi HP mati. Nyalakan lokasi, lalu coba lagi.';
      } else {
        var permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          error = 'Izin lokasi ditolak. Laporan tetap bisa dikirim.';
        } else {
          Position? position;
          try {
            position = await Geolocator.getCurrentPosition(
              locationSettings: const LocationSettings(
                accuracy: LocationAccuracy.high,
                timeLimit: Duration(seconds: 30),
              ),
            );
          } catch (_) {
            // Di dalam rumah GPS sering belum dapat sinyal; pakai lokasi
            // terakhir yang diketahui HP, akurasinya ikut ditampilkan.
            position = await Geolocator.getLastKnownPosition();
          }
          if (position == null) {
            error = 'Lokasi belum didapat. Coba lagi di tempat terbuka.';
          } else {
            found = ReportLocation(
              position.latitude,
              position.longitude,
              position.accuracy,
            );
          }
        }
      }
    } catch (_) {
      error = 'Lokasi belum didapat. Coba lagi di tempat terbuka.';
    }
    if (!mounted) return;
    setState(() {
      _locating = false;
      _location = found ?? _location;
      _locationError = found == null ? error : null;
    });
  }

  Future<void> _submit() async {
    // Melepas fokus dari kolomnya, bukan dari halaman. Dengan
    // FocusScope.of(context).unfocus() halaman masih mengingat kolom cerita,
    // lalu keyboard muncul lagi saat kembali dari hasil analisis.
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _analyzing = true);

    final story = _story.text.trim();
    final nlp = await _nlp;
    final cnn = await _cnn;
    final photos = [
      for (final photo in _photos)
        ReportPhoto(
          path: photo.file.path,
          bytes: photo.bytes,
          quality: photo.prepared?.quality,
          cnn: _classify(cnn, photo.prepared),
        ),
    ];

    final report = ReportAnalysis(
      time: DateTime.now(),
      story: story,
      reporterChoice: _choice,
      photos: photos,
      location: _location,
      text: story.isEmpty ? null : nlp.analyze(story),
    );

    if (!mounted) return;
    setState(() => _analyzing = false);
    final startOver = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ReportResultScreen(
          report: report,
          cnnInstalled: cnn != null,
          trainingSize: nlp.trainingSize,
        ),
      ),
    );
    if (startOver == true && mounted) _reset();
  }

  CnnResult? _classify(CnnClassifier? cnn, PreparedPhoto? prepared) {
    if (cnn == null || prepared == null) return null;
    try {
      return cnn.classify(prepared.cnnInput);
    } catch (_) {
      return null;
    }
  }

  void _reset() {
    _story.clear();
    setState(() {
      _photos.clear();
      _choice = null;
    });
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: const TopBar(title: 'EWS Lumeneng'),
      body: ListView(
        // Isi boleh lewat di belakang menu bawah, tetapi bagian akhirnya
        // diberi ruang setinggi menu itu agar tombol terakhir bisa dicapai.
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          MediaQuery.paddingOf(context).bottom + 24,
        ),
        children: [
          Text(
            'Lapor tanda longsor',
            style: textTheme.titleLarge?.copyWith(fontSize: 22),
          ),
          const SizedBox(height: 6),
          Text(
            'Tulis dengan bahasa sehari-hari. Bahasa Jawa juga bisa, nanti '
            'dibakukan ke bahasa Indonesia.',
            style: textTheme.bodyLarge?.copyWith(color: AppColors.inkSoft),
          ),
          const SizedBox(height: 16),
          const _SafetyNote(),
          const SizedBox(height: 16),
          _PhotoSection(
            photos: _photos,
            preparing: _preparingPhoto,
            onCamera: () => _pickPhotos(ImageSource.camera),
            onGallery: () => _pickPhotos(ImageSource.gallery),
            onRemove: _removePhoto,
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Ceritakan yang Anda lihat',
            children: [
              TextField(
                controller: _story,
                minLines: 4,
                maxLines: 8,
                textCapitalization: TextCapitalization.sentences,
                style: textTheme.bodyLarge,
                decoration: InputDecoration(
                  hintText: _storyHint,
                  hintMaxLines: 3,
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
              const SizedBox(height: 8),
              Text(
                'Sebutkan tempatnya, misalnya "mburi omah pak RT" atau '
                '"pinggir kali".',
                style: textTheme.bodyMedium?.copyWith(color: AppColors.inkSoft),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Yang terlihat',
            children: [
              _SignChoices(
                selected: _choice,
                onSelected: (choice) => setState(() => _choice = choice),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _LocationSection(
            location: _location,
            error: _locationError,
            locating: _locating,
            onRetry: _locate,
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _canSubmit ? _submit : null,
            child: Text(_analyzing ? 'Menganalisis...' : 'Periksa laporan'),
          ),
          if (!_canSubmit && !_analyzing) ...[
            const SizedBox(height: 8),
            Text(
              'Isi cerita atau tambahkan foto dulu.',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(color: AppColors.inkSoft),
            ),
          ],
        ],
      ),
    );
  }
}

class _SafetyNote extends StatelessWidget {
  const _SafetyNote();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.health_and_safety_outlined, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Ambil foto dari tempat aman. Jangan mendekati lereng atau '
                'tanah yang bergerak.',
                style: Theme.of(context).textTheme.bodyLarge
                    ?.copyWith(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoSection extends StatelessWidget {
  const _PhotoSection({
    required this.photos,
    required this.preparing,
    required this.onCamera,
    required this.onGallery,
    required this.onRemove,
  });

  final List<_PendingPhoto> photos;
  final bool preparing;
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hintStyle = textTheme.bodyMedium?.copyWith(color: AppColors.inkSoft);
    final full = photos.length >= maxReportPhotos;
    final canAdd = !preparing && !full;

    final buttons = Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: canAdd ? onCamera : null,
            icon: const Icon(Icons.photo_camera_outlined, size: 18),
            label: const Text('Kamera'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: canAdd ? onGallery : null,
            icon: const Icon(Icons.photo_library_outlined, size: 18),
            label: const Text('Galeri'),
          ),
        ),
      ],
    );

    if (photos.isEmpty) {
      return SectionCard(
        title: 'Foto (boleh dilewati)',
        children: [
          Container(
            height: 120,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.panel,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: preparing
                ? const CircularProgressIndicator()
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.add_a_photo_outlined,
                        size: 32,
                        color: AppColors.inkSoft,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Foto retakan, longsoran, atau air yang keluar',
                        textAlign: TextAlign.center,
                        style: hintStyle,
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 8),
          Text(
            'Boleh sampai $maxReportPhotos foto. Saran 3 foto: dari dekat, '
            'dari jauh, dan keadaan sekitar.',
            style: hintStyle,
          ),
          const SizedBox(height: 10),
          buttons,
        ],
      );
    }

    final notes = [
      for (final (index, photo) in photos.indexed)
        if (photo.prepared == null)
          'Foto ${index + 1}: tidak bisa dibaca, tetap ikut dikirim.'
        else if (!photo.prepared!.quality.isClear)
          'Foto ${index + 1}: '
              '${photo.prepared!.quality.issues.join(', ').toLowerCase()}.',
    ];

    return SectionCard(
      title: 'Foto (${photos.length} dari $maxReportPhotos)',
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            const gap = 8.0;
            final size = (constraints.maxWidth - gap * 2) / 3;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final (index, photo) in photos.indexed)
                  _PhotoTile(
                    size: size,
                    number: index + 1,
                    photo: photo,
                    onRemove: () => onRemove(index),
                  ),
                if (preparing)
                  SizedBox.square(
                    dimension: size,
                    child: const Center(child: CircularProgressIndicator()),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 10),
        if (notes.isEmpty)
          Text('Semua foto cukup jelas.', style: textTheme.bodyLarge)
        else ...[
          for (final note in notes) Text(note, style: textTheme.bodyLarge),
          const SizedBox(height: 2),
          Text('Ambil ulang bila aman, atau kirim saja.', style: hintStyle),
        ],
        const SizedBox(height: 10),
        if (full)
          Text(
            'Sudah $maxReportPhotos foto. Hapus salah satu untuk menggantinya.',
            style: hintStyle,
          )
        else
          buttons,
      ],
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({
    required this.size,
    required this.number,
    required this.photo,
    required this.onRemove,
  });

  final double size;
  final int number;
  final _PendingPhoto photo;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final clear = photo.prepared?.quality.isClear ?? false;

    return SizedBox.square(
      dimension: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(
              photo.bytes,
              fit: BoxFit.cover,
              cacheWidth: 300,
              gaplessPlayback: true,
            ),
          ),
          Positioned(
            left: 6,
            bottom: 6,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$number',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      clear ? Icons.check_circle_outline : Icons.info_outline,
                      size: 14,
                      semanticLabel: clear ? 'Jelas' : 'Perlu dicek',
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: IconButton.filled(
              onPressed: onRemove,
              tooltip: 'Hapus foto $number',
              iconSize: 18,
              style: IconButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.ink,
                minimumSize: const Size(32, 32),
                fixedSize: const Size(32, 32),
                tapTargetSize: MaterialTapTargetSize.padded,
              ),
              icon: const Icon(Icons.close),
            ),
          ),
        ],
      ),
    );
  }
}

class _SignChoices extends StatelessWidget {
  const _SignChoices({required this.selected, required this.onSelected});

  final SignCategory? selected;
  final ValueChanged<SignCategory?> onSelected;

  @override
  Widget build(BuildContext context) {
    final options = <(SignCategory?, String)>[
      (null, 'Belum tahu'),
      for (final category in SignCategory.values)
        if (category != SignCategory.tidakRelevan) (category, category.label),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (category, label) in options)
          ChoiceChip(
            label: Text(label),
            selected: selected == category,
            showCheckmark: false,
            onSelected: (_) => onSelected(category),
            backgroundColor: Colors.white,
            selectedColor: AppColors.ink,
            side: const BorderSide(color: AppColors.border),
            labelStyle: TextStyle(
              fontFamily: appFontFamily,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected == category ? Colors.white : AppColors.ink,
            ),
          ),
      ],
    );
  }
}

class _LocationSection extends StatelessWidget {
  const _LocationSection({
    required this.location,
    required this.error,
    required this.locating,
    required this.onRetry,
  });

  final ReportLocation? location;
  final String? error;
  final bool locating;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final found = location;

    final status = locating
        ? 'Mencari lokasi...'
        : found != null
        ? found.coordinates
        : error ?? 'Lokasi belum diambil.';

    return SectionCard(
      title: 'Lokasi',
      children: [
        Row(
          children: [
            const Icon(Icons.my_location, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(status, style: textTheme.bodyLarge),
                  if (found != null && !locating)
                    Text(
                      'Akurasi ±${found.accuracy.round()} m',
                      style: textTheme.bodyMedium?.copyWith(
                        color: AppColors.inkSoft,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: locating ? null : onRetry,
              child: Text(found == null ? 'Ambil' : 'Perbarui'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Ini lokasi HP Anda. Bila kejadiannya di tempat lain, sebutkan di '
          'cerita.',
          style: textTheme.bodyMedium?.copyWith(color: AppColors.inkSoft),
        ),
      ],
    );
  }
}
