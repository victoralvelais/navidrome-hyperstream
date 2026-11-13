import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/library.dart';
import '../models/smart_playlist.dart';
import 'library_catalog.dart';
import 'navidrome_client.dart';

class PlaylistPublishException implements Exception {
  const PlaylistPublishException(this.message);
  final String message;
  @override
  String toString() => message;
}

class PlaylistPublishConflict extends PlaylistPublishException {
  const PlaylistPublishConflict(this.remote)
    : super(
        'This server copy changed outside Hyperstream. Review it before replacing its songs.',
      );
  final MusicPlaylist remote;
}

class PublishedPlaylist {
  PublishedPlaylist({
    required this.name,
    this.remoteId,
    List<String> trackIds = const [],
    List<String>? pendingIds,
  }) : trackIds = List.unmodifiable(trackIds),
       pendingIds = pendingIds == null ? null : List.unmodifiable(pendingIds);
  final String name;
  final String? remoteId;
  final List<String> trackIds;
  final List<String>? pendingIds;
  bool get creationUncertain => remoteId == null && pendingIds != null;
  Map<String, dynamic> toJson() => {
    'name': name,
    'remoteId': remoteId,
    'trackIds': trackIds,
    'pendingIds': pendingIds,
  };
  factory PublishedPlaylist.fromJson(Map<String, dynamic> json) {
    final value = PublishedPlaylist(
      name: json['name'] as String,
      remoteId: json['remoteId'] as String?,
      trackIds: (json['trackIds'] as List).cast<String>(),
      pendingIds: (json['pendingIds'] as List?)?.cast<String>(),
    );
    if (value.name.trim().isEmpty ||
        value.name.length > 200 ||
        (value.remoteId != null && value.remoteId!.isEmpty) ||
        (value.remoteId == null && value.pendingIds == null)) {
      throw const FormatException();
    }
    for (final ids in [
      value.trackIds,
      if (value.pendingIds != null) value.pendingIds!,
    ]) {
      if (ids.length > 100000 ||
          ids.any((id) => id.isEmpty || id.length > 1000)) {
        throw const FormatException();
      }
    }
    return value;
  }
}

/// Explicit account-scoped publishing, with a durable intent before each write.
/// No timer, name-based adoption, blind retry of creates, or server deletion.
class SmartPlaylistPublisher {
  SmartPlaylistPublisher(
    this.client, {
    Future<String?> Function(String)? read,
    Future<void> Function(String, String)? write,
  }) : storageKey =
           'hyperstream.publishedPlaylists.v1.${sha256.convert(utf8.encode(jsonEncode([client.baseUri.toString(), client.username])))}',
       _read = read ?? ((key) => SharedPreferencesAsync().getString(key)),
       _write =
           write ??
           ((key, value) => SharedPreferencesAsync().setString(key, value));
  final NavidromeClient client;
  final String storageKey;
  final Future<String?> Function(String) _read;
  final Future<void> Function(String, String) _write;
  Map<String, PublishedPlaylist> _links = {};
  Future<void>? _loading;
  bool _disposed = false;
  bool busy = false;
  bool canWrite = false;
  PublishedPlaylist? link(String id) => _links[id];

  void _check() {
    if (_disposed || client.isClosed) {
      throw const PlaylistPublishException(
        'This server connection is no longer active.',
      );
    }
  }

  Future<void> load() => _loading ??= () async {
    try {
      final raw = await _read(storageKey).timeout(const Duration(seconds: 3));
      _check();
      if (raw != null) {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        if (json['schemaVersion'] != 1) throw const FormatException();
        final links = json['links'] as Map<String, dynamic>;
        if (links.length > 500) throw const FormatException();
        _links = links.map(
          (id, value) => MapEntry(
            id,
            PublishedPlaylist.fromJson(value as Map<String, dynamic>),
          ),
        );
      }
      canWrite = true;
    } on Object {
      throw const PlaylistPublishException(
        'Saved server-copy links could not be read. Reopen the app to retry; existing data has been preserved.',
      );
    }
  }();

  Future<void> _save(
    String id,
    PublishedPlaylist value, {
    bool remoteAlreadyCreated = false,
  }) async {
    _check();
    final next = {..._links, id: value};
    if (next.length > 500) {
      throw const PlaylistPublishException(
        'Up to 500 server copies can be linked on this device.',
      );
    }
    try {
      await _write(
        storageKey,
        jsonEncode({
          'schemaVersion': 1,
          'links': next.map((key, value) => MapEntry(key, value.toJson())),
        }),
      );
      _check();
      _links = next;
    } on Object {
      // Retain the known ID in memory; the earlier durable create intent still
      // prevents another automatic create if this process exits before repair.
      if (remoteAlreadyCreated) _links = next;
      throw const PlaylistPublishException(
        'Could not save the server-copy record. A server request may already have succeeded. Retry to verify it before making another copy.',
      );
    }
  }

  void _owned(MusicPlaylist playlist, String id) {
    if (playlist.id != id ||
        playlist.owner != client.username ||
        playlist.readOnly) {
      throw const PlaylistPublishException(
        'Only your own writable server copies can be updated.',
      );
    }
    if (playlist.songCount != playlist.tracks.length) {
      throw const PlaylistPublishException(
        'The server did not return the complete playlist. This copy could not be verified.',
      );
    }
  }

