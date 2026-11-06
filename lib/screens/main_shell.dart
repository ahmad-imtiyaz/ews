import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../data/sample_data.dart';
import 'home_screen.dart';
import 'report_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({
    super.key,
    required this.initialData,
    this.load = loadMonitoring,
    this.showMapTiles = true,
    this.locateOnReport = true,
  });

  final MonitoringData initialData;
  final Future<MonitoringData> Function() load;
  final bool showMapTiles;
  final bool locateOnReport;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  // Halaman Lapor baru dibuat saat pertama dibuka supaya izin lokasi tidak
  // diminta bersamaan dengan izin notifikasi di awal.
  final _opened = <int>{0};

  void _select(int index) {
    setState(() {
      _index = index;
      _opened.add(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    return Scaffold(
      body: Stack(
        children: [
          _FadePage(
            active: _index == 0,
            child: HomeScreen(
              initialData: widget.initialData,
              load: widget.load,
              showMapTiles: widget.showMapTiles,
            ),
          ),
          if (_opened.contains(1))
            _FadePage(
              active: _index == 1,
              child: ReportScreen(locateOnStart: widget.locateOnReport),
            ),
        ],
      ),
      bottomNavigationBar: keyboardOpen
          ? null
          : _FloatingNavBar(index: _index, onSelected: _select),
    );
  }
}

const _softDuration = Duration(milliseconds: 380);
const _softCurve = Curves.easeOutCubic;

/// Halaman muncul dengan fade dan sedikit naik. Halaman yang tidak aktif
/// tetap hidup (isian form tidak hilang) tapi disembunyikan setelah memudar.
class _FadePage extends StatefulWidget {
  const _FadePage({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<_FadePage> createState() => _FadePageState();
}

class _FadePageState extends State<_FadePage>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
    value: widget.active ? 1 : 0,
  )..addStatusListener((_) => setState(() {}));
  late final _curve = CurvedAnimation(parent: _controller, curve: _softCurve);
  late final _slide = Tween(
    begin: const Offset(0, 0.02),
    end: Offset.zero,
  ).animate(_curve);

  @override
  void didUpdateWidget(_FadePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active == oldWidget.active) return;
    widget.active ? _controller.forward() : _controller.reverse();
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hidden = _controller.isDismissed;
    return Offstage(
      offstage: hidden,
      child: TickerMode(
        enabled: !hidden,
        child: IgnorePointer(
          ignoring: !widget.active,
          child: FadeTransition(
            opacity: _curve,
            child: SlideTransition(position: _slide, child: widget.child),
          ),
        ),
      ),
    );
  }
}

/// Menu samping: ikon dengan teks di bawahnya. Beranda di tengah.
typedef _NavEntry = ({
  int index,
  IconData icon,
  IconData activeIcon,
  String label,
});

class _FloatingNavBar extends StatelessWidget {
  const _FloatingNavBar({required this.index, required this.onSelected});

  final int index;
  final ValueChanged<int> onSelected;

  static const _homeIndex = 0;

  // Menu baru ditambahkan ke kiri atau kanan supaya Beranda tetap di tengah.
  static const List<_NavEntry> _left = [
    (
      index: 1,
      icon: Icons.edit_note_outlined,
      activeIcon: Icons.edit_note_rounded,
      label: 'Lapor',
    ),
  ];
  static const List<_NavEntry> _right = [];

  static const _barHeight = 58.0;
  static const _maxBump = 22.0;
  static const _homeSize = 48.0;
  static const _centerGap = _homeSize + 32;

  /// Titik tengah tiap menu samping, dihitung dari kiri batang.
  static Map<int, double> _centers(double width) {
    final sideWidth = (width - _centerGap) / 2;
    return {
      for (final (i, entry) in _left.indexed)
        entry.index: sideWidth / _left.length * (i + 0.5),
      for (final (i, entry) in _right.indexed)
        entry.index:
            sideWidth + _centerGap + sideWidth / _right.length * (i + 0.5),
    };
  }

  @override
  Widget build(BuildContext context) {
    final onHome = index == _homeIndex;

    Widget side(List<_NavEntry> entries) => Expanded(
      child: Row(
        children: [
          for (final entry in entries)
            Expanded(
              child: _NavItem(
                icon: entry.index == index ? entry.activeIcon : entry.icon,
                label: entry.label,
                selected: entry.index == index,
                onTap: () => onSelected(entry.index),
              ),
            ),
        ],
      ),
    );

    return ColoredBox(
      color: AppColors.page,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(
            height: _barHeight + _maxBump,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final highlightX = _centers(width)[index] ?? width / 2;

                return TweenAnimationBuilder<double>(
                  tween: Tween(end: onHome ? 1 : 0),
                  duration: _softDuration,
                  curve: _softCurve,
                  builder: (context, raise, _) {
                    // 1: tombol menonjol di atas batang, 0: masuk ke batang.
                    final buttonTop = lerpDouble(_maxBump + 5, 3, raise)!;
                    final bump = lerpDouble(2, _maxBump, raise)!;

                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _BarPainter(barTop: _maxBump, bump: bump),
                          ),
                        ),
                        AnimatedPositioned(
                          duration: _softDuration,
                          curve: _softCurve,
                          top: _maxBump + 5,
                          left: highlightX - 34,
                          child: AnimatedOpacity(
                            duration: _softDuration,
                            curve: _softCurve,
                            opacity: onHome ? 0 : 1,
                            child: Container(
                              width: 68,
                              height: _barHeight - 10,
                              decoration: BoxDecoration(
                                color: AppColors.iconTile,
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                        ),
                        Positioned.fill(
                          top: _maxBump,
                          child: Row(
                            children: [
                              side(_left),
                              const SizedBox(width: _centerGap),
                              side(_right),
                            ],
                          ),
                        ),
                        Positioned(
                          top: buttonTop,
                          left: (width - _homeSize) / 2,
                          child: Transform.scale(
                            scale: lerpDouble(0.86, 1, raise),
                            child: _HomeButton(
                              size: _homeSize,
                              selected: onHome,
                              elevation: lerpDouble(0, 4, raise)!,
                              onTap: () => onSelected(_homeIndex),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Batang putih dengan tonjolan di tengah untuk tombol Beranda.
class _BarPainter extends CustomPainter {
  const _BarPainter({required this.barTop, required this.bump});

  final double barTop;

  /// Tinggi tonjolan di atas batang.
  final double bump;

  @override
  void paint(Canvas canvas, Size size) {
    const radius = 20.0;
    const bumpHalf = 54.0;
    final top = barTop;
    final peak = barTop - bump;
    final cx = size.width / 2;

    final path = Path()
      ..moveTo(0, top + radius)
      ..quadraticBezierTo(0, top, radius, top)
      ..lineTo(cx - bumpHalf, top)
      ..cubicTo(cx - bumpHalf * 0.55, top, cx - bumpHalf * 0.62, peak, cx, peak)
      ..cubicTo(
        cx + bumpHalf * 0.62,
        peak,
        cx + bumpHalf * 0.55,
        top,
        cx + bumpHalf,
        top,
      )
      ..lineTo(size.width - radius, top)
      ..quadraticBezierTo(size.width, top, size.width, top + radius)
      ..lineTo(size.width, size.height - radius)
      ..quadraticBezierTo(
        size.width,
        size.height,
        size.width - radius,
        size.height,
      )
      ..lineTo(radius, size.height)
      ..quadraticBezierTo(0, size.height, 0, size.height - radius)
      ..close();

    canvas.drawShadow(path, const Color(0x40000000), 8, false);
    canvas.drawPath(path, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_BarPainter oldDelegate) =>
      oldDelegate.barTop != barTop || oldDelegate.bump != bump;
}

class _HomeButton extends StatelessWidget {
  const _HomeButton({
    required this.size,
    required this.selected,
    required this.elevation,
    required this.onTap,
  });

  final double size;
  final bool selected;
  final double elevation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Beranda',
      child: Semantics(
        button: true,
        selected: selected,
        label: 'Beranda',
        excludeSemantics: true,
        child: Material(
          color: AppColors.ink,
          shape: const CircleBorder(),
          elevation: elevation,
          shadowColor: const Color(0x66000000),
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: SizedBox.square(
              dimension: size,
              child: Icon(
                selected ? Icons.home_rounded : Icons.home_outlined,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.ink : AppColors.inkSoft;
    final style = Theme.of(context).textTheme.labelLarge!.copyWith(
      color: color,
      fontSize: 11,
      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
    );

    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.3,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TweenAnimationBuilder<Color?>(
                tween: ColorTween(end: color),
                duration: _softDuration,
                curve: _softCurve,
                builder: (_, value, _) => Icon(icon, color: value, size: 22),
              ),
              const SizedBox(height: 3),
              AnimatedDefaultTextStyle(
                duration: _softDuration,
                curve: _softCurve,
                style: style,
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
