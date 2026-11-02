import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'aws/lightsail_client.dart';
import 'credentials_store.dart';
import 'provision/cleanup_job.dart';
import 'provision/constants.dart';
import 'provision/create_job.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LightsailApp());
}

class LightsailApp extends StatelessWidget {
  const LightsailApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lightsail',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A6B6A),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _store = CredentialsStore();
  final _accessCtrl = TextEditingController();
  final _secretCtrl = TextEditingController();
  bool _busy = false;
  bool _loaded = false;

  static const createSteps = [
    ('create', 'Creating instance'),
    ('created', 'Instance created'),
    ('waiting', 'Waiting for running'),
    ('running', 'Instance running'),
    ('ip_create', 'Creating static IP'),
    ('ip_created', 'Static IP created'),
    ('ip_attach', 'Attaching static IP'),
    ('ip_attached', 'Static IP attached'),
    ('ssh', 'SSH into server'),
    ('outline', 'Install Outline (+ Docker)'),
    ('firewall', 'Open Lightsail firewall ports'),
    ('outline_manager', 'Configure Outline on device'),
    ('data_limit', 'Rename cursor-key → set 2.5TB data limit'),
    ('access_key', 'Fetch access key'),
    ('done', 'Complete'),
  ];

  static const cleanupSteps = [
    ('stop', 'Stopping instance'),
    ('stopped', 'Instance stopped'),
    ('delete_instance', 'Deleting instance'),
    ('instance_deleted', 'Instance deleted'),
    ('delete_ip', 'Deleting static IP'),
    ('ip_deleted', 'Static IP deleted'),
    ('done', 'Cleanup complete'),
  ];

  @override
  void initState() {
    super.initState();
    _loadCreds();
  }

  Future<void> _loadCreds() async {
    final creds = await _store.load();
    if (creds != null) {
      _accessCtrl.text = creds.accessKeyId;
      _secretCtrl.text = creds.secretAccessKey;
    }
    setState(() => _loaded = true);
  }

