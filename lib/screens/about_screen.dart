import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../app_theme.dart';
import '../config.dart';
import '../services/notification_inbox.dart';
import '../widgets/brand_logo.dart';
import '../widgets/section_card.dart';
import '../widgets/top_bar.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static final _packageInfo = PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final body = textTheme.bodyLarge;
    final soft = textTheme.bodyMedium?.copyWith(color: AppColors.inkSoft);
    const gap = SizedBox(height: 16);

    Widget paragraph(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: body),
    );

    return Scaffold(
      appBar: const TopBar(title: 'Tentang aplikasi', backLabel: 'Kembali'),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          MediaQuery.paddingOf(context).bottom + 16,
        ),
        children: [
          const Align(
            alignment: AlignmentDirectional.centerStart,
            child: BrandLogo(height: 56),
          ),
          const SizedBox(height: 4),
          FutureBuilder(
            future: _packageInfo,
            builder: (context, snapshot) => Text(switch (snapshot.data) {
              final info? => 'Versi ${info.version} (${info.buildNumber})',
              null => '',
            }, style: soft),
          ),
          gap,
          SectionCard(
            children: [
              paragraph(
                'EWS Lumeneng menampilkan kondisi lereng Desa Lumeneng dari '
                'alat EWS di lapangan, dan memberi tanda saat statusnya '
                'berubah.',
              ),
              Text(
                'Ini alat bantu pemantauan warga, bukan peringatan resmi BPBD. '
                'Saat ragu, utamakan keselamatan dan ikuti arahan perangkat '
                'desa.',
                style: body?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          gap,
          SectionCard(
            title: 'Keadaan darurat',
            children: [
              paragraph('Telepon 112, layanan darurat nasional (gratis).'),
              Text(
                'Untuk melaporkan tanda longsor ke penanggung jawab EWS, '
                'pakai menu Lapor.',
                style: body,
              ),
            ],
          ),
          gap,
          SectionCard(
            title: 'Sumber data',
            children: [
              paragraph(
                'Status dan bacaan sensor dari server EWS desa '
                '(${Uri.parse(ewsBaseUrl).host}), dicek tiap '
                '${ewsRefreshInterval.inSeconds} detik selama aplikasi dibuka.',
              ),
              paragraph(
                'Zona rawan longsor dan batas desa dari Kajian Pemetaan '
                'Bencana Desa Lumeneng 2024 oleh LPBI NU Kabupaten Pekalongan '
                'dan Ringan Tangan Indonesia.',
              ),
              Text(
                'Peta dasar: OpenStreetMap, Esri, dan OpenTopoMap.',
                style: body,
              ),
            ],
          ),
          gap,
          SectionCard(
            title: 'Data dan privasi',
            children: [
              paragraph('Aplikasi ini tidak memakai akun.'),
              paragraph(
                'Lokasi HP dipakai untuk titik Anda di peta, dan ikut dalam '
                'laporan bila Anda mengirimnya. Foto dan isi laporan hanya '
                'terkirim lewat WhatsApp saat Anda sendiri menekan kirim.',
              ),
              paragraph(
                'Status terakhir dan ${NotificationInbox.maxEntries} '
                'notifikasi terakhir disimpan di HP ini, supaya tetap terbaca '
                'saat tidak ada sinyal.',
              ),
              Text(
                'Bila aplikasi mengalami galat, laporan teknis (jenis HP dan '
                'letak galat di kode, tanpa nama, lokasi, atau foto) dikirim '
                'ke pengembang lewat Firebase Crashlytics.',
                style: body,
              ),
            ],
          ),
          gap,
          Text(
            'Dibuat oleh tim KKN untuk warga Desa Lumeneng, Kecamatan '
            'Paninggaran, Kabupaten Pekalongan.',
            style: soft,
          ),
        ],
      ),
    );
  }
}
