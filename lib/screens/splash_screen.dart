import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';

import '../data/monitoring.dart';
import '../services/ews_feed.dart';
import 'main_shell.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.feed, this.showMapTiles = true});

  /// Diisi di tes. Bila kosong, data diambil dari server EWS. Setelah splash,
  /// MainShell yang memegang dan menutupnya.
  final EwsFeed? feed;
  final bool showMapTiles;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const _stillDuration = Duration(seconds: 1);
  static const _maxAnimationWait = Duration(seconds: 5);
  static const _loadTimeout = Duration(seconds: 8);
  // Android masih memudarkan jendela saat aplikasi baru dibuka. Tanpa jeda ini,
  // adegan retak sudah lewat sebelum terlihat.
  static const _startDelay = Duration(milliseconds: 600);

  late final AnimationController _controller = AnimationController(vsync: this);
  late final EwsFeed _feed = widget.feed ?? EwsFeed();
  final _animationDone = Completer<void>();

  Timer? _waitTimer;
  Timer? _startTimer;
  bool _animationsDisabled = false;
  bool _waitingForData = false;

  @override
  void initState() {
    super.initState();
    _openHome();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_waitTimer != null) return;

    _animationsDisabled = MediaQuery.disableAnimationsOf(context);
    // Batas waktu ini menjaga warga tidak tertahan bila animasi gagal dimuat.
    _waitTimer = Timer(
      _animationsDisabled ? _stillDuration : _maxAnimationWait,
      _finishAnimation,
    );
  }

  @override
  void dispose() {
    _waitTimer?.cancel();
    _startTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _finishAnimation() {
    if (!_animationDone.isCompleted) _animationDone.complete();
  }

  void _onAnimationLoaded(LottieComposition composition) {
    _controller.duration = composition.duration;
    if (_animationsDisabled) {
      _controller.value = 1;
    } else {
      _startTimer = Timer(_startDelay, () {
        _controller.forward().whenComplete(_finishAnimation);
      });
    }
  }

  Future<void> _openHome() async {
    // Kegagalan memuat tidak boleh menahan warga di splash. Bila lewat batas
    // waktu, pengambilan tetap jalan dan Beranda ikut berubah begitu selesai.
    final data = _feed.refresh().timeout(_loadTimeout).catchError((_) {});

    // Saat Awas, warga langsung melihat kondisi tanpa menunggu animasi.
    unawaited(
      data.then((_) {
        if (monitoringFrom(_feed.data).status == MonitoringStatus.awas) {
          _finishAnimation();
        }
      }),
    );

    var dataReady = false;
    unawaited(data.whenComplete(() => dataReady = true));

    await _animationDone.future;
    _waitTimer?.cancel();
    if (!mounted) return;
    if (!dataReady) setState(() => _waitingForData = true);

    await data;
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) =>
            MainShell(feed: _feed, showMapTiles: widget.showMapTiles),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Semantics(
        button: true,
        label: 'Lewati animasi pembuka',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _finishAnimation,
          child: Scaffold(
            backgroundColor: Colors.black,
            body: Stack(
              fit: StackFit.expand,
              children: [
                Lottie.asset(
                  'assets/animations/splash.json',
                  controller: _controller,
                  frameRate: FrameRate.max,
                  fit: BoxFit.cover,
                  onLoaded: _onAnimationLoaded,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
                SafeArea(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'EWS Lumeneng',
                            textAlign: TextAlign.center,
                            style: textTheme.headlineLarge?.copyWith(
                              color: Colors.white,
                              fontSize: 30,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _waitingForData
                                ? 'Mengambil data terbaru'
                                : 'Pemantauan longsor desa',
                            textAlign: TextAlign.center,
                            style: textTheme.bodyLarge?.copyWith(
                              color: Colors.white,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
