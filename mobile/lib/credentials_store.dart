import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class CredentialsStore {
  static const _accessKeyId = 'aws_access_key_id';
  static const _secretAccessKey = 'aws_secret_access_key';
  static const _region = 'aws_region';

  final _storage = const FlutterSecureStorage();

  Future<AwsCredentials?> load() async {
    final id = await _storage.read(key: _accessKeyId);
    final secret = await _storage.read(key: _secretAccessKey);
    final region = await _storage.read(key: _region) ?? 'us-west-2';
    if (id == null || secret == null || id.isEmpty || secret.isEmpty) {
      return null;
    }
    return AwsCredentials(
      accessKeyId: id,
      secretAccessKey: secret,
      region: region,
    );
  }

  Future<void> save(AwsCredentials creds) async {
    await _storage.write(key: _accessKeyId, value: creds.accessKeyId);
    await _storage.write(key: _secretAccessKey, value: creds.secretAccessKey);
    await _storage.write(key: _region, value: creds.region);
  }

  Future<void> clear() async {
    await _storage.delete(key: _accessKeyId);
    await _storage.delete(key: _secretAccessKey);
    await _storage.delete(key: _region);
  }
}

class AwsCredentials {
  AwsCredentials({
    required this.accessKeyId,
    required this.secretAccessKey,
    this.region = 'us-west-2',
  });

  final String accessKeyId;
  final String secretAccessKey;
  final String region;
}
