import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../models/library.dart';
import '../../services/playlist_icon_store.dart';
import '../../widgets/playlist_icon_picker.dart';
import '../../widgets/edge_back_gesture.dart';
import '../../widgets/floating_chrome.dart';
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
  final _smartKey = GlobalKey<SmartPlaylistScreenState>();
  ScrollDirection _scrollDirection = ScrollDirection.idle;
  late final LibraryCollections _collections;
  late final RecentRadioService _radio;
  late final SmartPlaylistStore _smartStore;
  late final PlaylistIconStore _icons;
  final _playlistKey = GlobalKey<PlaylistTracksState>();
  String? _smartId;
  MusicPlaylist? _playlistInfo;
  bool _compactTitle = false;
  int _navigationEpoch = 0;
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
      _selected != null ||
      _playlistId != null ||
      _artist != null ||
      _smartId != null;

  @override
  void initState() {
    super.initState();
    _collections = LibraryCollections(widget.client);
    _radio = RecentRadioService(widget.client);
    _smartStore = SmartPlaylistStore(widget.client);
    _icons = PlaylistIconStore(widget.client);
    _smartStore.load();
    _icons.load();
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
    _icons.dispose();
    _radio.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _radio.setAppActive(state == AppLifecycleState.resumed);
  }

  void _selectAlbum(Album album) => setState(() {
    _compactTitle = false;
    _navigationEpoch++;
    _selected = album;
    _playlistId = null;
  });
  void _selectArtist(Artist artist) => setState(() {
    _compactTitle = false;
    _navigationEpoch++;
    _artist = artist;
    _selected = null;
    _playlistId = null;
  });
  void _back() {
    if (_section == _Section.home &&
        (_settingsKey.currentState?.back() ?? false)) {
      return;
    }
    setState(() {
      _compactTitle = false;
      _navigationEpoch++;
      if (_selected != null || _playlistId != null || _smartId != null) {
        _smartId = null;
        _selected = null;
        _playlistId = null;
      } else if (_artist != null) {
        _artist = null;
      } else {
        _libraryPage = _libraryPage == 'Recent Radio' ? 'Playlists' : null;
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
      _smartId = null;
      _compactTitle = false;
      _navigationEpoch++;
    });
  }

  void _openCategory(String page) {
    setState(() {
      _section = _Section.library;
      _libraryPage = page;
      _smartId = null;
      _compactTitle = false;
      _navigationEpoch++;
      _selected = null;
      _playlistId = null;
      _artist = null;
    });
    if (page == 'Playlists') _collections.refreshPlaylists();
    if (page == 'Favorites') _collections.refreshFavorites();
  }

  Future<void> _newSmart() async {
    final id = await editSmartPlaylist(
      context,
      catalog: _radio,
      store: _smartStore,
      playback: widget.playback,
    );
    if (!mounted || id == null) return;
    setState(() {
      _smartId = id;
      _compactTitle = false;
      _navigationEpoch++;
    });
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
      _compactTitle = false;
      _navigationEpoch++;
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
    'Playlists' => PlaylistsScreen(
      collections: _collections,
      smartStore: _smartStore,
      icons: _icons,
      onSmartSelected: (item) => setState(() {
        _smartId = item.id;
        _compactTitle = false;
        _navigationEpoch++;
      }),
      onNewSmartPlaylist: _newSmart,
      onRecentRadio: () => _openCategory('Recent Radio'),
      onSelected: (playlist) => setState(() {
        _playlistId = playlist.id;
        _playlistInfo = playlist;
        _selected = null;
        _compactTitle = false;
        _navigationEpoch++;
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
    if (_smartId != null) {
      return SmartPlaylistScreen(
        key: _smartKey,
        id: _smartId!,
        catalog: _radio,
        store: _smartStore,
        icons: _icons,
        playback: widget.playback,
        onDeleted: _back,
      );
    }
    if (_playlistId != null) {
      return PlaylistTracks(
        key: _playlistKey,
        onLoaded: (playlist) {
          if (mounted) setState(() => _playlistInfo = playlist);
        },
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

  Widget _visiblePane(_Section section, Widget child) =>
      NotificationListener<ScrollNotification>(
        onNotification: (_) => _section != section || _hasSelection,
        child: child,
      );
  Widget _browsePane() => IndexedStack(
    key: _browseKey,
    index: _section.index,
    children: [
      _visiblePane(_Section.home, _home()),
      _visiblePane(_Section.library, _library()),
      _visiblePane(
        _Section.search,
        LibrarySearch(
          discover: true,
          client: widget.client,
          playback: widget.playback,
          collections: _collections,
          onAlbumSelected: _selectAlbum,
          onArtistSelected: _selectArtist,
        ),
      ),
    ],
  );

  bool get _canBack =>
      _hasSelection ||
      _libraryPage != null ||
      (_section == _Section.home && _homeHasPage);
  String get _backLabel => _section == _Section.home
      ? 'Back to home'
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
      : _libraryPage == 'Recent Radio'
      ? 'Back to playlists'
      : 'Back to library';
  String get _title => _smartId != null
      ? (_smartStore.items
                .where((item) => item.id == _smartId)
                .firstOrNull
                ?.name ??
            'Playlist')
      : _selected?.name ??
            (_playlistId == null ? null : _playlistInfo?.name) ??
            _artist?.name ??
            (_section == _Section.home
                ? (_settingsKey.currentState?.pageTitle ?? 'Home')
                : _section == _Section.search
                ? 'Search'
                : _libraryPage ?? 'Library');

  Widget? _topActions() {
    if (_smartId != null) {
      return PopupMenuButton<String>(
        tooltip: 'Playlist options',
        icon: const Icon(Icons.more_horiz_rounded),
        onSelected: (action) {
          if (action == 'edit') _smartKey.currentState?.edit();
          if (action == 'delete') _smartKey.currentState?.delete();
          if (action == 'icon') {
            choosePlaylistIcon(
              context,
              store: _icons,
              id: 'smart:$_smartId',
              name: _title,
            );
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'edit', child: Text('Edit configuration')),
          PopupMenuItem(value: 'icon', child: Text('Choose icon')),
          PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      );
    }
    if (_playlistId != null) {
      return PopupMenuButton<String>(
        tooltip: 'Playlist options',
        icon: const Icon(Icons.more_horiz_rounded),
        onSelected: (action) {
          if (action == 'icon') {
            choosePlaylistIcon(
              context,
              store: _icons,
              id: 'playlist:$_playlistId',
              name: _title,
            );
          }
          if (action == 'rename') _playlistKey.currentState?.rename();
          if (action == 'add') _playlistKey.currentState?.addSongs();
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'icon', child: Text('Choose icon')),
          if (_playlistInfo?.owner == widget.client.username) ...const [
            PopupMenuItem(value: 'add', child: Text('Add songs')),
            PopupMenuItem(value: 'rename', child: Text('Rename playlist')),
          ],
        ],
      );
    }
    if (_libraryPage == 'Recent Radio') {
      return IconButton(
        tooltip: 'Choose icon for Recent Radio',
        icon: const Icon(Icons.more_horiz_rounded),
        onPressed: () => choosePlaylistIcon(
          context,
          store: _icons,
          id: 'radio',
          name: 'Recent Radio',
        ),
      );
    }
    if (_libraryPage == 'Playlists') {
      return NewPlaylistMenu(
        collections: _collections,
        onNewSmartPlaylist: _newSmart,
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 950;
    final busy = _disconnecting || (widget.accountSession?.busy ?? false);
    final splitDetail =
        wide &&
        MediaQuery.sizeOf(context).width - 80 >= 760 &&
        _hasSelection &&
        _section != _Section.home &&
        !['Recent Radio', 'Playlists'].contains(_libraryPage);
    return PopScope(
      canPop: !_canBack,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: EdgeBackGesture(
        onBack: _canBack && !busy ? _back : null,
        child: StreamBuilder<MediaItem?>(
          stream: widget.playback.mediaItem,
          initialData: widget.playback.mediaItem.value,
          builder: (context, playing) => ArtworkBackdrop(
            client: widget.client,
            coverArt: _selected != null
                ? _selected!.coverArt
                : _playlistId != null
                ? _playlistInfo?.coverArt
                : playing.data?.extras?['coverArtId'] as String?,
            immersive: _selected != null || _playlistId != null,
            child: Scaffold(
              extendBody: true,
              backgroundColor: Colors.transparent,
              body: SafeArea(
                bottom: false,
                child: PageChrome(
                  topInset: _canBack ? 64 : 8,
                  compactTitle: _compactTitle,
                  child: Stack(
                    children: [
                      NotificationListener<ScrollNotification>(
                        onNotification: (notification) {
                          if (notification.metrics.axis != Axis.vertical ||
                              notification.depth != 0) {
                            return false;
                          }
                          if (notification is UserScrollNotification) {
                            _scrollDirection = notification.direction;
                          }
                          final titleOffset =
                              _selected != null || _playlistId != null
                              ? 360
                              : _smartId != null
                              ? 140
                              : 64;
                          final compact =
                              notification.metrics.pixels > titleOffset;
                          final collapse =
                              !wide &&
                              _scrollDirection == ScrollDirection.reverse &&
                              notification.metrics.pixels > 48;
                          final expand =
                              !wide &&
                              (_scrollDirection == ScrollDirection.forward ||
                                  notification.metrics.pixels <= 0);
                          if (_compactTitle != compact ||
                              (collapse && !_dockCollapsed) ||
                              (expand && _dockCollapsed)) {
                            final epoch = _navigationEpoch;
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (!mounted || epoch != _navigationEpoch) return;
                              setState(() {
                                _compactTitle = compact;
                                if (collapse || expand) {
                                  _dockCollapsed = collapse;
                                }
                              });
                            });
                          }
                          return false;
                        },
                        child: AbsorbPointer(
                          absorbing: busy,
                          child: Column(
                            children: [
                              if (busy) const LinearProgressIndicator(),
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
                                            selectedIcon: Icon(
                                              Icons.home_rounded,
                                            ),
                                            label: Text('Home'),
                                          ),
                                          NavigationRailDestination(
                                            icon: Icon(
                                              Icons.library_music_outlined,
                                            ),
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
                                                'Playlists',
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
                                                            padding:
                                                                EdgeInsets.all(
                                                                  32,
                                                                ),
                                                            child: Text(
                                                              'Choose an album or artist to explore.',
                                                              textAlign:
                                                                  TextAlign
                                                                      .center,
                                                            ),
                                                          ),
                                                        ),
                                                ),
                                              ],
                                            );
                                          }
                                          return Stack(
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
                      Positioned(
                        top: 0,
                        left: splitDetail
                            ? MediaQuery.sizeOf(context).width - 370
                            : wide
                            ? 80
                            : 0,
                        right: 0,
                        child: AbsorbPointer(
                          absorbing: busy,
                          child: ListenableBuilder(
                            listenable: _smartStore,
                            builder: (context, _) => FloatingTopBar(
                              title: _compactTitle ? _title : null,
                              leading: _canBack
                                  ? IconButton(
                                      tooltip: _backLabel,
                                      onPressed: _back,
                                      icon: const Icon(
                                        Icons.arrow_back_ios_new_rounded,
                                        size: 20,
                                      ),
                                    )
                                  : null,
                              trailing: _topActions(),
                            ),
                          ),
                        ),
                      ),
                    ],
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
                        _disconnecting ||
                        (widget.accountSession?.busy ?? false),
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
                                    onPressed: () =>
                                        _tab(_Section.search.index),
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
                              child: FloatingNavigation(
                                selectedIndex: _section.index,
                                onSelected: _disconnecting ? null : _tab,
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
      ),
    );
  }
}