  List<String> _ids(MusicPlaylist playlist) =>
      playlist.tracks.map((track) => track.id).toList();
  Future<MusicPlaylist> _readRemote(String id) async {
    _check();
    final remote = await client.playlist(id);
    _check();
    _owned(remote, id);
    return remote;
  }

  Future<T> _exclusive<T>(Future<T> Function() operation) async {
    _check();
    if (busy) {
      throw const PlaylistPublishException(
        'A server copy is already being published. Wait for it to finish.',
      );
    }
    busy = true;
    try {
      await load();
      _check();
      return await operation();
    } finally {
      busy = false;
    }
  }

  Future<MusicPlaylist> publish({
    required String definitionId,
    required String name,
    required SmartPlaylistResult result,
    required LibraryCatalog catalog,
    bool separateCopy = false,
    MusicPlaylist? reviewed,
  }) => _exclusive(() async {
    if (!identical(catalog.client, client) ||
        catalog.lastSyncedAt == null ||
        catalog.loading ||
        catalog.error != null) {
      throw const PlaylistPublishException(
        'Finish a successful library sync before publishing. The current server copy has been left unchanged.',
      );
    }
    final ids = result.matches.map((match) => match.track.id).toList();
    if (ids.isEmpty ||
        ids.length > 100000 ||
        ids.toSet().length != ids.length ||
        ids.any((id) => id.isEmpty)) {
      throw const PlaylistPublishException(
        'Publish a nonempty preview of up to 100000 distinct tracks. Empty results never clear a server copy.',
      );
    }
    if (name.trim().isEmpty || name.trim().length > 120) {
      throw const PlaylistPublishException(
        'Enter a server-copy name of up to 120 characters.',
      );
    }
    var current = separateCopy ? null : _links[definitionId];
    if (current?.creationUncertain == true) {
      throw const PlaylistPublishException(
        'The previous create may have succeeded. Check existing copies before creating another.',
      );
    }
    if (current == null) {
      await _save(
        definitionId,
        PublishedPlaylist(name: name.trim(), pendingIds: ids),
      );
      _check();
      final created = await client.createPlaylist(name.trim(), songIds: ids);
      _check();
      if (created.id.isEmpty) {
        throw const PlaylistPublishException(
          'The server did not return a playlist ID. Check existing copies before creating another.',
        );
      }
      current = PublishedPlaylist(
        name: name.trim(),
        remoteId: created.id,
        pendingIds: ids,
      );
      await _save(definitionId, current, remoteAlreadyCreated: true);
      final verified = await _readRemote(created.id);
      if (!listEquals(_ids(verified), ids)) {
        throw PlaylistPublishConflict(verified);
      }
      await _save(
        definitionId,
        PublishedPlaylist(
          name: verified.name,
          remoteId: verified.id,
          trackIds: ids,
        ),
      );
      return verified;
    }
    final remote = await _readRemote(current.remoteId!);
    final remoteIds = _ids(remote);
    // A lost response or failed final save can be recovered without resending.
    if (current.pendingIds != null &&
        listEquals(remoteIds, current.pendingIds)) {
      current = PublishedPlaylist(
        name: remote.name,
        remoteId: remote.id,
        trackIds: remoteIds,
      );
      await _save(definitionId, current);
    }
    if (reviewed != null) {
      if (reviewed.id != remote.id || !listEquals(_ids(reviewed), remoteIds)) {
        throw PlaylistPublishConflict(remote);
      }
    } else if (!listEquals(remoteIds, current.trackIds)) {
      throw PlaylistPublishConflict(remote);
    }
    if (listEquals(remoteIds, ids)) {
      await _save(
        definitionId,
        PublishedPlaylist(
          name: remote.name,
          remoteId: remote.id,
          trackIds: ids,
        ),
      );
      return remote;
    }
    await _save(
      definitionId,
      PublishedPlaylist(
        name: remote.name,
        remoteId: remote.id,
        trackIds: remoteIds,
        pendingIds: ids,
      ),
    );
    _check();
    final beforeWrite = await _readRemote(remote.id);
    if (!listEquals(_ids(beforeWrite), remoteIds)) {
      throw PlaylistPublishConflict(beforeWrite);
    }
    await client.replacePlaylistTracks(remote.id, ids);
    final verified = await _readRemote(remote.id);
    if (!listEquals(_ids(verified), ids)) {
      throw PlaylistPublishConflict(verified);
    }
    await _save(
      definitionId,
      PublishedPlaylist(
        name: verified.name,
        remoteId: verified.id,
        trackIds: ids,
      ),
    );
    return verified;
  });

  /// Explicit user-selected ID only; never infer ownership or identity by name.
  Future<MusicPlaylist> recover(String definitionId, String remoteId) =>
      _exclusive(() async {
        final pending = _links[definitionId];
        if (pending == null || !pending.creationUncertain) {
          throw const PlaylistPublishException(
            'There is no uncertain create to recover.',
          );
        }
        final remote = await _readRemote(remoteId);
        if (!listEquals(_ids(remote), pending.pendingIds)) {
          throw const PlaylistPublishException(
            'This playlist does not match the pending copy. No link or server contents were changed.',
          );
        }
        await _save(
          definitionId,
          PublishedPlaylist(
            name: remote.name,
            remoteId: remote.id,
            trackIds: _ids(remote),
          ),
        );
        return remote;
      });

  void dispose() {
    _disposed = true;
  }
}
