import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/library.dart';
import '../../services/audio_file_share.dart';
import '../../services/navidrome_client.dart';
import '../../widgets/glass_overlays.dart';

Future<void> shareAudioFile(
  BuildContext context,
  NavidromeClient client,
  Track track, {
  AudioFileShare? transfer,
}) async {
  final export = transfer ?? AudioFileShare(client: client, track: track);
  final route = DialogRoute<Object>(
    context: context,
    builder: (_) => _PrepareAudioShare(export: export),
  );
  try {
    final outcome = await Navigator.of(
      context,
      rootNavigator: true,
    ).push(route);
    // Wait for the Flutter dialog to leave before presenting native UI.
    await route.completed;
    if (outcome is NavidromeException) throw outcome;
    if (outcome == true && context.mounted && !client.isClosed) {
      await export.share();
    }
  } on AudioShareCancelled {
    // Cancelling a download or switching accounts is not an error.
  } finally {
    export.cancel();
    await export.finishPreparing();
    await export.cleanup();
    export.dispose();
  }
}

class _PrepareAudioShare extends StatefulWidget {
  const _PrepareAudioShare({required this.export});
  final AudioFileShare export;
  @override
  State<_PrepareAudioShare> createState() => _PrepareAudioShareState();
}

class _PrepareAudioShareState extends State<_PrepareAudioShare> {
  bool _ready = false;
  @override
  void initState() {
    super.initState();
    unawaited(_prepare());
  }

  Future<void> _prepare() async {
    try {
      await widget.export.prepare();
      if (mounted && ModalRoute.of(context)?.isCurrent == true) {
        _ready = true;
        Navigator.pop(context, true);
      }
    } on AudioShareCancelled {
      if (mounted && ModalRoute.of(context)?.isCurrent == true) {
        Navigator.pop(context);
      }
    } on NavidromeException catch (error) {
      if (mounted && ModalRoute.of(context)?.isCurrent == true) {
        Navigator.pop(context, error);
      }
    }
  }

  @override
  void dispose() {
    if (!_ready) widget.export.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.export,
    builder: (context, _) {
      final export = widget.export;
      String size(int bytes) => '${(bytes / 1000000).toStringAsFixed(1)} MB';
      return GlassAlertDialog(
        title: const Text('Preparing audio file'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              export.track.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(value: export.progress),
            const SizedBox(height: 8),
            Text(
              export.total == null
                  ? '${size(export.received)} downloaded'
                  : '${size(export.received)} of ${size(export.total!)}',
            ),
          ],
        ),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () {
              export.cancel();
              Navigator.pop(context);
            },
            child: const Text('Cancel'),
          ),
        ],
      );
    },
  );
}
