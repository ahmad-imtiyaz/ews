import 'dart:convert';

import 'package:http/http.dart' as http;

import '../data/ews_data.dart';

class EwsApi {
  EwsApi(this.baseUrl, {http.Client? client, this.onNewBody})
    : _client = client ?? http.Client();

  final String baseUrl;

  /// Dipanggil dengan isi balasan yang baru dan sudah terbaca, untuk disimpan.
  final void Function(String body)? onNewBody;
  final http.Client _client;
  String? _etag;
  EwsData? _last;

  Future<EwsData> fetch() async {
    final last = _last;
    final response = await _client
        .get(
          Uri.parse('$baseUrl/api/ews/data'),
          headers: {
            'Accept': 'application/json',
            // Bila data belum berubah server membalas 304 tanpa isi, jadi
            // pengecekan tiap 10 detik hampir tidak memakan kuota.
            if (_etag != null && last != null) 'If-None-Match': _etag!,
          },
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 304 && last != null) return last;
    if (response.statusCode != 200) {
      throw http.ClientException(
        'Server membalas kode ${response.statusCode}',
        response.request?.url,
      );
    }

    // bodyBytes, bukan body: tanpa utf8.decode simbol "°" terbaca "Â°".
    final body = utf8.decode(response.bodyBytes);
    final data = EwsData.fromJson(jsonDecode(body) as Map<String, dynamic>);
    _etag = response.headers['etag'];
    onNewBody?.call(body);
    return _last = data;
  }

  void close() => _client.close();
}
