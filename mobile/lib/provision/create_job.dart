import '../aws/lightsail_client.dart';
import '../outline/outline_api.dart';
import '../ssh/remote_exec.dart';
import 'constants.dart';

typedef ProgressFn = void Function(String step, String message);

class CreateResult {
  CreateResult({
    required this.accessKey,
    required this.outline,
  });

  final String accessKey;
  final Map<String, String> outline;
}

class CreateJob {
  CreateJob({
    required this.client,
    required this.onProgress,
  });

  final LightsailClient client;
  final ProgressFn onProgress;

  Future<CreateResult> run() async {
    await _createInstance();
    await _waitUntilRunning();
    final publicIp = await _allocateAndAttachStaticIp();
    final access = await _waitForSsh(publicIp);
    final installOutput = await _installOutline(access, publicIp);
    final parsed = _parseOutlineOutput(installOutput, publicIp);
    await _openFirewallPorts(
      parsed['managementPort'] as int,
      parsed['accessKeyPort'] as int,
    );

    final outline = Map<String, String>.from(parsed['outline'] as Map);
    final accessKey = await _configureOutlineKey(outline);

    onProgress('done', 'Outline access key ready');
    return CreateResult(accessKey: accessKey, outline: outline);
  }

  Future<void> _createInstance() async {
    if (await client.instanceExists(instanceName)) {
      onProgress('create', 'Instance $instanceName already exists — skipping create');
      onProgress('created', 'Instance created');
      return;
    }
    onProgress('create', 'Creating instance $instanceName…');
    await client.call('CreateInstances', {
      'instanceNames': [instanceName],
      'availabilityZone': availabilityZone,
      'blueprintId': blueprintId,
      'bundleId': bundleId,
    });
    onProgress('created', 'Instance created');
  }

  Future<void> _waitUntilRunning() async {
    onProgress('waiting', 'Waiting until instance is running…');
    while (true) {
      final state = await client.getInstanceState(instanceName);
      onProgress('waiting', 'Instance state: $state');
      if (state == 'running') {
        onProgress('running', 'Instance running');
        return;
      }
      if (state == null ||
          {'stopped', 'stopping', 'terminated', 'terminating', 'error'}
              .contains(state)) {
        throw Exception('Instance entered unexpected state: $state');
      }
      await Future<void>.delayed(const Duration(seconds: 5));
    }
  }

  Future<String> _allocateAndAttachStaticIp() async {
    var existing = await client.getStaticIp(staticIpName);
    if (existing != null) {
      onProgress('ip_create', 'Static IP $staticIpName already exists — skipping allocate');
      onProgress('ip_created', 'Static IP created');
    } else {
      onProgress('ip_create', 'Creating static IP $staticIpName…');
      await client.call('AllocateStaticIp', {'staticIpName': staticIpName});
      onProgress('ip_created', 'Static IP created');
      existing = await client.getStaticIp(staticIpName) ?? {};
    }

    onProgress('ip_attach', 'Attaching static IP to $instanceName…');
    if (existing['isAttached'] == true &&
        existing['attachedTo'] == instanceName) {
      onProgress('ip_attached', 'Static IP already attached');
    } else {
      await client.call('AttachStaticIp', {
        'staticIpName': staticIpName,
        'instanceName': instanceName,
      });
      onProgress('ip_attached', 'Static IP attached');
    }

    final data = await client.getStaticIp(staticIpName);
    final ip = data?['ipAddress'] as String?;
    if (ip == null || ip.isEmpty) {
      throw Exception('Could not read static IP address');
    }
    return ip;
  }

  Future<String> _downloadDefaultPrivateKey() async {
    final data = await client.call('DownloadDefaultKeyPair', {});
    var pem = (data['privateKeyBase64'] ?? data['privateKey'] ?? '') as String;
    if (!pem.startsWith('-----BEGIN')) {
      throw Exception('Could not download Lightsail default SSH key pair');
    }
    if (!pem.endsWith('\n')) pem = '$pem\n';
    return pem;
  }

  Future<SshAccess> _waitForSsh(String publicIp) async {
    onProgress('ssh', 'Waiting for SSH on $publicIp…');
    final privateKey = await _downloadDefaultPrivateKey();
    const username = 'ubuntu';
    final deadline = DateTime.now().add(const Duration(seconds: 180));
    var attempt = 0;
    var lastError = 'timed out';

    while (DateTime.now().isBefore(deadline)) {
      attempt += 1;
      try {
        final access = SshAccess(
          host: publicIp,
          username: username,
          privateKeyPem: privateKey,
        );
        await runSsh(access, 'echo ready', timeout: const Duration(seconds: 20));
        onProgress('ssh', 'SSH ready ($username@$publicIp)');
        return access;
      } catch (e) {
        lastError = e.toString().trim().split('\n').last;
        final remaining = deadline.difference(DateTime.now()).inSeconds;
        onProgress(
          'ssh',
          'SSH not ready (attempt $attempt, ${remaining}s left): $lastError',
        );
        await Future<void>.delayed(const Duration(seconds: 5));
      }
    }
    throw Exception('SSH not ready after 180s: $lastError');
  }

