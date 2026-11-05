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
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
                    child: const Icon(
                      Icons.chevron_left,
                      semanticLabel: 'Kembali',
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'Buat laporan',
                      textAlign: TextAlign.center,
                      style: textTheme.titleLarge,
                    ),
                  ),
                  const SizedBox(width: 44),
                ],
              ),
              const SizedBox(height: 20),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Formulir laporan sedang dibuat',
                        style: textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Untuk sementara, bila melihat tanda longsor, segera '
                        'menjauh dan hubungi petugas desa.',
                        style: textTheme.bodyLarge,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
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
