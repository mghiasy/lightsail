const region = 'us-west-2';
const availabilityZone = 'us-west-2a';
const instanceName = 'cusor_instance';
const staticIpName = 'cusor_instance-ip';
const blueprintId = 'ubuntu_24_04';
const bundleId = 'small_3_0';

const outlineInstallUrl =
    'https://raw.githubusercontent.com/Jigsaw-Code/outline-server/'
    'master/src/server_manager/install_scripts/install_server.sh';

const accessKeyName = 'cursor-key';
const dataLimitTb = 2.5;
const dataLimitGb = 2500;
const dataLimitBytes = dataLimitGb * 1000 * 1000 * 1000;

final ansiRe = RegExp(r'\x1b\[[0-9;]*m');
final outlineJsonRe = RegExp(
  r'\{\s*"apiUrl"\s*:\s*"[^"]+"\s*,\s*"certSha256"\s*:\s*"[^"]+"\s*\}',
);