  Future<String> _installOutline(SshAccess access, String publicIp) async {
    onProgress('outline', 'Installing Docker (if needed) and Outline…');
    final remote = '''
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

for i in \$(seq 1 60); do
  if sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 \\
     || sudo fuser /var/lib/apt/lists/lock >/dev/null 2>&1; then
    echo "Waiting for apt lock… (\$i)"
    sleep 5
  else
    break
  fi
done

if ! command -v docker >/dev/null 2>&1; then
  echo "Installing Docker…"
  curl -fsSL https://get.docker.com | sudo sh
fi
sudo systemctl enable --now docker

sudo docker rm -f shadowbox watchtower >/dev/null 2>&1 || true

wget -qO /tmp/install_server.sh '$outlineInstallUrl'
sudo bash /tmp/install_server.sh --hostname '$publicIp'

echo '---ACCESS_TXT---'
sudo cat /opt/outline/access.txt
echo '---SERVER_CONFIG---'
sudo cat /opt/outline/persisted-state/shadowbox_server_config.json 2>/dev/null || true
''';
    final output = await runSshScript(access, remote);
    final cleaned = output.replaceAll(ansiRe, '');
    if (!cleaned.contains('---ACCESS_TXT---')) {
      throw Exception(cleaned.trim().isEmpty ? 'Outline install failed' : cleaned.trim());
    }
    onProgress('outline', 'Outline install finished');
    return cleaned;
  }

  Map<String, dynamic> _parseOutlineOutput(String output, String publicIp) {
    String accessTxt = '';
    if (output.contains('---ACCESS_TXT---')) {
      accessTxt = output.split('---ACCESS_TXT---').last;
      if (accessTxt.contains('---SERVER_CONFIG---')) {
        accessTxt = accessTxt.split('---SERVER_CONFIG---').first;
      }
    }

    String? apiUrl;
    String? certSha;
    for (final line in accessTxt.split('\n')) {
      final t = line.trim();
      if (t.startsWith('apiUrl:')) {
        apiUrl = t.substring('apiUrl:'.length).trim();
      } else if (t.startsWith('certSha256:')) {
        certSha = t.substring('certSha256:'.length).trim();
      }
    }

    if (apiUrl == null || certSha == null) {
      final match = outlineJsonRe.firstMatch(output);
      if (match == null) {
        throw Exception('Could not find Outline apiUrl/certSha256 in install output');
      }
      apiUrl = RegExp(r'"apiUrl"\s*:\s*"([^"]+)"').firstMatch(match.group(0)!)?.group(1);
      certSha =
          RegExp(r'"certSha256"\s*:\s*"([^"]+)"').firstMatch(match.group(0)!)?.group(1);
    }

    if (apiUrl == null || certSha == null) {
      throw Exception('Could not find Outline apiUrl/certSha256 in install output');
    }

    int? managementPort;
    final apiMatch = RegExp(r':(\d+)/').firstMatch(apiUrl);
    if (apiMatch != null) managementPort = int.parse(apiMatch.group(1)!);

    final mgmtMsg = RegExp(r'Management port\s+(\d+)', caseSensitive: false)
        .firstMatch(output);
    if (mgmtMsg != null) managementPort = int.parse(mgmtMsg.group(1)!);

    int? keysPort;
    final keysMsg = RegExp(r'Access key port\s+(\d+)', caseSensitive: false)
        .firstMatch(output);
    if (keysMsg != null) keysPort = int.parse(keysMsg.group(1)!);

    if (keysPort == null && output.contains('---SERVER_CONFIG---')) {
      final blob = output.split('---SERVER_CONFIG---').last.trim().split('\n').first;
      final port = RegExp(r'"portForNewAccessKeys"\s*:\s*(\d+)').firstMatch(blob);
      if (port != null) keysPort = int.parse(port.group(1)!);
    }

    if (managementPort == null || keysPort == null) {
      throw Exception(
        'Could not parse required ports (management=$managementPort, keys=$keysPort)',
      );
    }

    return {
      'outline': {'apiUrl': apiUrl, 'certSha256': certSha},
      'managementPort': managementPort,
      'accessKeyPort': keysPort,
      'publicIp': publicIp,
    };
  }

  Future<void> _openFirewallPorts(int managementPort, int accessKeyPort) async {
    onProgress('firewall', 'Opening Lightsail firewall ports…');
    Future<void> open(int from, int to, String protocol) async {
      await client.call('OpenInstancePublicPorts', {
        'instanceName': instanceName,
        'portInfo': {
          'fromPort': from,
          'toPort': to,
          'protocol': protocol,
          'cidrs': ['0.0.0.0/0'],
        },
      });
    }

    await open(managementPort, managementPort, 'tcp');
    await open(accessKeyPort, accessKeyPort, 'tcp');
    await open(accessKeyPort, accessKeyPort, 'udp');
    onProgress('firewall', 'Lightsail firewall ports opened');
  }

  Future<String> _configureOutlineKey(Map<String, String> outline) async {
    final api = OutlineApi(outline['apiUrl']!);
    onProgress('outline_manager', 'Configuring Outline access key on device…');

    // Wait briefly for API to come up
    String? accessKey;
    dynamic keyId;
    for (var i = 0; i < 30; i++) {
      try {
        keyId = await api.firstKeyId();
        accessKey = await api.firstAccessUrl();
        if (accessKey != null) break;
      } catch (_) {}
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    if (accessKey == null) {
      throw Exception('Could not get Outline access key from Management API');
    }

    onProgress('data_limit', 'Rename $accessKeyName → set ${dataLimitTb}TB data limit…');
    try {
      await api.renameKey(keyId, accessKeyName);
    } catch (_) {}
    try {
      await api.setDataLimitBytes(keyId, dataLimitBytes);
      onProgress('data_limit', '$accessKeyName data limit set to ${dataLimitTb}TB');
    } catch (e) {
      onProgress('data_limit', 'Could not set data limit: $e');
    }

    onProgress('access_key', 'Access key ready');
    return accessKey;
  }
}
