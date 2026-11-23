import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import 'whatsapp_sender.dart';

/// Nomor dari balasan `/api/ews/pelaporan`, dalam format 62..., atau `null`
/// bila server belum mengisi nomor atau isinya bukan nomor HP.
String? parseReportNumber(Map<String, dynamic> json) {
  final raw = json['nomor'];
  if (json['tersedia'] != true || raw is! String) return null;
  final number = internationalPhone(raw);
  return RegExp(r'^62\d{8,13}$').hasMatch(number) ? number : null;
}

/// Nomor WhatsApp penanggung jawab, diatur dari web Laravel.
///
/// Urutannya: nomor terbaru dari server, lalu nomor terakhir yang tersimpan
/// di HP, lalu [reportWhatsAppNumber]. Sinyal putus atau server mati tidak
/// pernah membuat laporan warga kehilangan tujuan.
class ReportContact {
  ReportContact({this.baseUrl = ewsBaseUrl, this.client});

  static const _savedKey = 'report.whatsapp';

  final String baseUrl;

  /// Diisi di tes. Bila kosong, tiap pengambilan memakai klien baru.
  final http.Client? client;
  final number = ValueNotifier<String>(reportWhatsAppNumber);
  bool _savedLoaded = false;

  Future<void> refresh() async {
    if (!_savedLoaded) {
      _savedLoaded = true;
      try {
        final saved = (await SharedPreferences.getInstance()).getString(
          _savedKey,
        );
        if (saved != null) number.value = saved;
      } catch (_) {}
    }

    final client = this.client ?? http.Client();
    try {
      final response = await client
          .get(
            Uri.parse('$baseUrl/api/ews/pelaporan'),
            headers: {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return;
      final fresh = parseReportNumber(
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>,
      );
      if (fresh == null) return;
      number.value = fresh;
      await (await SharedPreferences.getInstance()).setString(_savedKey, fresh);
    } catch (_) {
      // Tanpa sinyal atau balasan rusak: tetap pakai nomor yang ada.
    } finally {
      if (this.client == null) client.close();
    }
  }

  static const _chattedKey = 'report.chatted';

  /// Sudah pernah ada chat dari HP ini ke [phone]. WhatsApp hanya mau
  /// langsung membuka chat berfoto untuk nomor yang ada di kontak atau sudah
  /// pernah di-chat; selain itu muncul menu "Kirim ke...".
  Future<bool> hasChatted(String phone) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getStringList(_chattedKey) ?? const []).contains(
        internationalPhone(phone),
      );
    } catch (_) {
      return false;
    }
  }

  Future<void> markChatted(String phone) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final chatted = prefs.getStringList(_chattedKey) ?? [];
      final number = internationalPhone(phone);
      if (chatted.contains(number)) return;
      await prefs.setStringList(_chattedKey, [...chatted, number]);
    } catch (_) {}
  }
}

final reportContact = ReportContact();
