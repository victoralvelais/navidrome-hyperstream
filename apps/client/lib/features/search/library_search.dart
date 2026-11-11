import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import '../../models/library.dart';
import '../../services/library_collections.dart';
import '../../services/navidrome_client.dart';
import '../../services/playback_service.dart';
import '../library/cover_art.dart';
import '../library/collection_actions.dart';

enum _SearchPage { all, albums, songs }

class LibrarySearch extends StatefulWidget {
  const LibrarySearch({
    super.key,
    required this.client,
    required this.playback,
    required this.onAlbumSelected,
    this.collections,
  });

  final NavidromeClient client;
  final PlaybackService playback;
  final ValueChanged<Album> onAlbumSelected;
  final LibraryCollections? collections;

  @override
  State<LibrarySearch> createState() => _LibrarySearchState();
}

class _LibrarySearchState extends State<LibrarySearch> {
  static const _pageSize = 20;
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final List<Album> _albums = [];
  final List<Track> _songs = [];
  Timer? _debounce;
  String _query = '';
  int _revision = 0;
  int? _loadingRevision;
  bool _busy = false;
  bool _moreAlbums = false;
  bool _moreSongs = false;
  String? _error;
  _SearchPage _failedPage = _SearchPage.all;

  void _changed(String text) {
    final query = text.trim();
    if (query == _query) return;
    _debounce?.cancel();
    final revision = ++_revision;
    setState(() {
      _query = query;
      _albums.clear();
      _songs.clear();
      _error = null;
      _moreAlbums = false;
      _moreSongs = false;
      _busy = query.isNotEmpty;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    if (query.isNotEmpty) {
      _debounce = Timer(
        const Duration(milliseconds: 350),
        () => _load(revision),
      );
    }
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    if (_debounce?.isActive ?? false) {
      _debounce!.cancel();
      _load(_revision);
    }
  }

  Future<void> _load(int revision, {_SearchPage page = _SearchPage.all}) async {
    final query = _query;
    if (query.isEmpty || _loadingRevision == revision) return;
    _loadingRevision = revision;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final results = await widget.client.search(
        query,
        albumOffset: page == _SearchPage.albums ? _albums.length : 0,
        songOffset: page == _SearchPage.songs ? _songs.length : 0,
        albumCount: page == _SearchPage.songs ? 0 : _pageSize,
        songCount: page == _SearchPage.albums ? 0 : _pageSize,
      );
      // A slow response for an earlier query must never replace a newer search.
      if (!mounted || revision != _revision) return;
      setState(() {
        if (page == _SearchPage.all) {
          _albums.clear();
          _songs.clear();
        }
        if (page != _SearchPage.songs) {
          _albums.addAll(results.albums);
          _moreAlbums = results.albums.length == _pageSize;
        }
        if (page != _SearchPage.albums) {
          _songs.addAll(results.tracks);
          _moreSongs = results.tracks.length == _pageSize;
        }
      });
    } on NavidromeException catch (error) {
      if (mounted && revision == _revision) {
        setState(() {
          _error = error.message;
          _failedPage = page;
        });
      }
    } finally {
      if (mounted && revision == _revision) {
        _loadingRevision = null;
        setState(() => _busy = false);
      }
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
    child: Text(text, style: Theme.of(context).textTheme.titleLarge),
  );

  Widget _message(String text, {IconData? icon}) => Padding(
    padding: const EdgeInsets.all(32),
    child: Column(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
        ],
        Text(text, textAlign: TextAlign.center),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
        child: TextField(
          controller: _controller,
          onChanged: _changed,
          onSubmitted: (_) => _submit(),
          textInputAction: TextInputAction.search,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: 'Search your library',
            hintText: 'Albums and songs',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () {
                      _controller.clear();
                      _changed('');
                    },
                  ),
          ),
        ),
      ),
      if (_busy) const LinearProgressIndicator(),
      Expanded(
        child: StreamBuilder<MediaItem?>(
          stream: widget.playback.mediaItem,
          initialData: widget.playback.mediaItem.value,
          builder: (context, playing) => CustomScrollView(
            controller: _scroll,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              if (_query.isEmpty)
                SliverToBoxAdapter(
                  child: _message(
                    'Find your next listen. Search albums and songs in your Navidrome library.',
                    icon: Icons.manage_search_rounded,
                  ),
                ),
              if (_albums.isNotEmpty) ...[
                SliverToBoxAdapter(child: _heading('Albums')),
                SliverList.builder(
                  itemCount: _albums.length,
                  itemBuilder: (context, index) {
                    final album = _albums[index];
                    return ListTile(
                      leading: SizedBox(
                        width: 48,
                        height: 48,
                        child: CoverArt(
                          client: widget.client,
                          id: album.coverArt,
                        ),
                      ),
                      title: Text(
                        album.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        album.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: widget.collections == null
                          ? const Icon(Icons.chevron_right_rounded)
                          : FavoriteButton(
                              collections: widget.collections!,
                              album: album,
                            ),
                      onTap: () {
                        FocusScope.of(context).unfocus();
                        widget.onAlbumSelected(album);
                      },
                    );
                  },
                ),
              ],
              if (_moreAlbums)
                SliverToBoxAdapter(
                  child: TextButton(
                    onPressed: _busy
                        ? null
                        : () => _load(_revision, page: _SearchPage.albums),
                    child: const Text('More albums'),
                  ),
                ),
              if (_songs.isNotEmpty) ...[
                SliverToBoxAdapter(child: _heading('Songs')),
                SliverList.builder(
                  itemCount: _songs.length,
                  itemBuilder: (context, index) {
                    final song = _songs[index];
                    return ListTile(
                      selected: playing.data?.id == song.id,
                      leading: SizedBox(
                        width: 48,
                        height: 48,
                        child: CoverArt(
                          client: widget.client,
                          id: song.coverArt,
                        ),
                      ),
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
                      trailing: widget.collections == null
                          ? const Icon(Icons.play_arrow_rounded)
                          : SongActions(
                              collections: widget.collections!,
                              song: song,
                            ),
                      onTap: () {
                        FocusScope.of(context).unfocus();
                        // Snapshot the loaded results so later paging/searching
                        // cannot mutate a queue while the native player loads.
                        widget.playback.playAlbum(
                          widget.client,
                          List.of(_songs),
                          index,
                        );
                      },
                    );
                  },
                ),
              ],
              if (_moreSongs)
                SliverToBoxAdapter(
                  child: TextButton(
                    onPressed: _busy
                        ? null
                        : () => _load(_revision, page: _SearchPage.songs),
                    child: const Text('More songs'),
                  ),
                ),
              if (!_busy && _error != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        TextButton(
                          onPressed: () => _load(_revision, page: _failedPage),
                          child: const Text('Retry search'),
                        ),
                      ],
                    ),
                  ),
                ),
              if (!_busy &&
                  _error == null &&
                  _query.isNotEmpty &&
                  _albums.isEmpty &&
                  _songs.isEmpty)
                SliverToBoxAdapter(
                  child: _message(
                    'No matches. Try another album, song, or artist name.',
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        ),
      ),
    ],
  );
}
