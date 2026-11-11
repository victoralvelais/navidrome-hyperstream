import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import '../../widgets/pull_to_refresh.dart';

import '../../models/library.dart';
import '../../services/library_collections.dart';
import '../../services/navidrome_client.dart';
import '../../services/playback_service.dart';
import '../library/collection_actions.dart';
import '../library/cover_art.dart';
import '../library/artwork_backdrop.dart';
import 'playlist_dialogs.dart';
import '../search/library_search.dart';

class PlaylistTracks extends StatefulWidget {
  const PlaylistTracks({
    super.key,
    required this.playlistId,
    required this.collections,
    required this.playback,
  });
  final String playlistId;
  final LibraryCollections collections;
  final PlaybackService playback;
  @override
  State<PlaylistTracks> createState() => _PlaylistTracksState();
}

class _PlaylistTracksState extends State<PlaylistTracks> {
  MusicPlaylist? _playlist;
  bool _loading = false;
  bool _editing = false;
  String? _error;
  int _revision = 0;
  late int _collectionRevision;

  @override
  void initState() {
    super.initState();
    _collectionRevision = widget.collections.playlistRevision;
    widget.collections.addListener(_collectionsChanged);
    _load();
  }

  void _collectionsChanged() {
    if (_collectionRevision != widget.collections.playlistRevision) {
      _collectionRevision = widget.collections.playlistRevision;
      _load();
    }
  }

  Future<void> _load() async {
    final revision = ++_revision;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final playlist = await widget.collections.client.playlist(
        widget.playlistId,
      );
      if (mounted && revision == _revision) {
        setState(() => _playlist = playlist);
      }
    } on NavidromeException catch (error) {
      if (mounted && revision == _revision) {
        setState(() => _error = error.message);
      }
    } finally {
      if (mounted && revision == _revision) setState(() => _loading = false);
    }
  }

  Future<void> _remove(int index) async {
    if (_editing || _loading || _error != null) return;
    setState(() => _editing = true);
    try {
      await widget.collections.removeFromPlaylist(_playlist!, index);
    } on NavidromeException {
      // A rejected stale edit refreshes the screen; it never retries the edit.
      await _load();
      rethrow;
    } finally {
      if (mounted) setState(() => _editing = false);
    }
  }

  void _addSongs() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (context) => FractionallySizedBox(
      heightFactor: .9,
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              tooltip: 'Close add songs',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded),
            ),
          ),
          Expanded(
            child: LibrarySearch(
              client: widget.collections.client,
              playback: widget.playback,
              onAlbumSelected: (_) {},
              onSongSelected: (song) =>
                  widget.collections.addToPlaylist(widget.playlistId, song.id),
            ),
          ),
        ],
      ),
    ),
  );

  @override
  void dispose() {
    widget.collections.removeListener(_collectionsChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playlist = _playlist;
    final editable = playlist?.owner == widget.collections.client.username;
    return StreamBuilder<PlaybackState>(
      stream: widget.playback.playbackState,
      initialData: widget.playback.playbackState.value,
      builder: (context, playing) {
        // Duplicate songs are distinct playlist positions. After editing,
        // only highlight a position if this order still matches the queue.
        final queue = widget.playback.queue.value;
        final sameOrder =
            playlist != null &&
            queue.length == playlist.tracks.length &&
            queue.indexed.every(
              (entry) => entry.$2.id == playlist.tracks[entry.$1].id,
            );
        return ArtworkBackdrop(
          client: widget.collections.client,
          coverArt: playlist?.coverArt,
          child: PullToRefresh(
            onRefresh: () async {
              if (!_editing) await _load();
            },
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.only(
                top: 16,
                bottom: MediaQuery.paddingOf(context).bottom + 16,
              ),
              itemCount: (playlist?.tracks.length ?? 0) + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    child: Column(
                      children: [
                        if (playlist != null) ...[
                          SizedBox(
                            width: 280,
                            child: CoverArt(
                              client: widget.collections.client,
                              id: playlist.coverArt,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            playlist.name,
                            style: Theme.of(context).textTheme.headlineSmall,
                            textAlign: TextAlign.center,
                          ),
                          Text('${playlist.tracks.length} songs'),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: Theme.of(context)
                                  .colorScheme
                                  .onSurface,
                              foregroundColor: Theme.of(context)
                                  .colorScheme
                                  .surface,
                              shape: const StadiumBorder(),
                            ),
                            onPressed: playlist.tracks.isEmpty
                                ? null
                                : () => widget.playback.playAlbum(
                                    widget.collections.client,
                                    playlist.tracks,
                                    0,
                                  ),
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: const Text('Play playlist'),
                          ),
                          if (editable)
                            TextButton.icon(
                              onPressed: _editing || _loading
                                  ? null
                                  : _addSongs,
                              icon: const Icon(
                                Icons.add_circle_outline_rounded,
                              ),
                              label: const Text('Add songs'),
                            ),
                          if (editable)
                            TextButton(
                              onPressed: _editing || _loading
                                  ? null
                                  : () => editPlaylistName(
                                      context,
                                      initialName: playlist.name,
                                      onSave: (name) => widget.collections
                                          .renamePlaylist(playlist.id, name),
                                    ),
                              child: const Text('Rename playlist'),
                            ),
                          if (playlist.tracks.isEmpty)
                            const Text('Add songs using their song menu.'),
                        ],
                        if (_loading || _editing)
                          const LinearProgressIndicator(),
                        if (_error != null)
                          Text(_error!, textAlign: TextAlign.center),
                        if (_error != null)
                          TextButton(
                            onPressed: _loading || _editing ? null : _load,
                            child: const Text('Retry'),
                          ),
                      ],
                    ),
                  );
                }
                final song = playlist!.tracks[index - 1];
                return ListTile(
                  selected: sameOrder && playing.data?.queueIndex == index - 1,
                  leading: SizedBox(width: 28, child: Text('$index')),
                  title: Text(
                    song.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${song.artist} · ${song.album}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: SongActions(
                    collections: widget.collections,
                    song: song,
                    enabled: !_editing && !_loading && _error == null,
                    onRemove: editable ? () => _remove(index - 1) : null,
                  ),
                  onTap: () => widget.playback.playAlbum(
                    widget.collections.client,
                    playlist.tracks,
                    index - 1,
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
