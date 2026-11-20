import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../data/ews_data.dart';

/// Balasan server terakhir yang tersimpan di HP, supaya aplikasi yang dibuka
/// tanpa sinyal tetap menampilkan kondisi terakhir beserta umurnya.
///
/// Gagal membaca atau menulis tidak pernah menghentikan aplikasi: tanpa
/// simpanan, aplikasi hanya kembali menunggu server seperti dulu.
class EwsCache {
  static const _bodyKey = 'ews.body';
  static const _checkedAtKey = 'ews.checkedAt';

  Future<({EwsData data, DateTime checkedAt})?> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final body = prefs.getString(_bodyKey);
      final checkedAt = DateTime.tryParse(prefs.getString(_checkedAtKey) ?? '');
      if (body == null || checkedAt == null) return null;
      final data = EwsData.fromJson(jsonDecode(body) as Map<String, dynamic>);
      return (data: data, checkedAt: checkedAt);
    } catch (_) {
      // Simpanan rusak atau bentuk data server sudah berubah.
      return null;
    }
  }

  /// [body] hanya diisi saat server mengirim data baru (bukan 304).
  Future<void> save({String? body, required DateTime checkedAt}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (body != null) await prefs.setString(_bodyKey, body);
      await prefs.setString(_checkedAtKey, checkedAt.toIso8601String());
    } catch (_) {}
  }
}
