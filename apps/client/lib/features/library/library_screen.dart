import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import '../../models/library.dart';
import '../../services/library_collections.dart';
import '../../services/navidrome_client.dart';
import '../../services/playback_service.dart';
import '../../widgets/glass_surface.dart';
import '../favorites/favorites_screen.dart';
import '../player/player_controls.dart';
import '../playlists/playlist_tracks.dart';
import '../playlists/playlists_screen.dart';
import '../search/library_search.dart';
import '../settings/settings_sheet.dart';
import 'album_tracks.dart';
import 'artwork_backdrop.dart';
import 'catalog_widgets.dart';
import 'collection_actions.dart';
import 'cover_art.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    required this.client,
    required this.playback,
    required this.onDisconnect,
  });
  final NavidromeClient client;
  final PlaybackService playback;
  final Future<void> Function() onDisconnect;
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _albums = <Album>[];
  final _browseKey = GlobalKey();
  late final LibraryCollections _collections;
  late Future<List<Album>> _recent;
  Album? _selected;
  Artist? _artist;
  String? _playlistId;
  String? _libraryPage;
  int _section = 0;
  bool _busy = false;
  bool _more = true;
  bool _disconnecting = false;
  String? _error;
  bool get _hasSelection =>
      _selected != null || _playlistId != null || _artist != null;

  @override
  void initState() {
    super.initState();
    _collections = LibraryCollections(widget.client);
    _recent = widget.client.albums(recent: true, size: 12);
    _collections.refreshFavorites();
    _load();
  }

  @override
  void dispose() {
    _collections.dispose();
    super.dispose();
  }

  void _selectAlbum(Album album) => setState(() {
    _selected = album;
    _playlistId = null;
  });
  void _selectArtist(Artist artist) => setState(() {
    _artist = artist;
    _selected = null;
    _playlistId = null;
  });
  void _back() => setState(() {
    if (_selected != null || _playlistId != null) {
      _selected = null;
      _playlistId = null;
    } else if (_artist != null) {
      _artist = null;
    } else {
      _libraryPage = null;
    }
  });

  void _tab(int index) {
    FocusScope.of(context).unfocus();
    setState(() {
      _section = index;
      _selected = null;
      _playlistId = null;
      _artist = null;
      if (index == 2) _libraryPage = null;
    });
    if (index == 0) _collections.refreshFavorites();
  }

  void _openCategory(String page) {
    setState(() {
      _section = 2;
      _libraryPage = page;
      _selected = null;
      _playlistId = null;
      _artist = null;
    });
    if (page == 'Playlists') _collections.refreshPlaylists();
    if (page == 'Favorites') _collections.refreshFavorites();
  }

  Future<void> _load({bool refresh = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final albums = await widget.client.albums(
        offset: refresh ? 0 : _albums.length,
      );
      if (!mounted) return;
      setState(() {
        if (refresh) _albums.clear();
        _albums.addAll(albums);
        _more = albums.length == 40;
      });
    } on NavidromeException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _refresh() {
    setState(() => _recent = widget.client.albums(recent: true, size: 12));
    _collections.refreshFavorites();
    _load(refresh: true);
  }

  Future<void> _disconnect() async {
    if (_disconnecting) return;
    setState(() => _disconnecting = true);
    try {
      await widget.onDisconnect();
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not finish disconnecting or remove your saved account. Please try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _disconnecting = false);
    }
  }

  Widget _heading(String title, {bool large = false}) => Padding(
    padding: EdgeInsets.fromLTRB(24, large ? 8 : 24, 24, 12),
    child: Text(
      title,
      style: large
          ? Theme.of(context).textTheme.headlineLarge
          : Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
    ),
  );

  Widget _albumStatus() => SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: _busy
            ? const CircularProgressIndicator()
            : _error != null
            ? Column(
                children: [
                  Text(_error!),
                  TextButton(onPressed: _load, child: const Text('Retry')),
                ],
              )
            : _albums.isEmpty
            ? const Text('No albums yet. Check your Navidrome library scan.')
            : _more
            ? TextButton(
                onPressed: _load,
                child: const Text('Load more albums'),
              )
            : const SizedBox.shrink(),
      ),
    ),
  );

  Widget _home() => CustomScrollView(
    key: const PageStorageKey('home'),
    slivers: [
      SliverToBoxAdapter(child: _heading('Home', large: true)),
      SliverToBoxAdapter(
        child: FutureBuilder<List<Album>>(
          future: _recent,
          builder: (context, snapshot) {
            final recent = snapshot.data ?? [];
            if (snapshot.connectionState != ConnectionState.done) {
              return const SizedBox(height: 8);
            }
            if (snapshot.hasError) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: TextButton(
                  onPressed: _refresh,
                  child: const Text('Retry recently played'),
                ),
              );
            }
            if (recent.isEmpty) return const SizedBox.shrink();
            final scale = MediaQuery.textScalerOf(context).scale(1);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _heading('Recently played'),
                SizedBox(
                  height: 176 + 60 * scale,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    scrollDirection: Axis.horizontal,
                    itemCount: recent.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 16),
                    itemBuilder: (_, index) => SizedBox(
                      width: 176,
                      child: AlbumCard(
                        album: recent[index],
                        client: widget.client,
                        onTap: () => _selectAlbum(recent[index]),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
      SliverToBoxAdapter(
        child: ListenableBuilder(
          listenable: _collections,
          builder: (context, _) {
            final songs = _collections.favoriteSongs.take(4).toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 16, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Favorite songs',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      TextButton(
                        onPressed: () => _openCategory('Favorites'),
                        child: const Text('See all'),
                      ),
                    ],
                  ),
                ),
                if (songs.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    child: Text(
                      _collections.favoritesError != null
                          ? 'Favorites could not load. Open Favorites to retry.'
                          : 'Heart a song to find it here.',
                    ),
                  ),
                for (var i = 0; i < songs.length; i++)
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                    leading: SizedBox(
                      width: 44,
                      height: 44,
                      child: CoverArt(
                        client: widget.client,
                        id: songs[i].coverArt,
                      ),
                    ),
                    title: Text(
                      songs[i].title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(songs[i].artist, maxLines: 1),
                    trailing: FavoriteButton(
                      collections: _collections,
                      song: songs[i],
                    ),
                    onTap: () =>
                        widget.playback.playAlbum(widget.client, songs, i),
                  ),
              ],
            );
          },
        ),
      ),
      SliverToBoxAdapter(child: _heading('Recently added')),
      AlbumGrid(
        albums: _albums,
        client: widget.client,
        onSelected: _selectAlbum,
      ),
      _albumStatus(),
    ],
  );

  Widget _libraryHub() => CustomScrollView(
    key: const PageStorageKey('library-hub'),
    slivers: [
      SliverToBoxAdapter(child: _heading('Library', large: true)),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Material(
            color: Theme.of(context).colorScheme.surfaceContainer
                .withValues(alpha: .65),
            borderRadius: BorderRadius.circular(22),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final entry in const [
                  ('Artists', Icons.mic_none_rounded),
                  ('Albums', Icons.album_outlined),
                  ('Songs', Icons.music_note_rounded),
                  ('Playlists', Icons.queue_music_rounded),
                  ('Favorites', Icons.favorite_border_rounded),
                ])
                  ListTile(
                    leading: Icon(
                      entry.$2,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    title: Text(entry.$1),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _openCategory(entry.$1),
                  ),
              ],
            ),
          ),
        ),
      ),
      SliverToBoxAdapter(child: _heading('Recently added')),
      AlbumGrid(
        albums: _albums,
        client: widget.client,
        onSelected: _selectAlbum,
      ),
      _albumStatus(),
    ],
  );

  Widget _catalog(String kind, {Artist? artist}) => CatalogPage(
    key: ValueKey(artist?.id ?? kind),
    kind: kind,
    artist: artist,
    client: widget.client,
    playback: widget.playback,
    collections: _collections,
    onAlbum: _selectAlbum,
    onArtist: _selectArtist,
  );

  Widget _library() => switch (_libraryPage) {
    'Playlists' => PlaylistsScreen(
      collections: _collections,
      onSelected: (playlist) => setState(() {
        _playlistId = playlist.id;
        _selected = null;
      }),
    ),
    'Favorites' => FavoritesScreen(
      collections: _collections,
      playback: widget.playback,
      onAlbumSelected: _selectAlbum,
    ),
    final String category => _catalog(category),
    null => _libraryHub(),
  };

  Widget _trackPane() {
    if (_playlistId != null) {
      return PlaylistTracks(
        key: ValueKey('playlist:$_playlistId'),
        playlistId: _playlistId!,
        collections: _collections,
        playback: widget.playback,
      );
    }
    if (_selected case final Album album) {
      return AlbumTracks(
        key: ValueKey(album.id),
        client: widget.client,
        album: album,
        playback: widget.playback,
        collections: _collections,
        onPlay: (tracks, index) => widget.playback.playAlbum(
          widget.client,
          tracks,
          index,
          coverArtId: album.coverArt,
        ),
      );
    }
    return _catalog('Albums', artist: _artist);
  }

  Widget _browsePane() => IndexedStack(
    key: _browseKey,
    index: _section,
    children: [
      _home(),
      LibrarySearch(
        client: widget.client,
        playback: widget.playback,
        collections: _collections,
        onAlbumSelected: _selectAlbum,
        onArtistSelected: _selectArtist,
      ),
      _library(),
    ],
  );

  String get _backLabel => _selected != null && _artist != null
      ? 'Back to artist'
      : _hasSelection
      ? _section == 1
            ? 'Back to search'
            : _libraryPage == 'Playlists'
            ? 'Back to playlists'
            : _libraryPage == 'Favorites'
            ? 'Back to favorites'
            : 'Back to albums'
      : 'Back to library';

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 950;
    return PopScope(
      canPop: !_hasSelection && _libraryPage == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: StreamBuilder<MediaItem?>(
        stream: widget.playback.mediaItem,
        initialData: widget.playback.mediaItem.value,
        builder: (context, playing) => ArtworkBackdrop(
          client: widget.client,
          coverArt: playing.data?.extras?['coverArtId'] as String?,
          immersive: false,
          child: Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              toolbarHeight: 44,
              leading: _hasSelection || _libraryPage != null
                  ? IconButton(
                      tooltip: _backLabel,
                      onPressed: _back,
                      icon: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 20,
                      ),
                    )
                  : null,
              actions: [
                IconButton(
                  tooltip: 'Settings',
                  icon: const Icon(Icons.tune_rounded),
                  onPressed: _disconnecting
                      ? null
                      : () => showSettings(
                          context,
                          widget.playback,
                          onDisconnect: _disconnect,
                        ),
                ),
                IconButton(
                  tooltip: 'Refresh albums',
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: _busy || _disconnecting ? null : _refresh,
                ),
                const SizedBox(width: 12),
              ],
            ),
            body: SafeArea(
              bottom: false,
              child: AbsorbPointer(
                absorbing: _disconnecting,
                child: Column(
                  children: [
                    if (_disconnecting) const LinearProgressIndicator(),
                    Expanded(
                      child: Row(
                        children: [
                          if (wide)
                            NavigationRail(
                              backgroundColor: Colors.transparent,
                              labelType: NavigationRailLabelType.all,
                              selectedIndex: _section,
                              onDestinationSelected: _tab,
                              destinations: const [
                                NavigationRailDestination(
                                  icon: Icon(Icons.home_outlined),
                                  selectedIcon: Icon(Icons.home_rounded),
                                  label: Text('Home'),
                                ),
                                NavigationRailDestination(
                                  icon: Icon(Icons.search_rounded),
                                  label: Text('Search'),
                                ),
                                NavigationRailDestination(
                                  icon: Icon(Icons.library_music_outlined),
                                  selectedIcon: Icon(
                                    Icons.library_music_rounded,
                                  ),
                                  label: Text('Library'),
                                ),
                              ],
                            ),
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, bounds) {
                                if (wide && bounds.maxWidth >= 760) {
                                  return Row(
                                    children: [
                                      Expanded(child: _browsePane()),
                                      const VerticalDivider(width: 1),
                                      SizedBox(
                                        width: 370,
                                        child: _hasSelection
                                            ? _trackPane()
                                            : const Center(
                                                child: Padding(
                                                  padding: EdgeInsets.all(32),
                                                  child: Text(
                                                    'Choose an album or artist to explore.',
                                                    textAlign: TextAlign.center,
                                                  ),
                                                ),
                                              ),
                                      ),
                                    ],
                                  );
                                }
                                return Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Offstage(
                                      offstage: _hasSelection,
                                      child: _browsePane(),
                                    ),
                                    if (_hasSelection) _trackPane(),
                                  ],
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            bottomNavigationBar: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PlayerControls(
                    playback: widget.playback,
                    client: widget.client,
                    collections: _collections,
                  ),
                  if (!wide)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                      child: GlassSurface(
                        radius: 32,
                        child: NavigationBar(
                          backgroundColor: Colors.transparent,
                          elevation: 0,
                          height: 64,
                          indicatorColor: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: .12),
                          selectedIndex: _section,
                          onDestinationSelected: _disconnecting ? null : _tab,
                          destinations: const [
                            NavigationDestination(
                              icon: Icon(Icons.home_outlined),
                              selectedIcon: Icon(Icons.home_rounded),
                              label: 'Home',
                            ),
                            NavigationDestination(
                              icon: Icon(Icons.search_rounded),
                              label: 'Search',
                            ),
                            NavigationDestination(
                              icon: Icon(Icons.library_music_outlined),
                              selectedIcon: Icon(Icons.library_music_rounded),
                              label: 'Library',
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
