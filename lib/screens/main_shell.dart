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
      body: IndexedStack(
        index: _index,
        children: [
          HomeScreen(
            initialData: widget.initialData,
            load: widget.load,
            showMapTiles: widget.showMapTiles,
          ),
          if (_opened.contains(1))
            ReportScreen(locateOnStart: widget.locateOnReport)
          else
            const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: keyboardOpen
          ? null
          : _FloatingNavBar(index: _index, onSelected: _select),
    );
  }
}

class _FloatingNavBar extends StatelessWidget {
  const _FloatingNavBar({required this.index, required this.onSelected});

  final int index;
  final ValueChanged<int> onSelected;

  static const _items = [
    (Icons.home_outlined, Icons.home_rounded, 'Beranda'),
    (Icons.edit_note_outlined, Icons.edit_note_rounded, 'Lapor'),
  ];

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.page,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1A000000),
                  blurRadius: 16,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Row(
                children: [
                  for (final (i, (icon, activeIcon, label)) in _items.indexed)
                    Expanded(
                      child: _NavItem(
                        icon: i == index ? activeIcon : icon,
                        label: label,
                        selected: i == index,
                        onTap: () => onSelected(i),
                      ),
                    ),
                ],
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
    final color = selected ? Colors.white : AppColors.ink;

    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? AppColors.ink : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: color, size: 22),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge
                          ?.copyWith(color: color),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
