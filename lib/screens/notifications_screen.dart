import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../services/notification_inbox.dart';
import '../services/notification_service.dart';
import '../widgets/map_markers.dart';
import '../widgets/top_bar.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({
    super.key,
    required this.entries,
    required this.service,
  });

  final List<NotificationEntry> entries;
  final NotificationService service;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool? _allowed;
  bool _askedAgain = false;

  @override
  void initState() {
    super.initState();
    _refreshPermission();
  }

  Future<void> _refreshPermission() async {
    final allowed = await widget.service.isAllowed();
    if (mounted) setState(() => _allowed = allowed);
  }

  Future<void> _askPermission() async {
    final allowed = await widget.service.requestPermission();
    if (mounted) {
      setState(() {
        _allowed = allowed;
        _askedAgain = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: const TopBar(title: 'Notifikasi', backLabel: 'Kembali'),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          MediaQuery.paddingOf(context).bottom + 16,
        ),
        children: [
          if (_allowed == false) ...[
            _PermissionCard(askedAgain: _askedAgain, onAllow: _askPermission),
            const SizedBox(height: 16),
          ],
          Text(
            'Isi di sini masih contoh dan tersimpan sampai aplikasi ditutup.',
            style: textTheme.bodyMedium?.copyWith(color: AppColors.inkSoft),
          ),
          const SizedBox(height: 12),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: widget.entries.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      'Belum ada notifikasi. Perubahan status titik pantau '
                      'akan muncul di sini.',
                      style: textTheme.bodyLarge?.copyWith(
                        color: AppColors.inkSoft,
                      ),
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (index, entry)
                          in widget.entries.reversed.indexed) ...[
                        if (index > 0) const Divider(indent: 56, endIndent: 14),
                        _NotificationRow(entry: entry),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({required this.askedAgain, required this.onAllow});

  final bool askedAgain;
  final VoidCallback onAllow;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Notifikasi HP belum diizinkan', style: textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              askedAgain
                  ? 'Bila jendela izin tidak muncul, aktifkan notifikasi EWS '
                        'Lumeneng lewat Pengaturan HP.'
                  : 'Izinkan supaya peringatan muncul di HP dengan suaranya.',
              style: textTheme.bodyMedium?.copyWith(color: AppColors.inkSoft),
            ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: onAllow,
              child: const Text('Izinkan notifikasi'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationRow extends StatelessWidget {
  const _NotificationRow({required this.entry});

  final NotificationEntry entry;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StatusShape(status: entry.status, size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.title, style: textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(entry.body, style: textTheme.bodyLarge),
                const SizedBox(height: 2),
                Text(
                  entry.time,
                  style: textTheme.bodyMedium?.copyWith(
                    color: AppColors.inkSoft,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
