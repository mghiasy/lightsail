import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Minimal AWS Signature Version 4 signer for Lightsail JSON 1.1 APIs.
class AwsSigV4 {
  AwsSigV4({
    required this.accessKeyId,
    required this.secretAccessKey,
    required this.region,
    this.service = 'lightsail',
  });

  final String accessKeyId;
  final String secretAccessKey;
  final String region;
  final String service;

  Map<String, String> signHeaders({
    required String method,
    required Uri uri,
    required String payload,
    required String amzTarget,
    DateTime? now,
  }) {
    final timestamp = now?.toUtc() ?? DateTime.now().toUtc();
    final amzDate = _formatAmzDate(timestamp);
    final dateStamp = amzDate.substring(0, 8);
    final host = uri.host;
    final payloadHash = sha256.convert(utf8.encode(payload)).toString();

    final headers = <String, String>{
      'content-type': 'application/x-amz-json-1.1',
      'host': host,
      'x-amz-date': amzDate,
      'x-amz-target': amzTarget,
    };

    final signedHeaderNames = headers.keys.toList()..sort();
    final canonicalHeaders = signedHeaderNames
        .map((k) => '${k.toLowerCase()}:${headers[k]!.trim()}\n')
        .join();
    final signedHeaders = signedHeaderNames.join(';');

    final canonicalRequest = [
      method.toUpperCase(),
      uri.path.isEmpty ? '/' : uri.path,
      '', // query string
      canonicalHeaders,
      signedHeaders,
      payloadHash,
    ].join('\n');

    final credentialScope = '$dateStamp/$region/$service/aws4_request';
    final stringToSign = [
      'AWS4-HMAC-SHA256',
      amzDate,
      credentialScope,
      sha256.convert(utf8.encode(canonicalRequest)).toString(),
    ].join('\n');

    final signingKey = _getSignatureKey(secretAccessKey, dateStamp, region, service);
    final signature = Hmac(sha256, signingKey)
        .convert(utf8.encode(stringToSign))
        .bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();

    headers['authorization'] =
        'AWS4-HMAC-SHA256 Credential=$accessKeyId/$credentialScope, '
        'SignedHeaders=$signedHeaders, Signature=$signature';
    return headers;
  }

  static List<int> _sign(List<int> key, String message) =>
      Hmac(sha256, key).convert(utf8.encode(message)).bytes;

  static List<int> _getSignatureKey(
    String key,
    String dateStamp,
    String regionName,
    String serviceName,
  ) {
    final kDate = _sign(utf8.encode('AWS4$key'), dateStamp);
    final kRegion = _sign(kDate, regionName);
    final kService = _sign(kRegion, serviceName);
    return _sign(kService, 'aws4_request');
  }

  static String _formatAmzDate(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}${two(dt.month)}${two(dt.day)}T'
        '${two(dt.hour)}${two(dt.minute)}${two(dt.second)}Z';
  }
}
