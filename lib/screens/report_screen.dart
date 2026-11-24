import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../analysis/photo_analyzer.dart';
import '../analysis/report.dart';
import '../analysis/sign_category.dart';
import '../analysis/text_analyzer.dart';
import '../app_theme.dart';
import '../config.dart';
import '../services/notification_inbox.dart';
import '../services/phone_location.dart';
import '../widgets/notification_bell.dart';
import '../widgets/photo_viewer.dart';
import '../widgets/section_card.dart';
import '../widgets/top_bar.dart';
import 'report_result_screen.dart';

/// Paling lama menunggu lokasi akurat setelah Periksa laporan ditekan. Laporan
/// tanda longsor tidak boleh tertahan oleh GPS yang tidak kunjung masuk,
/// misalnya di dalam rumah.
const _locationWaitLimit = Duration(seconds: 30);

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
    this.locate = watchPhoneLocation,
    this.isApproximate = isLocationApproximate,
    this.loadText = TextAnalyzer.load,
    this.loadCnn = CnnClassifier.load,
    this.inbox,
  });

  /// Dimatikan di tes karena GPS tidak tersedia.
  final bool locateOnStart;
  final Stream<PhoneFix> Function() locate;
  final Future<bool> Function() isApproximate;
  final Future<TextAnalyzer> Function() loadText;
  final Future<CnnClassifier?> Function() loadCnn;

  /// Lonceng di bar atas. Kosong di tes yang membuka halaman ini sendiri.
  final NotificationInbox? inbox;

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

  /// Sama dengan [_location], untuk jendela tunggu lokasi.
  final _liveLocation = ValueNotifier<ReportLocation?>(null);
  LocationProblem? _locationProblem;
  StreamSubscription<PhoneFix>? _locationUpdates;
  bool _locating = false;

  /// Sudah ada posisi dari pencarian ini, tapi GPS belum masuk.
  bool _sharpening = false;

  /// Jendela tunggu lokasi sedang terbuka.
  bool _waitingForLocation = false;

  /// Izin lokasi hanya "Perkiraan", posisinya bisa meleset sampai ±2 km.
  bool _approximate = false;

  /// Dialog lokasi tepat sudah ditawarkan dari tombol. Bila masih
  /// perkiraan, tombol berikutnya membuka pengaturan izin.
  bool _preciseAsked = false;

  late final AppLifecycleListener _lifecycle;

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
    _lifecycle = AppLifecycleListener(onResume: _onReturn);
    if (widget.locateOnStart) _locate();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _locationUpdates?.cancel();
    _liveLocation.dispose();
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

  void _locate() {
    _locationUpdates?.cancel();
    setState(() {
      _locating = true;
      _sharpening = false;
      _locationProblem = null;
    });
    _locationUpdates = widget.locate().listen(
      (fix) {
        setState(() {
          _location = ReportLocation(fix.latitude, fix.longitude, fix.accuracy);
          _sharpening = true;
        });
        _liveLocation.value = _location;
      },
      onError: (Object e) => setState(() {
        _locationProblem = e is LocationUnavailable
            ? e.problem
            : LocationProblem.notFound;
      }),
      onDone: () {
        setState(() {
          _locating = false;
          _sharpening = false;
        });
        // Pencarian berhenti setelah 45 detik sejak Lapor dibuka, bisa di
        // tengah jendela tunggu. Tanpa ini sisa waktunya terbuang.
        if (_waitingForLocation && _locationProblem == null && mounted) {
          _locate();
        }
      },
    );
    // Dicek sekarang, bukan menunggu posisi pertama: dengan izin "Perkiraan"
    // sebagian HP tidak mendapat posisi sama sekali, dan warga perlu tahu
    // penyebabnya izin, bukan tempatnya.
    _checkPrecision();
  }

  Future<void> _checkPrecision() async {
    final approximate = await widget.isApproximate();
    if (mounted && approximate != _approximate) {
      setState(() => _approximate = approximate);
    }
  }

  Future<void> _allowPrecise() async {
    if (_preciseAsked) {
      // Android tidak memunculkan dialognya lagi; kembali dari pengaturan
      // ditangani [_onReturn].
      await openLocationSettings();
      return;
    }
    // Android memunculkan dialognya paling banyak sekali lagi. Bila izinnya
    // tetap perkiraan, tombol dan petunjuknya sudah menunjuk ke pengaturan.
    setState(() => _preciseAsked = true);
    await askPreciseLocation();
    await _checkPrecision();
    if (mounted && !_approximate) _locate();
  }

  /// Kembali dari jendela izin atau pengaturan HP: izinnya bisa berubah ke
  /// "Perkiraan" atau sebaliknya. Bila sekarang lokasi tepat, posisinya
  /// diambil ulang.
  Future<void> _onReturn() async {
    final wasApproximate = _approximate;
    await _checkPrecision();
    if (mounted && wasApproximate && !_approximate) _locate();
  }

  /// Lokasi masih kasar padahal bisa jadi akurat. Lokasi yang mati, izin yang
  /// ditolak, atau izin "Perkiraan" tidak ditunggu: menunggu tidak membantu.
  bool get _locationWorthWaiting {
    if (_locationProblem != null || _approximate) return false;
    final location = _location;
    if (location == null) return _locating;
    return location.accuracy > gpsAccuracy;
  }

  Future<void> _submit() async {
    // Melepas fokus dari kolomnya, bukan dari halaman. Dengan
    // FocusScope.of(context).unfocus() halaman masih mengingat kolom cerita,
    // lalu keyboard muncul lagi saat kembali dari hasil analisis.
    FocusManager.instance.primaryFocus?.unfocus();

    if (_locationWorthWaiting) {
      // Pencarian berhenti setelah 45 detik; warga yang lama mengetik
      // dicarikan lagi.
      if (!_locating) _locate();
      _waitingForLocation = true;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _LocationWait(location: _liveLocation),
      );
      _waitingForLocation = false;
      if (!mounted) return;
    }

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
      appBar: TopBar(
        actions: [
          if (widget.inbox case final inbox?) NotificationBell(inbox: inbox),
        ],
      ),
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
            problem: _locationProblem,
            locating: _locating && !_sharpening,
            sharpening: _sharpening,
            onRetry: _locate,
            approximate: _approximate,
            openSettings: _preciseAsked,
            onAllowPrecise: _allowPrecise,
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

