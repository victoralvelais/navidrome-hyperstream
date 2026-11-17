import 'package:flutter/widgets.dart';

import '../models/library.dart';
import 'audio_file_share.dart';
import 'navidrome_client.dart';
import 'music_provider.dart';
import 'remote_folder.dart';
import 'remote_transfer_background.dart';

class RemoteTransferResult {
  const RemoteTransferResult({
    required this.success,
    required this.message,
    this.notified = false,
    this.retryWithActivity = false,
    this.uncertain = false,
  });
  final bool success;
  final String message;
  final bool notified;
  final bool retryWithActivity;
  final bool uncertain;
}

/// A user-started transfer whose lifetime is independent of the initiating page.
class RemoteTransfer with WidgetsBindingObserver {
  RemoteTransfer({
    required this.remote,
    required this.client,
    required this.track,
    AudioFileShare? export,
    RemoteTransferBackground? background,
    this.useActivity = false,
    this.notifySuccess = true,
  }) : background = background ?? RemoteTransferBackground() {
    this.export =
        export ??
        AudioFileShare(
          client: client,
          track: track,
          prepareDirectory: this.background.prepareDirectory,
        );
  }

  final RemoteFolders remote;
  final NavidromeClient client;
  final Track track;
  final RemoteTransferBackground background;
  final bool useActivity;
  final bool notifySuccess;
  late final AudioFileShare export;
  RemoteBackgroundMode? _mode;
  bool _started = false;
  bool _cancelled = false;
  bool _finishing = false;
  bool _expired = false;

  bool get _shouldCancel => _cancelled || client.isClosed;
  void cancel() => _cancel();

  void _downloadProgress() {
    final total = export.total;
    background.update(
      completed: export.received,
      total: total == null ? -1 : total * 2 + 1,
      stage: 'Downloading audio',
    );
  }

  void _cancel() {
    if (_finishing) return;
    _cancelled = true;
    export.cancel();
  }

  void _backgroundEnded() {
    _expired = true;
    _cancel();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      _cancel();
    } else if (state == AppLifecycleState.paused &&
        _mode == RemoteBackgroundMode.foreground) {
      _backgroundEnded();
    }
  }

  Future<RemoteTransferResult> run() async {
    if (_started) throw StateError('This transfer has already started.');
    _started = true;
    final destination = remote.destination;
    if (destination == null || !remote.begin()) {
      export.dispose();
      return RemoteTransferResult(
        success: false,
        message: destination == null
            ? 'Choose a remote folder in Settings before sending a song.'
            : 'Another remote transfer or connection check is already running.',
      );
    }
    WidgetsBinding.instance.addObserver(this);
    export.addListener(_downloadProgress);
    RemoteFileSystem? fs;
    var success = false;
    var notified = false;
    var uncertain = false;
    var message = 'The transfer could not finish.';
    try {
      _mode = await background.begin(_backgroundEnded, continued: useActivity);
      if (_mode == RemoteBackgroundMode.foreground &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.paused) {
        _backgroundEnded();
      }
      if (_shouldCancel) throw const RemoteSendCancelled();
      fs = await remote.connect(destination);
      if (_shouldCancel) throw const RemoteSendCancelled();
      final file = await export.prepare();
      if (_shouldCancel) throw const RemoteSendCancelled();
      final length = await file.length();
      background.update(
        completed: length,
        total: length * 2 + 1,
        stage: 'Sending audio',
      );
      final name = await sendRemoteFile(
        fs: fs,
        destination: destination,
        file: file,
        cancelled: () => _shouldCancel,
        onProgress: (sent, total) => background.update(
          completed: total + sent,
          total: total * 2 + 1,
          stage: 'Sending audio',
        ),
        onFinishing: () {
          _finishing = true;
          background.update(
            completed: length * 2,
            total: length * 2 + 1,
            stage: 'Finishing',
          );
        },
      );
      message = 'Sent $name to your remote folder.';
      success = true;
    } on Object catch (error) {
      uncertain = error is RemotePublicationUncertain;
      if (error is AudioShareCancelled || error is RemoteSendCancelled) {
        message = _expired
            ? 'iOS ended background time for “${track.title}”. The transfer stopped.'
            : 'Transfer cancelled for “${track.title}”.';
      } else {
        final detail = error is SourceException
            ? error.message
            : error is NavidromeException
            ? error.message
            : remoteFolderError(error);
        message = 'Could not send “${track.title}”. $detail';
      }
    } finally {
      WidgetsBinding.instance.removeObserver(this);
      export.removeListener(_downloadProgress);
      try {
        try {
          await fs?.close();
        } on Object {
          // Preserve the confirmed publication result.
        }
        export.cancel();
        await export.finishPreparing();
        await export.cleanup();
        if (!success || notifySuccess) {
          notified = await background.notifyResult(success: success);
        }
      } finally {
        export.dispose();
        await background.finish(success: success);
        remote.end();
      }
    }
    final retryWithActivity =
        !success &&
        _expired &&
        _mode == RemoteBackgroundMode.quiet &&
        !client.isClosed;
    return RemoteTransferResult(
      success: success,
      message: retryWithActivity
          ? '$message Retry starts again using iOS activity.'
          : message,
      notified: notified,
      retryWithActivity: retryWithActivity,
      uncertain: uncertain,
    );
  }
}
