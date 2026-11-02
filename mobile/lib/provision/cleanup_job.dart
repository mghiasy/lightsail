import '../aws/lightsail_client.dart';
import 'constants.dart';

typedef ProgressFn = void Function(String step, String message);

class CleanupJob {
  CleanupJob({
    required this.client,
    required this.onProgress,
  });

  final LightsailClient client;
  final ProgressFn onProgress;

  /// Returns false when instance was already missing.
  Future<bool> run() async {
    final state = await client.getInstanceState(instanceName);
    if (state == null) {
      return false;
    }

    await _stopInstance();
    await _deleteInstance();
    await _deleteStaticIp();
    onProgress('done', 'Cleanup complete');
    return true;
  }

  Future<void> _stopInstance() async {
    var state = await client.getInstanceState(instanceName);
    if (state == null) {
      onProgress('stop', 'Instance $instanceName not found — skipping stop');
      onProgress('stopped', 'Instance stopped');
      return;
    }
    if (state == 'stopped' || state == 'stopping') {
      onProgress('stop', 'Instance already $state');
    } else {
      onProgress('stop', 'Stopping instance $instanceName…');
      await client.call('StopInstance', {'instanceName': instanceName});
    }

    onProgress('stop', 'Waiting until instance is stopped…');
    while (true) {
      state = await client.getInstanceState(instanceName);
      if (state == null) {
        onProgress('stopped', 'Instance no longer exists');
        return;
      }
      onProgress('stop', 'Instance state: $state');
      if (state == 'stopped') {
        onProgress('stopped', 'Instance stopped');
        return;
      }
      if (state == 'terminated' || state == 'terminating') {
        onProgress('stopped', 'Instance $state');
        return;
      }
      await Future<void>.delayed(const Duration(seconds: 5));
    }
  }

  Future<void> _deleteInstance() async {
    var state = await client.getInstanceState(instanceName);
    if (state == null) {
      onProgress('delete_instance', 'Instance $instanceName already gone');
      onProgress('instance_deleted', 'Instance deleted');
      return;
    }
    onProgress('delete_instance', 'Deleting instance $instanceName…');
    await client.call('DeleteInstance', {'instanceName': instanceName});

    onProgress('delete_instance', 'Waiting until instance is gone…');
    while (true) {
      state = await client.getInstanceState(instanceName);
      if (state == null) {
        onProgress('instance_deleted', 'Instance deleted');
        return;
      }
      onProgress('delete_instance', 'Instance state: $state');
      await Future<void>.delayed(const Duration(seconds: 5));
    }
  }

  Future<void> _deleteStaticIp() async {
    final data = await client.getStaticIp(staticIpName);
    if (data == null) {
      onProgress('delete_ip', 'Static IP $staticIpName already gone');
      onProgress('ip_deleted', 'Static IP deleted');
      return;
    }
    final attached = data['attachedTo'];
    if (attached != null) {
      onProgress('delete_ip', 'Detaching static IP from $attached…');
      try {
        await client.call('DetachStaticIp', {'staticIpName': staticIpName});
      } catch (e) {
        if (!e.toString().toLowerCase().contains('not attached')) rethrow;
      }
    }
    onProgress('delete_ip', 'Deleting static IP $staticIpName…');
    await client.call('ReleaseStaticIp', {'staticIpName': staticIpName});
    onProgress('ip_deleted', 'Static IP deleted');
  }
}