  Future<AwsCredentials?> _requireCreds() async {
    final id = _accessCtrl.text.trim();
    final secret = _secretCtrl.text.trim();
    if (id.isEmpty || secret.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter AWS Access Key ID and Secret')),
      );
      return null;
    }
    final creds = AwsCredentials(accessKeyId: id, secretAccessKey: secret);
    await _store.save(creds);
    return creds;
  }

  Future<void> _runCreate() async {
    final creds = await _requireCreds();
    if (creds == null) return;

    setState(() => _busy = true);
    final states = {for (final s in createSteps) s.$1: 'pending'};
    String detail = 'Starting…';
    String? accessKey;
    Map<String, String>? outline;

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            Future<void> start() async {
              try {
                final client = LightsailClient(
                  accessKeyId: creds.accessKeyId,
                  secretAccessKey: creds.secretAccessKey,
                  region: creds.region,
                );
                final job = CreateJob(
                  client: client,
                  onProgress: (step, message) {
                    setModal(() {
                      detail = message;
                      for (final entry in createSteps) {
                        if (entry.$1 == step) {
                          states[entry.$1] = 'active';
                          break;
                        }
                        if (states[entry.$1] != 'done') {
                          states[entry.$1] = 'done';
                        }
                      }
                      states[step] = step == 'error' ? 'error' : 'active';
                      if (step == 'done') states[step] = 'done';
                    });
                  },
                );
                final result = await job.run();
                accessKey = result.accessKey;
                outline = result.outline;
                setModal(() {
                  detail = 'Access key ready';
                  for (final s in createSteps) {
                    states[s.$1] = 'done';
                  }
                });
              } catch (e) {
                setModal(() {
                  detail = e.toString();
                  states['done'] = 'error';
                });
              }
            }

            // Kick once
            if (detail == 'Starting…') {
              detail = 'Working…';
              start();
            }

            return _ProgressSheet(
              title: 'Provisioning progress',
              detail: detail,
              steps: createSteps,
              states: states,
              resultText: accessKey == null
                  ? null
                  : '$accessKey\n\n${const JsonEncoder.withIndent('  ').convert(outline)}',
              onClose: () => Navigator.pop(ctx),
              canClose: accessKey != null || detail.contains('Exception') || detail.contains('Error') || states.values.contains('error'),
            );
          },
        );
      },
    );

    setState(() => _busy = false);
  }

  Future<void> _runCleanup() async {
    final creds = await _requireCreds();
    if (creds == null) return;

    setState(() => _busy = true);
    final states = {for (final s in cleanupSteps) s.$1: 'pending'};
    String detail = 'Starting…';
    var finished = false;
    var notFound = false;

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            Future<void> start() async {
              try {
                final client = LightsailClient(
                  accessKeyId: creds.accessKeyId,
                  secretAccessKey: creds.secretAccessKey,
                  region: creds.region,
                );
                final job = CleanupJob(
                  client: client,
                  onProgress: (step, message) {
                    setModal(() {
                      detail = message;
                      for (final entry in cleanupSteps) {
                        if (entry.$1 == step) {
                          states[entry.$1] = 'active';
                          break;
                        }
                        if (states[entry.$1] != 'done') {
                          states[entry.$1] = 'done';
                        }
                      }
                      states[step] = 'active';
                      if (step == 'done') states[step] = 'done';
                    });
                  },
                );
                final existed = await job.run();
                notFound = !existed;
                finished = true;
                setModal(() {
                  detail = existed
                      ? 'Cleanup complete'
                      : 'Instance $instanceName does not exist.';
                  if (existed) {
                    for (final s in cleanupSteps) {
                      states[s.$1] = 'done';
                    }
                  }
                });
              } catch (e) {
                finished = true;
                setModal(() {
                  detail = e.toString();
                  states['done'] = 'error';
                });
              }
            }

            if (detail == 'Starting…') {
              detail = 'Working…';
              start();
            }

            return _ProgressSheet(
              title: 'Cleanup progress',
              detail: detail,
              steps: cleanupSteps,
              states: states,
              resultText: notFound ? 'Instance $instanceName does not exist.' : null,
              onClose: () => Navigator.pop(ctx),
              canClose: finished,
            );
          },
        );
      },
    );

    setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF07141F), Color(0xFF0C2436), Color(0xFF0A1A1C)],
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 24),
              Text(
                'Lightsail',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w400,
                      letterSpacing: -0.5,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Fully standalone on this phone',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white70,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Creates $instanceName, installs Outline, renames cursor-key, sets 2.5TB limit.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white60,
                    ),
              ),
              const SizedBox(height: 28),
              TextField(
                controller: _accessCtrl,
                decoration: const InputDecoration(
                  labelText: 'AWS Access Key ID',
                  border: OutlineInputBorder(),
                ),
                autocorrect: false,
                enableSuggestions: false,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _secretCtrl,
                decoration: const InputDecoration(
                  labelText: 'AWS Secret Access Key',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _runCreate,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: const Color(0xFF1A6B6A),
                ),
                child: const Text('Create cusor_instance'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _busy ? null : _runCleanup,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Clean up'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressSheet extends StatelessWidget {
  const _ProgressSheet({
    required this.title,
    required this.detail,
    required this.steps,
    required this.states,
    required this.onClose,
    required this.canClose,
    this.resultText,
  });

  final String title;
  final String detail;
  final List<(String, String)> steps;
  final Map<String, String> states;
  final VoidCallback onClose;
  final bool canClose;
  final String? resultText;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.85,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(detail, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: steps.length,
                itemBuilder: (context, i) {
                  final id = steps[i].$1;
                  final label = steps[i].$2;
                  final state = states[id] ?? 'pending';
                  IconData icon;
                  Color color;
                  switch (state) {
                    case 'done':
                      icon = Icons.check_circle;
                      color = Colors.tealAccent;
                      break;
                    case 'active':
                      icon = Icons.timelapse;
                      color = Colors.amber;
                      break;
                    case 'error':
                      icon = Icons.error;
                      color = Colors.redAccent;
                      break;
                    default:
                      icon = Icons.circle_outlined;
                      color = Colors.white24;
                  }
                  return ListTile(
                    dense: true,
                    leading: Icon(icon, color: color, size: 20),
                    title: Text(label),
                  );
                },
              ),
            ),
            if (resultText != null) ...[
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxHeight: 160),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.teal.withValues(alpha: 0.3)),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    resultText!,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: resultText!));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Copied')),
                    );
                  }
                },
                icon: const Icon(Icons.copy),
                label: const Text('Copy result'),
              ),
            ],
            FilledButton(
              onPressed: canClose ? onClose : null,
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}
