import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import '../../models/library.dart';
import '../../services/library_collections.dart';
import '../../services/navidrome_client.dart';
import '../../services/playback_service.dart';
import '../library/cover_art.dart';
import '../library/collection_actions.dart';
import '../library/catalog_widgets.dart';

enum _SearchPage { all, artists, albums, songs }

class LibrarySearch extends StatefulWidget {
  const LibrarySearch({
    super.key,
    required this.client,
    required this.playback,
    required this.onAlbumSelected,
    this.collections,
    this.onArtistSelected,
    this.onSongSelected,
  });

  final NavidromeClient client;
  final PlaybackService playback;
  final ValueChanged<Album> onAlbumSelected;
  final LibraryCollections? collections;
  final ValueChanged<Artist>? onArtistSelected;
  final Future<void> Function(Track)? onSongSelected;

  @override
  State<LibrarySearch> createState() => _LibrarySearchState();
}

class _LibrarySearchState extends State<LibrarySearch> {
  static const _pageSize = 20;
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final List<Album> _albums = [];
  final List<Track> _songs = [];
  final List<Artist> _artists = [];
  late _SearchPage _filter = widget.onSongSelected != null
      ? _SearchPage.songs
      : _SearchPage.all;
  final _adding = <String>{};

  Future<void> _add(Track song) async {
    if (!_adding.add(song.id)) return;
    setState(() {});
    try {
      await widget.onSongSelected!(song);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added ${song.title} to playlist.')),
        );
      }
    } on NavidromeException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _adding.remove(song.id));
    }
  }

  Timer? _debounce;
  String _query = '';
  int _revision = 0;
  int? _loadingRevision;
  bool _busy = false;
  bool _moreAlbums = false;
  bool _moreSongs = false;
  bool _moreArtists = false;
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
      _artists.clear();
      _error = null;
      _moreAlbums = false;
      _moreSongs = false;
      _moreArtists = false;
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
        albumCount:
            widget.onSongSelected == null &&
                (page == _SearchPage.all || page == _SearchPage.albums)
            ? _pageSize
            : 0,
        songCount: page == _SearchPage.all || page == _SearchPage.songs
            ? _pageSize
            : 0,
        artistCount:
            widget.onArtistSelected != null &&
                (page == _SearchPage.all || page == _SearchPage.artists)
            ? _pageSize
            : 0,
        artistOffset: page == _SearchPage.artists ? _artists.length : 0,
      );
      // A slow response for an earlier query must never replace a newer search.
      if (!mounted || revision != _revision) return;
      setState(() {
        if (page == _SearchPage.all) {
          _albums.clear();
          _songs.clear();
          _artists.clear();
        }
        if (page == _SearchPage.all || page == _SearchPage.albums) {
          _albums.addAll(results.albums);
          _moreAlbums = results.albums.length == _pageSize;
        }
        if (page == _SearchPage.all || page == _SearchPage.songs) {
          _songs.addAll(results.tracks);
          _moreSongs = results.tracks.length == _pageSize;
        }
        if (page == _SearchPage.all || page == _SearchPage.artists) {
          _artists.addAll(results.artists);
          _moreArtists = results.artists.length == _pageSize;
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
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleLarge
          ?.copyWith(fontWeight: FontWeight.w700),
    ),
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
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
        child: Text(
          widget.onSongSelected != null ? 'Add songs' : 'Search',
          style: Theme.of(context).textTheme.headlineLarge,
        ),
      ),
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
            floatingLabelBehavior: FloatingLabelBehavior.never,
            fillColor: Theme.of(context).colorScheme.surfaceContainer
                .withValues(alpha: .4),
            hintText: 'Artists, albums and songs',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(28),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(28),
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant
                    .withValues(alpha: .3),
              ),
            ),
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
      if (widget.onSongSelected == null)
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: _SearchPage.values
                .where(
                  (page) =>
                      page != _SearchPage.artists ||
                      widget.onArtistSelected != null,
                )
                .map(
                  (page) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      key: ValueKey('search-filter-${page.name}'),
                      label: Text(
                        '${page.name[0].toUpperCase()}${page.name.substring(1)}',
                      ),
                      selected: _filter == page,
                      shape: const StadiumBorder(),
                      side: BorderSide(
                        color: Theme.of(context).colorScheme.onSurface
                            .withValues(alpha: .14),
                      ),
                      showCheckmark: false,
                      onSelected: (_) => setState(() => _filter = page),
                    ),
                  ),
                )
                .toList(),
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
              if ((_filter == _SearchPage.all ||
                      _filter == _SearchPage.artists) &&
                  _artists.isNotEmpty) ...[
                SliverToBoxAdapter(child: _heading('Artists')),
                SliverList.builder(
                  itemCount: _artists.length,
                  itemBuilder: (_, index) => ArtistRow(
                    artist: _artists[index],
                    client: widget.client,
                    onTap: () {
                      FocusScope.of(context).unfocus();
                      widget.onArtistSelected?.call(_artists[index]);
                    },
                  ),
                ),
                if (_moreArtists)
                  SliverToBoxAdapter(
                    child: TextButton(
                      onPressed: _busy
                          ? null
                          : () => _load(_revision, page: _SearchPage.artists),
                      child: const Text('More artists'),
                    ),
                  ),
              ],
              if ((_filter == _SearchPage.all ||
                      _filter == _SearchPage.albums) &&
                  _albums.isNotEmpty) ...[
                SliverToBoxAdapter(child: _heading('Albums')),
                AlbumGrid(
                  albums: _albums,
                  client: widget.client,
                  onSelected: (album) {
                    FocusScope.of(context).unfocus();
                    widget.onAlbumSelected(album);
                  },
                ),
              ],
              if ((_filter == _SearchPage.all ||
                      _filter == _SearchPage.albums) &&
                  _moreAlbums)
                SliverToBoxAdapter(
                  child: TextButton(
                    onPressed: _busy
                        ? null
                        : () => _load(_revision, page: _SearchPage.albums),
                    child: const Text('More albums'),
                  ),
                ),
              if ((_filter == _SearchPage.all ||
                      _filter == _SearchPage.songs) &&
                  _songs.isNotEmpty) ...[
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
                      trailing: widget.onSongSelected != null
                          ? IconButton(
                              tooltip: 'Add ${song.title} to playlist',
                              onPressed: _adding.contains(song.id)
                                  ? null
                                  : () => _add(song),
                              icon: const Icon(
                                Icons.add_circle_outline_rounded,
                              ),
                            )
                          : widget.collections == null
                          ? const Icon(Icons.play_arrow_rounded)
                          : SongActions(
                              collections: widget.collections!,
                              song: song,
                            ),
                      onTap: () {
                        FocusScope.of(context).unfocus();
                        if (widget.onSongSelected != null) {
                          _add(song);
                          return;
                        }
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
              if ((_filter == _SearchPage.all ||
                      _filter == _SearchPage.songs) &&
                  _moreSongs)
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
                  (_filter == _SearchPage.all
                      ? _albums.isEmpty && _songs.isEmpty && _artists.isEmpty
                      : switch (_filter) {
                          _SearchPage.artists => _artists.isEmpty,
                          _SearchPage.albums => _albums.isEmpty,
                          _SearchPage.songs => _songs.isEmpty,
                          _SearchPage.all => false,
                        }))
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
