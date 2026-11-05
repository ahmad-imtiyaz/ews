import 'package:flutter/material.dart';

// TODO: ganti dengan formulir laporan warga.
class ReportPlaceholderScreen extends StatelessWidget {
  const ReportPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              Text(
                'Formulir laporan sedang dibuat',
                style: textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(
                'Untuk sementara, bila melihat tanda longsor, segera menjauh '
                'dan hubungi petugas desa.',
                style: textTheme.bodyLarge,
              ),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Kembali ke peta'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
