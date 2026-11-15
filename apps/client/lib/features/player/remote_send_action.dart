import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/library.dart';
import '../../services/audio_file_share.dart';
import '../../services/navidrome_client.dart';
import '../../services/remote_folder.dart';
import '../../services/remote_transfer.dart';
import '../../services/remote_transfer_background.dart';

/// Returns after starting the job so song menus and navigation stay available.
Future<void> sendSongToRemote(
  BuildContext context,
  NavidromeClient client,
  Track track, {
  RemoteFolders? remote,
  AudioFileShare? export,
  RemoteTransferBackground? background,
}) async {
  unawaited(
    _send(
      ScaffoldMessenger.of(context),
      client,
      track,
      remote: remote ?? RemoteFolders.instance,
      export: export,
      background: background,
    ),
  );
}

Future<void> _send(
  ScaffoldMessengerState messenger,
  NavidromeClient client,
  Track track, {
  required RemoteFolders remote,
  AudioFileShare? export,
  RemoteTransferBackground? background,
  bool useActivity = false,
}) async {
  RemoteTransferResult result;
  try {
    result = await RemoteTransfer(
      remote: remote,
      client: client,
      track: track,
      export: export,
      background: background,
      useActivity: useActivity,
    ).run();
  } on Object catch (error) {
    result = RemoteTransferResult(
      success: false,
      message: remoteFolderError(error),
    );
  }
  if (!messenger.mounted || (result.success && result.notified)) return;
  messenger.showSnackBar(
    SnackBar(
      content: Text(result.message),
      duration: result.success
          ? const Duration(seconds: 4)
          : const Duration(days: 1),
      showCloseIcon: true,
      action: result.retryWithActivity
          ? SnackBarAction(
              label: 'Retry',
              onPressed: () => unawaited(
                _send(
                  messenger,
                  client,
                  track,
                  remote: remote,
                  useActivity: true,
                ),
              ),
            )
          : null,
    ),
  );
}
