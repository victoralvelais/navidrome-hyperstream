import 'package:flutter/foundation.dart';

import '../models/library.dart';
import 'navidrome_client.dart';

/// Server-backed collections shared by browsing, search, and the player.
/// Changes become visible only after Navidrome confirms them.
class LibraryCollections extends ChangeNotifier {
  LibraryCollections(this.client);
  final NavidromeClient client;
  final Map<String, Album> _albums = {};
  final Map<String, Track> _songs = {};
  final Map<(bool, String), bool> _favoriteChanges = {};
  final Set<(bool, String)> _pendingFavorites = {};
  final Map<String, int> _ratings = {};
  final Set<String> _pendingRatings = {};
  int rating(Track track) => _ratings[track.id] ?? track.userRating;
  bool ratingPending(Track track) => _pendingRatings.contains(track.id);

  Future<void> rate(Track track, int value) async {
    if (!_pendingRatings.add(track.id)) return;
    _notify();
    try {
      await client.setRating(track.id, value);
      if (!_disposed) _ratings[track.id] = value;
    } finally {
      _pendingRatings.remove(track.id);
      _notify();
    }
  }

  int _favoriteRevision = 0;
  int playlistRevision = 0;
  bool _disposed = false;
  bool favoritesLoaded = false;
  bool favoritesLoading = false;
  String? favoritesError;
  List<Album> get favoriteAlbums => List.unmodifiable(_albums.values);
  List<Track> get favoriteSongs => List.unmodifiable(_songs.values);
  List<MusicPlaylist>? playlists;
  bool playlistsLoading = false;
  String? playlistsError;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool isFavorite(String id, {required bool album, bool fallback = false}) =>
      _favoriteChanges[(album, id)] ??
      (favoritesLoaded
          ? (album ? _albums.containsKey(id) : _songs.containsKey(id))
          : fallback);

  bool favoritePending(String id, {required bool album}) =>
      _pendingFavorites.contains((album, id));

  Future<void> toggleSong(Track song) =>
      _toggle(song.id, album: false, fallback: song.starred, song: song);
  Future<void> toggleAlbum(Album album) =>
      _toggle(album.id, album: true, fallback: album.starred, record: album);

  Future<void> _toggle(
    String id, {
    required bool album,
    required bool fallback,
    Track? song,
    Album? record,
  }) async {
    final key = (album, id);
    if (!_pendingFavorites.add(key)) return;
    final favorite = !isFavorite(id, album: album, fallback: fallback);
    _notify();
    try {
      await client.setFavorite(id, album: album, favorite: favorite);
      if (_disposed) return;
      _favoriteRevision++;
      _favoriteChanges[key] = favorite;
      if (album) {
        if (favorite) {
          _albums[id] = record!;
        } else {
          _albums.remove(id);
        }
      } else {
        if (favorite) {
          _songs[id] = song!;
        } else {
          _songs.remove(id);
        }
      }
    } finally {
      _pendingFavorites.remove(key);
      _notify();
    }
  }

  Future<void> refreshFavorites() async {
    if (favoritesLoading || _disposed) return;
    favoritesLoading = true;
    favoritesError = null;
    _notify();
    try {
      while (!_disposed) {
        final revision = _favoriteRevision;
        final result = await client.favorites();
        if (_disposed) return;
        // A read started before a successful edit must not undo that edit.
        if (revision != _favoriteRevision) continue;
        _albums
          ..clear()
          ..addEntries(result.albums.map((a) => MapEntry(a.id, a)));
        _songs
          ..clear()
          ..addEntries(result.tracks.map((t) => MapEntry(t.id, t)));
        _favoriteChanges.clear();
        favoritesLoaded = true;
        break;
      }
    } on NavidromeException catch (error) {
      favoritesError = error.message;
    } finally {
      favoritesLoading = false;
      _notify();
    }
  }

  Future<void> refreshPlaylists() async {
    if (playlistsLoading || _disposed) return;
    playlistsLoading = true;
    playlistsError = null;
    _notify();
    try {
      while (!_disposed) {
        final revision = playlistRevision;
        final result = await client.playlists();
        if (_disposed) return;
        if (revision != playlistRevision) continue;
        playlists = result;
        break;
      }
    } on NavidromeException catch (error) {
      playlistsError = error.message;
    } finally {
      playlistsLoading = false;
      _notify();
    }
  }

  Future<MusicPlaylist> createPlaylist(
    String name, {
    String? songId,
    List<String>? songIds,
  }) async {
    final result = await client.createPlaylist(
      name,
      songId: songId,
      songIds: songIds,
    );
    await _playlistsChanged();
    return result;
  }

  Future<void> addToPlaylist(String id, String songId) async {
    await client.addToPlaylist(id, songId);
    await _playlistsChanged();
  }

  Future<void> addSongsToPlaylist(String id, List<String> songIds) async {
    await client.addSongsToPlaylist(id, songIds);
    await _playlistsChanged();
  }

  Future<void> renamePlaylist(String id, String name) async {
    await client.renamePlaylist(id, name);
    await _playlistsChanged();
  }

  Future<void> removeFromPlaylist(MusicPlaylist snapshot, int index) async {
    await client.removeFromPlaylist(snapshot, index);
    await _playlistsChanged();
  }

  Future<void> _playlistsChanged() async {
    if (_disposed) return;
    playlistRevision++;
    _notify();
    await refreshPlaylists();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
