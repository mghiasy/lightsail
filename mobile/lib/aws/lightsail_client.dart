import 'dart:convert';

import 'package:http/http.dart' as http;

import 'sig_v4.dart';

class LightsailException implements Exception {
  LightsailException(this.message);
  final String message;
  @override
  String toString() => message;
}

class LightsailClient {
  LightsailClient({
    required this.accessKeyId,
    required this.secretAccessKey,
    this.region = 'us-west-2',
  }) : _signer = AwsSigV4(
          accessKeyId: accessKeyId,
          secretAccessKey: secretAccessKey,
          region: region,
        );

  final String accessKeyId;
  final String secretAccessKey;
  final String region;
  final AwsSigV4 _signer;

  Uri get _endpoint => Uri.parse('https://lightsail.$region.amazonaws.com/');

  Future<Map<String, dynamic>> call(
    String operation,
    Map<String, dynamic> body,
  ) async {
    final payload = jsonEncode(body);
    final target = 'Lightsail_20161128.$operation';
    final headers = _signer.signHeaders(
      method: 'POST',
      uri: _endpoint,
      payload: payload,
      amzTarget: target,
    );

    final response = await http.post(
      _endpoint,
      headers: headers,
      body: payload,
    );

    Map<String, dynamic> decoded = {};
    if (response.body.isNotEmpty) {
      try {
        decoded = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {
        throw LightsailException(
          'Invalid AWS response (${response.statusCode}): ${response.body}',
        );
      }
    }

    if (response.statusCode >= 400) {
      final msg = decoded['message'] ??
          decoded['Message'] ??
          decoded['__type'] ??
          response.body;
      throw LightsailException('$operation failed: $msg');
    }
    return decoded;
  }

  Future<bool> instanceExists(String name) async {
    try {
      await call('GetInstance', {'instanceName': name});
      return true;
    } on LightsailException catch (e) {
      if (e.message.toLowerCase().contains('notfound') ||
          e.message.toLowerCase().contains('does not exist')) {
        return false;
      }
      // Some errors are NotFoundException typed
      if (e.message.contains('NotFoundException')) return false;
      rethrow;
    }
  }

  Future<String?> getInstanceState(String name) async {
    try {
      final data = await call('GetInstance', {'instanceName': name});
      return data['instance']?['state']?['name'] as String?;
    } on LightsailException catch (e) {
      if (e.message.contains('NotFoundException') ||
          e.message.toLowerCase().contains('does not exist')) {
        return null;
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> getStaticIp(String name) async {
    try {
      final data = await call('GetStaticIp', {'staticIpName': name});
      return data['staticIp'] as Map<String, dynamic>?;
    } on LightsailException catch (e) {
      if (e.message.contains('NotFoundException') ||
          e.message.toLowerCase().contains('does not exist')) {
        return null;
      }
      rethrow;
    }
  }
}
