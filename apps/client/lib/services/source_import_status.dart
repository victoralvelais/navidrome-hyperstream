import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/library.dart';
import 'remote_folder.dart';

enum SourceImportPhase {
  queued,
  downloading,
  converting,
  sending,
  finishing,
  saved,
  failed,
  uncertain,
}

class SourceImportStatus {
  const SourceImportStatus(this.phase, {this.progress, this.savedAt});
  final SourceImportPhase phase;
  final double? progress;
  final DateTime? savedAt;
  bool get busy => ![
    SourceImportPhase.saved,
    SourceImportPhase.failed,
    SourceImportPhase.uncertain,
  ].contains(phase);
  String get label => switch (phase) {
    SourceImportPhase.queued => 'Waiting to send',
    SourceImportPhase.downloading => 'Downloading audio',
    SourceImportPhase.converting => 'Converting to MP3',
    SourceImportPhase.sending => 'Sending to remote folder',
    SourceImportPhase.finishing => 'Confirming remote save',
    SourceImportPhase.saved => 'Previously sent to this folder',
    SourceImportPhase.failed => 'Could not save. Tap to retry',
    SourceImportPhase.uncertain =>
      'Check the remote folder before sending again',
  };
}

/// A local delivery history, not a live index of files on the server. Only
/// identity hashes and timestamps persist; no server paths or credentials.
class SourceImportReceipts {
  SourceImportReceipts({this.read, this.write});
  factory SourceImportReceipts.persistent() {
    // Optional history must not prevent the player from opening when platform
    // preferences are unavailable. Construct the backend inside load's guarded
    // read so that failure retains the same session-only behavior as bad data.
    return SourceImportReceipts(
      read: () => SharedPreferencesAsync().getString(storageKey),
      write: (value) => SharedPreferencesAsync().setString(storageKey, value),
    );
  }
  static const storageKey = 'hyperstream.source-import-receipts.v1';
  final Future<String?> Function()? read;
  final Future<void> Function(String)? write;
  final values = <String, DateTime>{};
  Future<void>? _loading;
  Future<void>? _saving;
  String? _nextWrite;
  bool _writable = true;

  static String key(Track track, RemoteDestination destination) => sha256
      .convert(
        utf8.encode(
          jsonEncode([
            destination.address,
            destination.username,
            track.source!.sourceId,
            track.source!.trackId,
          ]),
        ),
      )
      .toString();

  Future<void> load() => _loading ??= _load();
  Future<void> _load() async {
    try {
      final raw = await read?.call().timeout(const Duration(seconds: 3));
      if (raw == null) return;
      if (raw.length > 8 * 1024 * 1024) throw const FormatException();
      final data = jsonDecode(raw) as Map<String, dynamic>;
      if (data['version'] != 1) throw const FormatException();
      final saved = data['saved'] as Map<String, dynamic>;
      final parsed = <String, DateTime>{};
      for (final entry in saved.entries) {
        if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(entry.key)) {
          throw const FormatException();
        }
        parsed[entry.key] = DateTime.fromMillisecondsSinceEpoch(
          entry.value as int,
        );
      }
      values.addAll(parsed);
    } on Object {
      // Protect unread/newer records. Session delivery state still works.
      _writable = false;
    }
  }

  Future<void> record(String key, DateTime at) async {
    await load();
    values[key] = at;
    if (!_writable || write == null) return;
    _nextWrite = jsonEncode({
      'version': 1,
      'saved': values.map(
        (key, at) => MapEntry(key, at.millisecondsSinceEpoch),
      ),
    });
    try {
      await (_saving ??= _drain()).timeout(const Duration(seconds: 3));
    } on Object {
      // A confirmed remote save remains successful even if local history fails.
    }
  }

  Future<void> _drain() async {
    await Future<void>.value();
    while (_nextWrite != null) {
      final data = _nextWrite!;
      _nextWrite = null;
      try {
        await write!(data);
      } on Object {
        /* Retain session receipt. */
      }
    }
    _saving = null;
  }
}
