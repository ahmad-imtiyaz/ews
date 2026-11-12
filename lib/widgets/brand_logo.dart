import 'package:flutter/material.dart';

/// Logo EWS Lumeneng beserta tulisannya.
///
/// Gambar dibuat oleh tool/generate_brand_assets.py. Lebarnya ikut
/// perbandingan gambar, jadi logo tidak tertarik dan tempatnya sudah tersedia
/// sebelum gambar selesai dimuat.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, required this.height, this.onDark = false});

  final double height;

  /// Versi untuk latar gelap: tulisan putih, biru gunung dicerahkan.
  final bool onDark;

  static const _aspectRatio = 686 / 228;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      onDark
          ? 'assets/brand/logo_wordmark_light.png'
          : 'assets/brand/logo_wordmark.png',
      height: height,
      width: height * _aspectRatio,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      semanticLabel: 'EWS Lumeneng',
    );
  }
}
