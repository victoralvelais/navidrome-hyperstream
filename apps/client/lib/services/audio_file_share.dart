import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../models/library.dart';
import 'navidrome_client.dart';

class AudioShareCancelled implements Exception {
  const AudioShareCancelled();
}

/// Streams an original track to a private temporary file. Only the completed
/// local file crosses the native bridge; server credentials never do.
class AudioFileShare extends ChangeNotifier {
  AudioFileShare({
    required this.client,
    required this.track,
    Future<Directory> Function()? temporaryDirectory,
    this.idleTimeout = const Duration(seconds: 30),
  }) : _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory;

  final NavidromeClient client;
  final Track track;
  final Future<Directory> Function() _temporaryDirectory;
  final Duration idleTimeout;
  final _abort = Completer<void>();
  Directory? _directory;
  File? _file;
  bool _cancelled = false;
  bool _disposed = false;
  bool _started = false;
  Future<File>? _preparation;
  int received = 0;
  int? total;
  double? get progress =>
      total == null || total! <= 0 ? null : (received / total!).clamp(0, 1);

  void cancel() {
    _cancelled = true;
    if (!_abort.isCompleted) _abort.complete();
  }

  void _checkActive() {
    if (_cancelled || client.isClosed) throw const AudioShareCancelled();
  }

  Future<File> prepare() {
    if (_started) throw StateError('This export has already started.');
    _started = true;
    return _preparation = _prepare();
  }

  Future<void> finishPreparing() async {
    try {
      await _preparation;
    } on Object {
      // The preparation UI owns its error; this only joins cancellation.
    }
  }

  Future<File> _prepare() async {
    RandomAccessFile? output;
    Stream<List<int>>? body;
    var bodyStarted = false;
    try {
      _checkActive();
      final cache = await _temporaryDirectory();
      final root = await Directory('${cache.path}/hyperstream-share')
          .create(recursive: true);
      // Reclaim interrupted exports left by a terminated app. Never traverse
      // links or delete anything outside this feature's own cache directory.
      await for (final entry in root.list(followLinks: false)) {
        if (entry is Directory &&
            entry.uri.pathSegments
                .where((s) => s.isNotEmpty)
                .last
                .startsWith('track-')) {
          final modified = (await entry.stat()).modified;
          if (DateTime.now().difference(modified) > const Duration(days: 1)) {
            await entry.delete(recursive: true);
          }
        }
      }
      _checkActive();
      _directory = await root.createTemp('track-');
      _checkActive();
      final response = await client.downloadAudio(
        track.id,
        abortTrigger: _abort.future,
      );
      body = response.stream;
      _checkActive();
      final mime =
          response.headers['content-type']
              ?.split(';')
              .first
              .trim()
              .toLowerCase() ??
          '';
      if (mime.contains('json') ||
          mime.contains('xml') ||
          mime.startsWith('text/')) {
        throw const NavidromeException(
          'The server did not return an audio file. Check your account’s download permission.',
        );
      }
      total = response.contentLength;
      if (!_disposed) notifyListeners();
      final partial = File('${_directory!.path}/audio.part');
      output = await partial.open(mode: FileMode.write);
      final prefix = <int>[];
      bodyStarted = true;
      await for (final chunk in body.timeout(idleTimeout)) {
        _checkActive();
        if (prefix.length < 512) prefix.addAll(chunk.take(512 - prefix.length));
        await output.writeFrom(chunk);
        received += chunk.length;
        if (!_disposed) notifyListeners();
      }
      _checkActive();
      await output.close();
      output = null;
      if (received == 0 || (total != null && received != total)) {
        throw const NavidromeException(
          'The audio download was incomplete. Try again.',
        );
      }
      final leading = utf8
          .decode(prefix, allowMalformed: true)
          .replaceFirst('\uFEFF', '')
          .trimLeft();
      if (leading.startsWith('{') ||
          leading.startsWith('[') ||
          leading.startsWith('<')) {
        throw const NavidromeException(
          'The server did not return an audio file. Check your account’s download permission.',
        );
      }
      final suffix = _suffix(track.container, mime);
      final name = _safeName('${track.artist} - ${track.title}');
      _file = await partial.rename('${_directory!.path}/$name.$suffix');
      _checkActive();
      return _file!;
    } on AudioShareCancelled {
      rethrow;
    } on NavidromeException {
      _checkActive();
      rethrow;
    } on Object {
      _checkActive();
      throw const NavidromeException(
        'Could not prepare the audio file. Check your connection and free storage, then try again.',
      );
    } finally {
      if (!_abort.isCompleted) _abort.complete();
      if (!bodyStarted) {
        await body?.listen(null, onError: (Object _) {}).cancel();
      }
      try {
        await output?.close();
      } on FileSystemException {
        // Preserve the sanitized failure already reported above.
      }
      if (_file == null) await cleanup();
    }
  }

  Future<void> share() async {
    _checkActive();
    final file = _file;
    if (file == null) {
      throw StateError('Prepare an audio file before sharing it.');
    }
    try {
      // iOS completes this call only after its activity sheet finishes, keeping
      // the file alive while Discord/AirDrop/Files reads the attachment.
      await const MethodChannel('dev.hyperstream/share')
          .invokeMethod<bool>('shareFile', file.path);
    } on Object {
      throw const NavidromeException(
        'Could not open audio sharing. Try again.',
      );
    }
  }

  Future<void> cleanup() async {
    final directory = _directory;
    if (directory == null) return;
    try {
      if (await directory.exists()) await directory.delete(recursive: true);
      _directory = null;
      _file = null;
    } on FileSystemException {
      // A later export reclaims stale files if the OS temporarily holds one.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    cancel();
    super.dispose();
  }
}

String _suffix(String? container, String mime) {
  final value = container?.trim().toLowerCase();
  if (value != null && RegExp(r'^[a-z0-9]{1,10}$').hasMatch(value)) {
    return value;
  }
  return switch (mime) {
    'audio/mpeg' || 'audio/mp3' => 'mp3',
    'audio/flac' || 'audio/x-flac' => 'flac',
    'audio/mp4' || 'audio/x-m4a' => 'm4a',
    'audio/aac' => 'aac',
    'audio/ogg' || 'application/ogg' => 'ogg',
    'audio/opus' => 'opus',
    'audio/wav' || 'audio/x-wav' || 'audio/wave' => 'wav',
    'audio/aiff' || 'audio/x-aiff' => 'aiff',
    _ => 'bin',
  };
}

String _safeName(String value) {
  final clean = value
      .replaceAll(RegExp(r'[\x00-\x1f\x7f/\\:*?"<>|]'), '_')
      .trim();
  final name = StringBuffer();
  var bytes = 0;
  for (final rune in clean.runes) {
    final character = String.fromCharCode(rune);
    bytes += utf8.encode(character).length;
    if (bytes > 180) break;
    name.write(character);
  }
  final result = name.toString().replaceAll(RegExp(r'^\.+|[. ]+$'), '');
  return result.isEmpty ? 'Audio' : result;
}
