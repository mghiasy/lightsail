import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

class SshAccess {
  SshAccess({
    required this.host,
    required this.username,
    required this.privateKeyPem,
  });

  final String host;
  final String username;
  final String privateKeyPem;
}

Future<String> runSsh(
  SshAccess access,
  String command, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  final socket = await SSHSocket.connect(
    access.host,
    22,
    timeout: const Duration(seconds: 15),
  );
  final client = SSHClient(
    socket,
    username: access.username,
    identities: [
      ...SSHKeyPair.fromPem(access.privateKeyPem),
    ],
  );

  try {
    final session = await client.execute(command);
    final stdout = await utf8.decoder
        .bind(session.stdout)
        .fold<StringBuffer>(StringBuffer(), (b, c) => b..write(c));
    final stderr = await utf8.decoder
        .bind(session.stderr)
        .fold<StringBuffer>(StringBuffer(), (b, c) => b..write(c));
    await session.done.timeout(timeout);
    final out = stdout.toString();
    final err = stderr.toString();
    final exit = session.exitCode ?? 0;
    if (exit != 0) {
      throw Exception((err.isNotEmpty ? err : out).trim().isEmpty
          ? 'SSH command failed ($exit)'
          : (err.isNotEmpty ? err : out).trim());
    }
    return out;
  } finally {
    client.close();
    await socket.close();
  }
}

Future<String> runSshScript(
  SshAccess access,
  String script, {
  Duration timeout = const Duration(minutes: 20),
}) async {
  final socket = await SSHSocket.connect(
    access.host,
    22,
    timeout: const Duration(seconds: 20),
  );
  final client = SSHClient(
    socket,
    username: access.username,
    identities: [
      ...SSHKeyPair.fromPem(access.privateKeyPem),
    ],
  );

  try {
    final session = await client.execute('bash -s');
    session.stdin.add(Uint8List.fromList(utf8.encode(script)));
    await session.stdin.close();

    final stdout = StringBuffer();
    final stderr = StringBuffer();
    final outSub = utf8.decoder.bind(session.stdout).listen(stdout.write);
    final errSub = utf8.decoder.bind(session.stderr).listen(stderr.write);

    await session.done.timeout(timeout);
    await outSub.cancel();
    await errSub.cancel();

    final combined = '${stdout.toString()}\n${stderr.toString()}';
    final exit = session.exitCode ?? 0;
    if (exit != 0 && !combined.contains('---ACCESS_TXT---')) {
      throw Exception(combined.trim().isEmpty
          ? 'SSH script failed ($exit)'
          : combined.trim());
    }
    return combined;
  } finally {
    client.close();
    await socket.close();
  }
}
