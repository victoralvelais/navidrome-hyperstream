import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum RemoteBackgroundMode { desktop, quiet, continued, limited, foreground }

/// Retains one execution grant across a sequential album's download/convert/send
/// operations. Ending a song releases its SMB lock while the album keeps its grant.
class AlbumTransferBackground extends RemoteTransferBackground {
  AlbumTransferBackground({RemoteTransferBackground? background})
    : _background = background ?? RemoteTransferBackground();
  final RemoteTransferBackground _background;
  RemoteBackgroundMode? _mode;
  VoidCallback? _onExpired;
  bool _expired = false;

  @override
  Future<RemoteBackgroundMode> begin(
    VoidCallback onExpired, {
    bool continued = false,
  }) async {
    _onExpired = onExpired;
    _mode ??= await _background.begin(() {
      _expired = true;
      _onExpired?.call();
    }, continued: continued);
    if (_expired) onExpired();
    return _mode!;
  }

  @override
  Future<void> prepareDirectory(Directory directory) =>
      _background.prepareDirectory(directory);

  @override
  Future<bool> notifyResult({required bool success}) =>
      _background.notifyResult(success: success);

  @override
  void update({
    required int completed,
    required int total,
    required String stage,
  }) => _background.update(completed: completed, total: total, stage: stage);

  @override
  Future<void> finish({required bool success}) async {
    _onExpired = null;
  }

  Future<void> finishAlbum({required bool success}) =>
      _background.finish(success: success);
}

/// Owns the OS execution grant for one user-started remote transfer.
class RemoteTransferBackground {
  RemoteTransferBackground({bool? isIOS})
    : _isIOS = isIOS ?? defaultTargetPlatform == TargetPlatform.iOS;

  static const _channel = MethodChannel('dev.hyperstream/remote_transfer');
  final bool _isIOS;
  final _token = DateTime.now().microsecondsSinceEpoch.toString();
  bool _started = false;
  bool _finished = false;
  DateTime? _lastUpdate;
  String? _lastStage;

  Future<RemoteBackgroundMode> begin(
    VoidCallback onExpired, {
    bool continued = false,
  }) async {
    if (_started) throw StateError('The background transfer already started.');
    _started = true;
    if (!_isIOS) return RemoteBackgroundMode.desktop;
    _channel.setMethodCallHandler((call) async {
      if (!_finished && call.method == 'expired' && call.arguments == _token) {
        onExpired();
      }
    });
    try {
      final mode = await _channel.invokeMethod<String>('begin', {
        'token': _token,
        'continued': continued,
      });
      return switch (mode) {
        'quiet' => RemoteBackgroundMode.quiet,
        'continued' => RemoteBackgroundMode.continued,
        'limited' => RemoteBackgroundMode.limited,
        _ => RemoteBackgroundMode.foreground,
      };
    } on PlatformException {
      return RemoteBackgroundMode.foreground;
    } on MissingPluginException {
      return RemoteBackgroundMode.foreground;
    }
  }

  Future<void> prepareDirectory(Directory directory) async {
    if (!_isIOS) return;
    try {
      await _channel.invokeMethod<void>('prepareDirectory', directory.path);
    } on MissingPluginException {
      // The UI already requires foreground execution when the bridge is absent.
    }
  }

  Future<bool> notifyResult({required bool success}) async {
    if (!_isIOS || !_started || _finished) return false;
    try {
      return await _channel.invokeMethod<bool>('notifyResult', {
            'token': _token,
            'success': success,
          }) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  void update({
    required int completed,
    required int total,
    required String stage,
  }) {
    if (!_isIOS || !_started || _finished) return;
    final now = DateTime.now();
    if (_lastStage == stage &&
        _lastUpdate != null &&
        now.difference(_lastUpdate!) < const Duration(seconds: 1)) {
      return;
    }
    _lastStage = stage;
    _lastUpdate = now;
    unawaited(_update(completed, total, stage));
  }

  Future<void> _update(int completed, int total, String stage) async {
    try {
      await _channel.invokeMethod<void>('update', {
        'token': _token,
        'completed': completed,
        'total': total,
        'stage': stage,
      });
    } on PlatformException {
      // Reporting progress must not turn a completed file into a failed transfer.
    } on MissingPluginException {
      // Foreground operation also works without a native execution grant.
    }
  }

  Future<void> finish({required bool success}) async {
    if (!_started || _finished) return;
    _finished = true;
    if (!_isIOS) return;
    try {
      await _channel.invokeMethod<void>('finish', {
        'token': _token,
        'success': success,
      });
    } on PlatformException {
      // Keep the transfer result when the OS has already revoked the grant.
    } on MissingPluginException {
      // There was no native grant to release.
    } finally {
      _channel.setMethodCallHandler(null);
    }
  }
}
