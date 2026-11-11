import 'package:flutter/material.dart';

import '../../models/library.dart';
import '../../services/library_collections.dart';
import '../../services/navidrome_client.dart';
import '../../services/playback_service.dart';
import '../player/player_controls.dart';
import '../favorites/favorites_screen.dart';
import '../playlists/playlists_screen.dart';
import '../playlists/playlist_tracks.dart';
import '../search/library_search.dart';
import '../settings/settings_sheet.dart';
import 'album_tracks.dart';
import 'cover_art.dart';
import '../../widgets/glass_surface.dart';

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
  final List<Album> _albums = [];
  final _browseKey = GlobalKey();
  Album? _selected;
  String? _playlistId;
  late final LibraryCollections _collections;
  bool get _hasSelection => _selected != null || _playlistId != null;
  int _section = 0;
  bool _busy = false;
  bool _more = true;
  bool _disconnecting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _collections = LibraryCollections(widget.client);
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
  void _back() => setState(() {
    _selected = null;
    _playlistId = null;
  });

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

  Widget _albumGrid() => CustomScrollView(
    key: const PageStorageKey('albums'),
    slivers: [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Library', style: Theme.of(context).textTheme.headlineLarge),
              const SizedBox(height: 20),
              Text(
                'Recently added',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
        sliver: SliverLayoutBuilder(
          builder: (context, constraints) {
            final columns = (constraints.crossAxisExtent / 190).floor().clamp(
              2,
              6,
            );
            final artworkSize =
                (constraints.crossAxisExtent - 16 * (columns - 1)) / columns;
            return SliverGrid.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisExtent:
                    artworkSize +
                    64 * MediaQuery.textScalerOf(context).scale(1),
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              itemCount: _albums.length,
              itemBuilder: (context, index) {
                final album = _albums[index];
                return InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _selectAlbum(album),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CoverArt(
                        key: ValueKey(album.id),
                        client: widget.client,
                        id: album.coverArt,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        album.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text(
                        album.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
      SliverToBoxAdapter(
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
                ? const Text(
                    'No albums yet. Check your Navidrome library scan.',
                  )
                : _more
                ? OutlinedButton(
                    onPressed: _load,
                    child: const Text('Load more albums'),
                  )
                : Text('${_albums.length} albums'),
          ),
        ),
      ),
    ],
  );

  Widget _trackPane() => _playlistId != null
      ? PlaylistTracks(
          key: ValueKey('playlist:$_playlistId'),
          playlistId: _playlistId!,
          collections: _collections,
          playback: widget.playback,
        )
      : AlbumTracks(
          key: ValueKey(_selected!.id),
          client: widget.client,
          album: _selected!,
          playback: widget.playback,
          collections: _collections,
          onPlay: (tracks, index) => widget.playback.playAlbum(
            widget.client,
            tracks,
            index,
            coverArtId: _selected!.coverArt,
          ),
        );

  // Keep browsing/search state alive while opening albums or changing tabs.
  Widget _browsePane() => IndexedStack(
    key: _browseKey,
    index: _section,
    children: [
      _albumGrid(),
      LibrarySearch(
        client: widget.client,
        playback: widget.playback,
        collections: _collections,
        onAlbumSelected: _selectAlbum,
      ),
      PlaylistsScreen(
        collections: _collections,
        onSelected: (playlist) => setState(() {
          _playlistId = playlist.id;
          _selected = null;
        }),
      ),
      FavoritesScreen(
        collections: _collections,
        playback: widget.playback,
        onAlbumSelected: _selectAlbum,
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_hasSelection,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _back();
    },
    child: Scaffold(
      appBar: AppBar(
        leading: !_hasSelection
            ? null
            : IconButton(
                tooltip: [
                  'Back to albums',
                  'Back to search',
                  'Back to playlists',
                  'Back to favorites',
                ][_section],
                icon: const Icon(Icons.arrow_back),
                onPressed: _back,
              ),
        title: const Text('Hyperstream'),
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
            icon: const Icon(Icons.refresh),
            onPressed: _busy || _disconnecting || _section != 0
                ? null
                : () => _load(refresh: true),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(1, -.9),
            radius: 1.5,
            colors: [
              Color.alphaBlend(
                Theme.of(context).colorScheme.primary.withValues(alpha: .055),
                Theme.of(context).colorScheme.surface,
              ),
              Theme.of(context).colorScheme.surface,
            ],
          ),
        ),
        child: SafeArea(
          child: AbsorbPointer(
            absorbing: _disconnecting,
            child: Column(
              children: [
                if (_disconnecting) const LinearProgressIndicator(),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth >= 850) {
                        return Row(
                          children: [
                            Expanded(child: _browsePane()),
                            const VerticalDivider(width: 1),
                            SizedBox(
                              width: 370,
                              child: Material(
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainer,
                                child: !_hasSelection
                                    ? const Center(
                                        child: Padding(
                                          padding: EdgeInsets.all(32),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.album_outlined,
                                                size: 64,
                                              ),
                                              SizedBox(height: 20),
                                              Text(
                                                'Choose something to play',
                                                textAlign: TextAlign.center,
                                              ),
                                              SizedBox(height: 8),
                                              Text(
                                                'Your next listen starts here.',
                                                textAlign: TextAlign.center,
                                              ),
                                            ],
                                          ),
                                        ),
                                      )
                                    : _trackPane(),
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
                PlayerControls(
                  playback: widget.playback,
                  client: widget.client,
                  collections: _collections,
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: GlassSurface(
            radius: 32,
            child: NavigationBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              height: 72,
              indicatorColor: Theme.of(context).colorScheme.primary
                  .withValues(alpha: .16),
              selectedIndex: _section,
              onDestinationSelected: _disconnecting
                  ? null
                  : (index) {
                      FocusScope.of(context).unfocus();
                      setState(() {
                        _section = index;
                        _selected = null;
                        _playlistId = null;
                      });
                      if (index == 2) _collections.refreshPlaylists();
                      if (index == 3) _collections.refreshFavorites();
                    },
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.library_music_outlined),
                  selectedIcon: Icon(Icons.library_music_rounded),
                  label: 'Library',
                ),
                NavigationDestination(
                  icon: Icon(Icons.search_rounded),
                  label: 'Search',
                ),
                NavigationDestination(
                  icon: Icon(Icons.queue_music_rounded),
                  label: 'Playlists',
                ),
                NavigationDestination(
                  icon: Icon(Icons.favorite_border_rounded),
                  selectedIcon: Icon(Icons.favorite_rounded),
                  label: 'Favorites',
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
