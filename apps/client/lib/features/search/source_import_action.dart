import 'package:hyperstream_client/widgets/app_icon.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/library.dart';
import '../../services/navidrome_client.dart';
import '../../services/remote_transfer.dart';
import '../../services/source_imports.dart';

class SourceDownloadButton extends StatelessWidget {
  const SourceDownloadButton({
    super.key,
    required this.client,
    required this.tracks,
  });
  final NavidromeClient client;
  final List<Track> tracks;
  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tracks.length == 1
        ? 'Download song to remote folder'
        : 'Download album to remote folder',
    icon: const AppIcon(Icons.download_rounded),
    onPressed:
        tracks.isEmpty || tracks.any((track) => track.source?.available != true)
        ? null
        : () => sendSourceTracks(context, client, tracks),
  );
}

void sendSourceTracks(
  BuildContext context,
  NavidromeClient client,
  List<Track> tracks,
) {
  final messenger = ScaffoldMessenger.of(context);
  unawaited(_report(messenger, SourceImports.instance.send(client, tracks)));
}

void retrySourceImport(BuildContext context) {
  unawaited(
    _report(ScaffoldMessenger.of(context), SourceImports.instance.retry()),
  );
}

Future<void> _report(
  ScaffoldMessengerState messenger,
  Future<RemoteTransferResult> operation,
) async {
  final result = await operation;
  if (!messenger.mounted || (result.success && result.notified)) return;
  messenger.showSnackBar(
    SnackBar(
      content: Text(result.message),
      duration: result.success
          ? const Duration(seconds: 4)
          : const Duration(days: 1),
      showCloseIcon: true,
      action:
          !result.success &&
              !result.uncertain &&
              !SourceImports.instance.active &&
              identical(result, SourceImports.instance.issue) &&
              SourceImports.instance.remaining.isNotEmpty
          ? SnackBarAction(
              label: 'Retry',
              onPressed: () {
                if (identical(result, SourceImports.instance.issue)) {
                  unawaited(_report(messenger, SourceImports.instance.retry()));
                }
              },
            )
          : null,
    ),
  );
}
