import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Foto layar penuh. Geser untuk pindah foto, cubit untuk memperbesar.
class PhotoViewer extends StatefulWidget {
  const PhotoViewer({
    super.key,
    required this.photos,
    this.initialIndex = 0,
    this.notes = const [],
  });

  final List<Uint8List> photos;
  final int initialIndex;

  /// Catatan per foto, `null` bila tidak ada. Boleh lebih pendek dari [photos].
  final List<String?> notes;

  static Future<void> open(
    BuildContext context, {
    required List<Uint8List> photos,
    int initialIndex = 0,
    List<String?> notes = const [],
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) =>
          PhotoViewer(photos: photos, initialIndex: initialIndex, notes: notes),
    ),
  );

  @override
  State<PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<PhotoViewer> {
  late final _pages = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  /// Selama diperbesar, geseran dipakai untuk menggeser foto, bukan pindah foto.
  bool _zoomed = false;

  /// Satu jari sedang menggeser untuk pindah foto.
  bool _swiping = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  // PageView tidak menangkap geseran sendiri. Kalau ikut berebut dengan
  // InteractiveViewer, usapan cepat sering dimenangkan zoom dan foto tidak
  // pindah. Jadi geseran satu jari dari InteractiveViewer diteruskan ke sini.
  // Halaman digeser dengan jumpTo, bukan position.drag: selama drag, PageView
  // menolak sentuhan baru, sehingga jari kedua untuk mencubit tidak sampai.
  void _startSwipe(ScaleStartDetails details) =>
      _swiping = !_zoomed && details.pointerCount == 1;

  void _updateSwipe(ScaleUpdateDetails details) {
    if (!_swiping) return;
    final position = _pages.position;
    position.jumpTo(
      (position.pixels - details.focalPointDelta.dx).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
  }

  /// Jari kedua yang turun juga mengakhiri geseran, lalu foto kembali pas.
  void _endSwipe(ScaleEndDetails details) {
    if (!_swiping) return;
    _swiping = false;
    final velocity = details.velocity.pixelsPerSecond.dx;
    final page = _pages.page ?? _index.toDouble();
    final target = velocity < -kMinFlingVelocity
        ? page.floor() + 1
        : velocity > kMinFlingVelocity
        ? page.ceil() - 1
        : page.round();
    _pages.animateToPage(
      target.clamp(0, widget.photos.length - 1),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.photos.length;
    final note = _index < widget.notes.length ? widget.notes[_index] : null;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: Text(count == 1 ? 'Foto' : 'Foto ${_index + 1} dari $count'),
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pages,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: count,
              onPageChanged: (index) => setState(() {
                _index = index;
                _zoomed = false;
              }),
              itemBuilder: (_, index) => _ZoomablePhoto(
                bytes: widget.photos[index],
                onStart: _startSwipe,
                onUpdate: _updateSwipe,
                onEnd: (details, zoomed) {
                  _endSwipe(details);
                  if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
                },
              ),
            ),
          ),
          if (note != null)
            Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                12,
                16,
                MediaQuery.paddingOf(context).bottom + 16,
              ),
              child: Text(
                note,
                style: Theme.of(context).textTheme.bodyLarge
                    ?.copyWith(color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}

class _ZoomablePhoto extends StatefulWidget {
  const _ZoomablePhoto({
    required this.bytes,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
  });

  final Uint8List bytes;
  final GestureScaleStartCallback onStart;
  final GestureScaleUpdateCallback onUpdate;

  /// `zoomed` true bila foto masih diperbesar setelah jari diangkat.
  final void Function(ScaleEndDetails details, bool zoomed) onEnd;

  @override
  State<_ZoomablePhoto> createState() => _ZoomablePhotoState();
}

class _ZoomablePhotoState extends State<_ZoomablePhoto> {
  final _transform = TransformationController();

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      transformationController: _transform,
      maxScale: 5,
      onInteractionStart: widget.onStart,
      onInteractionUpdate: widget.onUpdate,
      onInteractionEnd: (details) =>
          widget.onEnd(details, _transform.value.getMaxScaleOnAxis() > 1.01),
      child: Center(
        child: Image.memory(
          widget.bytes,
          fit: BoxFit.contain,
          gaplessPlayback: true,
        ),
      ),
    );
  }
}
