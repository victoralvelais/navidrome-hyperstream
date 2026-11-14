import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/library.dart';
import '../../services/audio_file_share.dart';
import '../../services/navidrome_client.dart';
import '../../services/remote_folder.dart';
import '../../widgets/glass_overlays.dart';

Future<void> sendSongToRemote(
  BuildContext context,
  NavidromeClient client,
  Track track, {
  RemoteFolders? remote,
  AudioFileShare? export,
}) async {
  final folders = remote ?? RemoteFolders.instance;
  final destination = folders.destination;
  if (destination == null || !folders.begin()) return;
  final transfer = export ?? AudioFileShare(client: client, track: track);
  try {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _RemoteSendDialog(
        remote: folders,
        destination: destination,
        client: client,
        export: transfer,
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
  });
  final RemoteFolders remote;
  final RemoteDestination destination;
  final NavidromeClient client;
  final AudioFileShare export;
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
  int _sent = 0;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.export.addListener(_refresh);
    unawaited(_run());
  }

  void _refresh() {
    if (mounted) setState(() {});
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
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _cancel();
    }
  }

  Future<void> _run() async {
    RemoteFileSystem? fs;
    try {
      fs = await widget.remote.connect(widget.destination);
      if (_shouldCancel) throw const RemoteSendCancelled();
      _stage = 'Preparing audio file';
      _refresh();
      final file = await widget.export.prepare();
      if (_shouldCancel) throw const RemoteSendCancelled();
      _stage = 'Sending';
      _total = await file.length();
      _refresh();
      final name = await sendRemoteFile(
        fs: fs,
        destination: widget.destination,
        file: file,
        cancelled: () => _shouldCancel,
        onProgress: (sent, total) {
          _sent = sent;
          _total = total;
          _refresh();
        },
        onFinishing: () {
          _finishing = true;
          _stage = 'Finishing';
          _refresh();
        },
      );
      _result = 'Sent $name to ${widget.destination.displayName}.';
    } on AudioShareCancelled {
      _result = 'Transfer cancelled.';
    } on RemoteSendCancelled {
      _result = 'Transfer cancelled. No completed song was published.';
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
      widget.export.removeListener(_refresh);
      widget.export.dispose();
      widget.remote.end();
      _done = true;
      _refresh();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (!_done && !_finishing) {
      _cancelled = true;
      widget.export.cancel();
    }
    widget.export.removeListener(_refresh);
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
                    : 'Keep Hyperstream open until this finishes.',
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
