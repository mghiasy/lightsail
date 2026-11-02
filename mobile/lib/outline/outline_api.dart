import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Outline Management API helper (self-signed certs allowed).
class OutlineApi {
  OutlineApi(this.apiUrl);

  final String apiUrl;

  http.Client _client() {
    final io = HttpClient()
      ..badCertificateCallback = (cert, host, port) => true;
    return IOClient(io);
  }

  Uri _uri(String path) {
    final base = apiUrl.endsWith('/') ? apiUrl.substring(0, apiUrl.length - 1) : apiUrl;
    return Uri.parse('$base$path');
  }

  Future<List<Map<String, dynamic>>> listAccessKeys() async {
    final client = _client();
    try {
      final res = await client.get(_uri('/access-keys')).timeout(const Duration(seconds: 20));
      if (res.statusCode >= 400) {
        throw Exception('List access keys failed: ${res.body}');
      }
      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      final keys = (decoded['accessKeys'] as List?) ?? [];
      return keys.cast<Map<String, dynamic>>();
    } finally {
      client.close();
    }
  }

  Future<String?> firstAccessUrl() async {
    final keys = await listAccessKeys();
    for (final key in keys) {
      final url = key['accessUrl'] as String?;
      if (url != null && url.isNotEmpty) return url;
    }
    return null;
  }

  Future<dynamic> firstKeyId() async {
    final keys = await listAccessKeys();
    if (keys.isEmpty) return null;
    return keys.first['id'] ?? 0;
  }

  Future<void> renameKey(dynamic id, String name) async {
    final client = _client();
    try {
      final res = await client
          .put(
            _uri('/access-keys/$id/name'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'name': name}),
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode >= 400) {
        throw Exception('Rename failed: ${res.body}');
      }
    } finally {
      client.close();
    }
  }

  Future<void> setDataLimitBytes(dynamic id, int bytes) async {
    final client = _client();
    try {
      final res = await client
          .put(
            _uri('/access-keys/$id/data-limit'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'limit': {'bytes': bytes},
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode >= 400) {
        throw Exception('Set data limit failed: ${res.body}');
      }
    } finally {
      client.close();
    }
  }
}
