import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/library.dart';
import '../../services/audio_file_share.dart';
import '../../services/navidrome_client.dart';
import '../../services/remote_folder.dart';
import '../../services/remote_transfer_background.dart';
import '../../widgets/glass_overlays.dart';

Future<void> sendSongToRemote(
  BuildContext context,
  NavidromeClient client,
  Track track, {
  RemoteFolders? remote,
  AudioFileShare? export,
  RemoteTransferBackground? background,
}) async {
  final folders = remote ?? RemoteFolders.instance;
  final destination = folders.destination;
  if (destination == null || !folders.begin()) return;
  final execution = background ?? RemoteTransferBackground();
  final transfer =
      export ??
      AudioFileShare(
        client: client,
        track: track,
        prepareDirectory: execution.prepareDirectory,
      );
  try {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _RemoteSendDialog(
        remote: folders,
        destination: destination,
        client: client,
        export: transfer,
        background: execution,
      ),
    );
  } on Object {
    folders.end();
    rethrow;
  }
}

class _RemoteSendDialog extends StatefulWidget {
  const _RemoteSendDialog({
    required this.remote,
    required this.destination,
    required this.client,
    required this.export,
    required this.background,
  });
  final RemoteFolders remote;
  final RemoteDestination destination;
  final NavidromeClient client;
  final AudioFileShare export;
  final RemoteTransferBackground background;
  @override
  State<_RemoteSendDialog> createState() => _RemoteSendDialogState();
}

class _RemoteSendDialogState extends State<_RemoteSendDialog>
    with WidgetsBindingObserver {
  String _stage = 'Connecting';
  String? _result;
  bool _cancelled = false;
  bool _finishing = false;
  bool _done = false;
  bool _failed = false;
  bool _backgroundExpired = false;
  RemoteBackgroundMode? _backgroundMode;
  int _sent = 0;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.export.addListener(_downloadProgress);
    unawaited(_run());
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _downloadProgress() {
    final total = widget.export.total;
    widget.background.update(
      completed: widget.export.received,
      total: total == null ? -1 : total * 2 + 1,
      stage: 'Downloading audio',
    );
    _refresh();
  }

  void _backgroundEnded() {
    _backgroundExpired = true;
    _cancel();
  }

  bool get _shouldCancel => _cancelled || widget.client.isClosed;
  void _cancel() {
    if (_finishing || _done) return;
    _cancelled = true;
    widget.export.cancel();
    _refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      _cancel();
    } else if (state == AppLifecycleState.paused &&
        _backgroundMode == RemoteBackgroundMode.foreground) {
      _backgroundEnded();
    }
  }

  Future<void> _run() async {
    RemoteFileSystem? fs;
    var success = false;
    try {
      _backgroundMode = await widget.background.begin(_backgroundEnded);
      // The app may have moved offscreen while the native grant was pending.
      if (_backgroundMode == RemoteBackgroundMode.foreground &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.paused) {
        _backgroundEnded();
      }
      if (_shouldCancel) throw const RemoteSendCancelled();
      _refresh();
      fs = await widget.remote.connect(widget.destination);
      if (_shouldCancel) throw const RemoteSendCancelled();
      _stage = 'Preparing audio file';
      _refresh();
      final file = await widget.export.prepare();
      if (_shouldCancel) throw const RemoteSendCancelled();
      _stage = 'Sending';
      _total = await file.length();
      widget.background.update(
        completed: _total,
        total: _total * 2 + 1,
        stage: 'Sending audio',
      );
      _refresh();
      final name = await sendRemoteFile(
        fs: fs,
        destination: widget.destination,
        file: file,
        cancelled: () => _shouldCancel,
        onProgress: (sent, total) {
          _sent = sent;
          _total = total;
          widget.background.update(
            completed: total + sent,
            total: total * 2 + 1,
            stage: 'Sending audio',
          );
          _refresh();
        },
        onFinishing: () {
          _finishing = true;
          _stage = 'Finishing';
          widget.background.update(
            completed: _total * 2,
            total: _total * 2 + 1,
            stage: 'Finishing',
          );
          _refresh();
        },
      );
      _result = 'Sent $name to ${widget.destination.displayName}.';
      success = true;
    } on AudioShareCancelled {
      _result = _cancellationMessage;
    } on RemoteSendCancelled {
      _result = _cancellationMessage;
    } on NavidromeException catch (e) {
      _failed = true;
      _result = e.message;
    } on Object catch (e) {
      _failed = true;
      _result = remoteFolderError(e);
    } finally {
      try {
        await fs?.close();
      } on Object {
        /* Keep the transfer result. */
      }
      widget.export.cancel();
      await widget.export.finishPreparing();
      await widget.export.cleanup();
      widget.export.removeListener(_downloadProgress);
      widget.export.dispose();
      await widget.background.finish(success: success);
      widget.remote.end();
      _done = true;
      _refresh();
    }
  }

  String get _cancellationMessage => _backgroundExpired
      ? 'Background execution ended or was cancelled in iOS. Reopen Hyperstream and send the song again.'
      : 'Transfer cancelled. No completed song was published.';

  String get _backgroundMessage => switch (_backgroundMode) {
    RemoteBackgroundMode.continued => 'The transfer can continue with the screen locked. Progress is available in the system activity.',
    RemoteBackgroundMode.limited => 'iOS granted limited background time. Keep Hyperstream open for long transfers.',
    RemoteBackgroundMode.foreground => 'Background transfer is unavailable. Keep Hyperstream open until this finishes.',
    RemoteBackgroundMode.desktop =>
      'You can minimize Hyperstream while the transfer finishes.',
    null => 'Requesting background time…',
  };

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (!_done && !_finishing) {
      _cancelled = true;
      widget.export.cancel();
    }
    widget.export.removeListener(_downloadProgress);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preparing = _stage == 'Preparing audio file';
    final progress = preparing
        ? widget.export.progress
        : (_stage == 'Sending' && _total > 0
              ? (_sent / _total).clamp(0.0, 1.0)
              : null);
    String size(int bytes) => '${(bytes / 1000000).toStringAsFixed(1)} MB';
    return PopScope(
      canPop: _done,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: GlassAlertDialog(
        scrollable: true,
        title: Text(
          _done
              ? (_failed ? 'Could not send song' : 'Remote folder')
              : (_cancelled ? 'Stopping transfer' : _stage),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.export.track.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Text(
              widget.destination.address,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),
            if (!_done) ...[
              LinearProgressIndicator(value: progress),
              const SizedBox(height: 8),
              if (preparing) Text('${size(widget.export.received)} downloaded'),
              if (_stage == 'Sending')
                Text('${size(_sent)} of ${size(_total)} sent'),
              const SizedBox(height: 12),
              Text(
                _cancelled
                    ? 'Waiting for the server and cleaning up…'
                    : _backgroundMessage,
              ),
            ] else
              Text(_result ?? 'Transfer finished.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: _done
                ? () => Navigator.pop(context)
                : (_finishing || _cancelled ? null : _cancel),
            child: Text(_done ? 'Done' : 'Cancel'),
          ),
        ],
      ),
    );
  }
}