/// Menunggu GPS sebentar sebelum laporan diperiksa, dengan angka akurasi yang
/// terus turun. Tutup sendiri begitu lokasi cukup akurat atau waktunya habis.
class _LocationWait extends StatefulWidget {
  const _LocationWait({required this.location});

  final ValueListenable<ReportLocation?> location;

  @override
  State<_LocationWait> createState() => _LocationWaitState();
}

class _LocationWaitState extends State<_LocationWait> {
  late final Timer _limit;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    _limit = Timer(_locationWaitLimit, _close);
    widget.location.addListener(_onLocation);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onLocation());
  }

  @override
  void dispose() {
    _limit.cancel();
    widget.location.removeListener(_onLocation);
    super.dispose();
  }

  void _onLocation() {
    final location = widget.location.value;
    if (location != null && location.accuracy <= gpsAccuracy) _close();
  }

  void _close() {
    if (_closed || !mounted) return;
    _closed = true;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return AlertDialog(
      title: const Text('Menunggu lokasi akurat'),
      content: ValueListenableBuilder(
        valueListenable: widget.location,
        builder: (context, location, _) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    location == null
                        ? 'Mencari lokasi...'
                        : 'Sekarang ±${location.accuracy.round()} m',
                    style: textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Supaya petugas bisa menemukan tempatnya. Lanjut sendiri begitu '
              'lokasi ±${gpsAccuracy.round()} m, paling lama '
              '${_locationWaitLimit.inSeconds} detik. Tetap di tempat yang '
              'aman, jangan mendekati lereng.',
              style: textTheme.bodyLarge?.copyWith(color: AppColors.inkSoft),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _close,
          child: const Text('Lanjut tanpa menunggu'),
        ),
      ],
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

    final photoNotes = [
      for (final (index, photo) in photos.indexed)
        if (_noteOf(photo) case final note?)
          'Foto ${index + 1}: $note'
        else
          null,
    ];
    final notes = photoNotes.nonNulls.toList();

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
                    onOpen: () => PhotoViewer.open(
                      context,
                      photos: [for (final photo in photos) photo.bytes],
                      initialIndex: index,
                      notes: photoNotes,
                    ),
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

  static String? _noteOf(_PendingPhoto photo) {
    final prepared = photo.prepared;
    if (prepared == null) return 'tidak bisa dibaca, tetap ikut dikirim.';
    final quality = prepared.quality;
    if (quality.isClear) return null;
    // Saran untuk masalah yang paling menentukan saja, supaya singkat.
    return '${quality.issueText.toLowerCase()}. ${quality.issues.first.tip}';
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({
    required this.size,
    required this.number,
    required this.photo,
    required this.onOpen,
    required this.onRemove,
  });

  final double size;
  final int number;
  final _PendingPhoto photo;
  final VoidCallback onOpen;
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
          Positioned.fill(
            child: Material(
              type: MaterialType.transparency,
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onOpen,
                child: Semantics(
                  button: true,
                  label: 'Lihat foto $number',
                  child: const SizedBox.expand(),
                ),
              ),
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
    required this.problem,
    required this.locating,
    required this.sharpening,
    required this.onRetry,
    required this.approximate,
    required this.openSettings,
    required this.onAllowPrecise,
  });

  final ReportLocation? location;
  final LocationProblem? problem;
  final bool locating;
  final bool sharpening;
  final VoidCallback onRetry;
  final bool approximate;

  /// Dialog Android sudah ditolak, jadi tombolnya membuka pengaturan.
  final bool openSettings;
  final VoidCallback onAllowPrecise;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final found = location;

    final status = locating
        ? 'Mencari lokasi...'
        : found != null
        ? found.coordinates
        : switch (problem) {
            LocationProblem.serviceOff =>
              'Lokasi HP mati. Nyalakan lokasi, lalu coba lagi.',
            LocationProblem.denied =>
              'Izin lokasi ditolak. Laporan tetap bisa dikirim.',
            // Penyebabnya izin, yang dijelaskan di bawah. Pindah ke tempat
            // terbuka tidak membantu.
            LocationProblem.notFound when approximate =>
              'Lokasi belum didapat.',
            LocationProblem.notFound =>
              'Lokasi belum didapat. Coba lagi di tempat terbuka.',
            null => 'Lokasi belum diambil.',
          };

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
                      sharpening && !approximate
                          ? 'Akurasi ±${found.accuracy.round()} m, menunggu GPS...'
                          : 'Akurasi ±${found.accuracy.round()} m',
                      style: textTheme.bodyMedium?.copyWith(
                        color: AppColors.inkSoft,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: locating || sharpening ? null : onRetry,
              child: Text(found == null ? 'Ambil' : 'Perbarui'),
            ),
          ],
        ),
        if (approximate) ...[
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.warning_amber_rounded, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  openSettings
                      ? 'Lokasi masih perkiraan, bisa meleset sampai 2 km. '
                            'Di pengaturan, buka Izin > Lokasi, lalu nyalakan '
                            '"Gunakan lokasi tepat" (di sebagian HP "Gunakan '
                            'lokasi presisi").'
                      : 'Lokasi masih perkiraan, bisa meleset sampai 2 km. '
                            'Izinkan lokasi tepat agar petugas menemukan '
                            'tempatnya.',
                  style: textTheme.bodyLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: onAllowPrecise,
            child: Text(
              openSettings ? 'Buka pengaturan izin' : 'Izinkan lokasi tepat',
            ),
          ),
        ],
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
