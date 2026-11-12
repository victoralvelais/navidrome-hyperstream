import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../models/library.dart';
import '../../services/library_collections.dart';
import '../../services/navidrome_client.dart';
import '../../services/playback_service.dart';
import '../../services/account_session.dart';
import '../../services/recent_radio_service.dart';
import '../../services/smart_playlist_store.dart';
import '../../widgets/pull_to_refresh.dart';
import '../../widgets/glass_surface.dart';
import '../favorites/favorites_screen.dart';
import '../player/player_controls.dart';
import '../playlists/playlist_tracks.dart';
import '../playlists/playlists_screen.dart';
import '../playlists/recent_radio_screen.dart';
import '../playlists/smart_playlists_screen.dart';
import '../search/library_search.dart';
import '../settings/settings_sheet.dart';
import 'album_tracks.dart';
import 'artwork_backdrop.dart';
import 'catalog_widgets.dart';

enum _Section { home, library, search }

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    required this.client,
    required this.playback,
    required this.onDisconnect,
    this.accountSession,
  });
  final NavidromeClient client;
  final PlaybackService playback;
  final Future<void> Function() onDisconnect;
  final AccountSession? accountSession;
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with WidgetsBindingObserver {
  final _albums = <Album>[];
  final _browseKey = GlobalKey();
  final _settingsKey = GlobalKey<SettingsPageState>();
  final _smartKey = GlobalKey<SmartPlaylistsScreenState>();
  ScrollDirection _scrollDirection = ScrollDirection.idle;
  late final LibraryCollections _collections;
  late final RecentRadioService _radio;
  late final SmartPlaylistStore _smartStore;
  bool _smartHasPage = false;
  bool _createSmartOnOpen = false;
  Album? _selected;
  Artist? _artist;
  String? _playlistId;
  String? _libraryPage;
  _Section _section = _Section.home;
  bool _busy = false;
  bool _more = true;
  bool _disconnecting = false;
  bool _homeHasPage = false;
  bool _dockCollapsed = false;
  String? _error;
  bool get _hasSelection =>
      _selected != null || _playlistId != null || _artist != null;

  @override
  void initState() {
    super.initState();
    _collections = LibraryCollections(widget.client);
    _radio = RecentRadioService(widget.client);
    _smartStore = SmartPlaylistStore(widget.client);
    WidgetsBinding.instance.addObserver(this);
    _radio.setAppActive(
      WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
    );
    _collections.refreshFavorites();
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _collections.dispose();
    _smartStore.dispose();
    _radio.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _radio.setAppActive(state == AppLifecycleState.resumed);
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
  void _back() {
    if (_libraryPage == 'Smart playlists' &&
        (_smartKey.currentState?.back() ?? false)) {
      return;
    }
    setState(() {
      if (_selected != null || _playlistId != null) {
        _selected = null;
        _playlistId = null;
      } else if (_artist != null) {
        _artist = null;
      } else {
        _libraryPage =
            ['Recent Radio', 'Smart playlists'].contains(_libraryPage)
            ? 'Playlists'
            : null;
      }
    });
  }

  void _tab(int index) {
    FocusScope.of(context).unfocus();
    if (index == _Section.home.index) _settingsKey.currentState?.back();
    setState(() {
      _section = _Section.values[index];
      _dockCollapsed = false;
      _scrollDirection = ScrollDirection.idle;
      _selected = null;
      _playlistId = null;
      _artist = null;
      _libraryPage = null;
      _smartHasPage = false;
    });
  }

  void _openCategory(String page) {
    setState(() {
      _section = _Section.library;
      _libraryPage = page;
      _smartHasPage = false;
      _selected = null;
      _playlistId = null;
      _artist = null;
    });
    if (page == 'Playlists') _collections.refreshPlaylists();
    if (page == 'Favorites') _collections.refreshFavorites();
  }

  void _openSmart({bool create = false}) {
    _createSmartOnOpen = create;
    _openCategory('Smart playlists');
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

  Future<void> _refresh() async {
    await Future.wait([_collections.refreshFavorites(), _load(refresh: true)]);
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

  Widget _home() => SettingsPage(
    key: _settingsKey,
    playback: widget.playback,
    session: widget.accountSession,
    onDisconnect: _disconnect,
    onPageChanged: (hasPage) => setState(() {
      _homeHasPage = hasPage;
      _dockCollapsed = false;
      _scrollDirection = ScrollDirection.idle;
    }),
  );

  Widget _libraryHub() => PullToRefresh(
    onRefresh: _refresh,
    child: CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
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
        const SliverToBoxAdapter(child: DockSpacer()),
      ],
    ),
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
    'Recent Radio' => RecentRadioScreen(
      radio: _radio,
      playback: widget.playback,
    ),
    'Smart playlists' => SmartPlaylistsScreen(
      key: _smartKey,
      catalog: _radio,
      store: _smartStore,
      playback: widget.playback,
      createOnOpen: _createSmartOnOpen,
      onPageChanged: (value) {
        if (mounted) setState(() => _smartHasPage = value);
      },
    ),
    'Playlists' => PlaylistsScreen(
      collections: _collections,
      onSmartPlaylists: () => _openSmart(),
      onNewSmartPlaylist: () => _openSmart(create: true),
      onRecentRadio: () => _openCategory('Recent Radio'),
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
    index: _section.index,
    children: [
      _home(),
      _library(),
      LibrarySearch(
        discover: true,
        client: widget.client,
        playback: widget.playback,
        collections: _collections,
        onAlbumSelected: _selectAlbum,
        onArtistSelected: _selectArtist,
      ),
    ],
  );

  String get _backLabel => _libraryPage == 'Smart playlists' && _smartHasPage
      ? 'Back to smart playlists'
      : _selected != null && _artist != null
      ? 'Back to artist'
      : _hasSelection
      ? _section == _Section.search
            ? 'Back to search'
            : _libraryPage == 'Playlists'
            ? 'Back to playlists'
            : _libraryPage == 'Favorites'
            ? 'Back to favorites'
            : 'Back to albums'
      : ['Recent Radio', 'Smart playlists'].contains(_libraryPage)
      ? 'Back to playlists'
      : 'Back to library';

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 950;
    return PopScope(
      canPop:
          !(_section == _Section.home && _homeHasPage) &&
          !_hasSelection &&
          _libraryPage == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop &&
            !(_section == _Section.home &&
                (_settingsKey.currentState?.back() ?? false))) {
          _back();
        }
      },
      child: StreamBuilder<MediaItem?>(
        stream: widget.playback.mediaItem,
        initialData: widget.playback.mediaItem.value,
        builder: (context, playing) => ArtworkBackdrop(
          client: widget.client,
          coverArt: playing.data?.extras?['coverArtId'] as String?,
          immersive: false,
          child: Scaffold(
            extendBody: true,
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              toolbarHeight: (_hasSelection || _libraryPage != null) ? 44 : 8,
              leading: (_hasSelection || _libraryPage != null)
                  ? IconButton(
                      tooltip: _backLabel,
                      onPressed: _back,
                      icon: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 20,
                      ),
                    )
                  : null,
            ),
            body: SafeArea(
              bottom: false,
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (wide ||
                      notification.metrics.axis != Axis.vertical ||
                      notification.depth != 0) {
                    return false;
                  }
                  if (notification is UserScrollNotification) {
                    _scrollDirection = notification.direction;
                  }
                  final collapse =
                      _scrollDirection == ScrollDirection.reverse &&
                      notification.metrics.pixels > 48;
                  final expand =
                      _scrollDirection == ScrollDirection.forward ||
                      notification.metrics.pixels <= 0;
                  if ((collapse && !_dockCollapsed) ||
                      (expand && _dockCollapsed)) {
                    setState(() => _dockCollapsed = collapse);
                  }
                  return false;
                },
                child: AbsorbPointer(
                  absorbing:
                      _disconnecting || (widget.accountSession?.busy ?? false),
                  child: Column(
                    children: [
                      if (_disconnecting ||
                          (widget.accountSession?.busy ?? false))
                        const LinearProgressIndicator(),
                      Expanded(
                        child: Row(
                          children: [
                            if (wide)
                              NavigationRail(
                                backgroundColor: Colors.transparent,
                                labelType: NavigationRailLabelType.all,
                                selectedIndex: _section.index,
                                onDestinationSelected: _tab,
                                destinations: const [
                                  NavigationRailDestination(
                                    icon: Icon(Icons.home_outlined),
                                    selectedIcon: Icon(Icons.home_rounded),
                                    label: Text('Home'),
                                  ),
                                  NavigationRailDestination(
                                    icon: Icon(Icons.library_music_outlined),
                                    selectedIcon: Icon(
                                      Icons.library_music_rounded,
                                    ),
                                    label: Text('Library'),
                                  ),
                                  NavigationRailDestination(
                                    icon: Icon(Icons.search_rounded),
                                    label: Text('Search'),
                                  ),
                                ],
                              ),
                            Expanded(
                              child: LayoutBuilder(
                                builder: (context, bounds) {
                                  if (wide &&
                                      bounds.maxWidth >= 760 &&
                                      _section != _Section.home &&
                                      ![
                                        'Recent Radio',
                                        'Smart playlists',
                                      ].contains(_libraryPage)) {
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
                                                      textAlign:
                                                          TextAlign.center,
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
            ),
            bottomNavigationBar: SafeArea(
              top: false,
              child: AnimatedSize(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment: Alignment.bottomCenter,
                child: AbsorbPointer(
                  absorbing:
                      _disconnecting || (widget.accountSession?.busy ?? false),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!wide &&
                          _dockCollapsed &&
                          MediaQuery.textScalerOf(context).scale(1) <= 1.2)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                          child: Row(
                            children: [
                              GlassSurface(
                                radius: 30,
                                child: IconButton(
                                  tooltip: 'Expand navigation',
                                  onPressed: () =>
                                      setState(() => _dockCollapsed = false),
                                  icon: Icon(
                                    _section == _Section.home
                                        ? Icons.home_rounded
                                        : _section == _Section.search
                                        ? Icons.explore_rounded
                                        : Icons.library_music_rounded,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: PlayerControls(
                                  playback: widget.playback,
                                  client: widget.client,
                                  collections: _collections,
                                  compact: true,
                                ),
                              ),
                              const SizedBox(width: 8),
                              GlassSurface(
                                radius: 30,
                                child: IconButton(
                                  tooltip: 'Search',
                                  onPressed: () => _tab(_Section.search.index),
                                  icon: const Icon(Icons.search_rounded),
                                ),
                              ),
                            ],
                          ),
                        )
                      else ...[
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
                                selectedIndex: _section.index,
                                onDestinationSelected: _disconnecting
                                    ? null
                                    : _tab,
                                destinations: const [
                                  NavigationDestination(
                                    icon: Icon(Icons.home_outlined),
                                    selectedIcon: Icon(Icons.home_rounded),
                                    label: 'Home',
                                  ),
                                  NavigationDestination(
                                    icon: Icon(Icons.library_music_outlined),
                                    selectedIcon: Icon(
                                      Icons.library_music_rounded,
                                    ),
                                    label: 'Library',
                                  ),
                                  NavigationDestination(
                                    icon: Icon(Icons.search_rounded),
                                    label: 'Search',
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
