/// "Update available" banner and the download/install dialog.
library;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

import '../app_services.dart';
import '../platform/updater.dart';

class UpdateBanner extends StatelessWidget {
  const UpdateBanner({
    super.key,
    required this.info,
    required this.onUpdate,
    required this.onLater,
  });
  final UpdateInfo info;
  final VoidCallback onUpdate;
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: scheme.secondaryContainer,
      child: ListTile(
        key: const ValueKey('update-banner'),
        leading: const Icon(Icons.system_update_rounded),
        title: Text('Update available · ${info.version}'),
        subtitle: Text('${(info.assetSize / 1e6).round()} MB'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(onPressed: onLater, child: const Text('Later')),
            FilledButton(onPressed: onUpdate, child: const Text('Update')),
          ],
        ),
      ),
    );
  }
}

Future<void> runUpdate(BuildContext context, AppServices s, UpdateInfo info) =>
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _UpdateDialog(services: s, info: info),
    );

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.services, required this.info});
  final AppServices services;
  final UpdateInfo info;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  double _progress = 0;
  String? _message;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    final s = widget.services;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final from = await s.updater!.currentBuild();
      final temp = await getTemporaryDirectory();
      Updater.cleanUp(
        temp,
      ); // never keep more than the one installer being fetched
      final dir = Updater.updatesDir(temp);
      final path = await s.updater!.download(
        widget.info,
        dir,
        progress: (v) {
          if (mounted) setState(() => _progress = v);
        },
      );
      s.logger.log('update.apply', {
        'kind': 'app',
        'from': from,
        'to': widget.info.build,
      });
      await s.updater!.install(path); // Windows exits and restarts here
      if (mounted) Navigator.of(context).pop();
    } on PlatformException catch (e) {
      setState(() {
        _busy = false;
        _message = e.code == 'needs_permission'
            ? 'Allow DuckLearn to install updates in the screen that just opened, '
                  'then tap Try again.'
            : 'Could not install: ${e.message ?? e.code}';
      });
    } on Object catch (e) {
      setState(() {
        _busy = false;
        _message = 'Download failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Updating to ${widget.info.version}'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(value: _busy ? _progress : null),
        const SizedBox(height: 8),
        Text(_busy ? '${(100 * _progress).round()}%' : (_message ?? '')),
        if (widget.info.notes.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            widget.info.notes,
            maxLines: 6,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    ),
    actions: [
      if (!_busy)
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      if (!_busy) FilledButton(onPressed: _run, child: const Text('Try again')),
    ],
  );
}
