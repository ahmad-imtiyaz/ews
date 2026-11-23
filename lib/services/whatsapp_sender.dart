import 'dart:io';

import 'package:flutter/services.dart';

/// 0812-2649-8705 atau +62 812... menjadi 6281226498705 untuk WhatsApp.
String internationalPhone(String raw) {
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  return digits.startsWith('0') ? '62${digits.substring(1)}' : digits;
}

/// 6281226498705 menjadi 0812-2649-8705 untuk ditampilkan ke warga.
String localPhone(String raw) {
  final international = internationalPhone(raw);
  final local = international.startsWith('62')
      ? '0${international.substring(2)}'
      : international;
  final groups = <String>[];
  for (var i = 0; i < local.length; i += 4) {
    groups.add(local.substring(i, i + 4 > local.length ? local.length : i + 4));
  }
  return groups.join('-');
}

class WhatsAppSender {
  static const _channel = MethodChannel('ews/whatsapp');

  /// Membuka chat [phone] dengan [text] terisi. Selalu langsung ke chat walau
  /// nomornya tidak ada di kontak pelapor, tapi tidak bisa membawa foto.
  /// `false` bila WhatsApp tidak terpasang atau bukan Android.
  static Future<bool> openChat({required String phone, required String text}) =>
      _invoke('openChat', {'phone': internationalPhone(phone), 'text': text});

  /// Membuka chat [phone] dengan teks dan semua foto terisi. Hanya langsung
  /// ke chat bila nomornya ada di kontak atau sudah pernah chat, jadi kirim
  /// [openChat] dulu. `false` bila WhatsApp tidak terpasang atau bukan
  /// Android.
  static Future<bool> send({
    required String phone,
    required String text,
    List<String> imagePaths = const [],
  }) => _invoke('send', {
    'phone': internationalPhone(phone),
    'text': text,
    'imagePaths': imagePaths,
  });

  static Future<bool> _invoke(String method, Map<String, Object> args) async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>(method, args) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
