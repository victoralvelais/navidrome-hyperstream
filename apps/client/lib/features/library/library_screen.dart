import 'package:flutter/material.dart';

import '../../models/library.dart';
import '../../services/navidrome_client.dart';
import '../../services/playback_service.dart';
import '../player/player_controls.dart';
import '../settings/settings_sheet.dart';
import 'album_tracks.dart';
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
  final List<Album> _albums = [];
  Album? _selected;
  bool _busy = false;
  bool _more = true;
  bool _disconnecting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
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

  Future<void> _disconnect() async {
    setState(() => _disconnecting = true);
    await widget.onDisconnect();
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
                  onTap: () => setState(() => _selected = album),
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

  Widget _trackPane() => AlbumTracks(
    key: ValueKey(_selected!.id),
    client: widget.client,
    album: _selected!,
    playback: widget.playback,
    onPlay: (tracks, index) => widget.playback.playAlbum(
      widget.client,
      tracks,
      index,
      coverArtId: _selected!.coverArt,
    ),
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _selected == null,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) setState(() => _selected = null);
    },
    child: Scaffold(
      appBar: AppBar(
        leading: _selected == null
            ? null
            : IconButton(
                tooltip: 'Back to albums',
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _selected = null),
              ),
        title: const Text('Hyperstream'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.tune_rounded),
            onPressed: _disconnecting
                ? null
                : () => showSettings(context, widget.playback),
          ),
          IconButton(
            tooltip: 'Refresh albums',
            icon: const Icon(Icons.refresh),
            onPressed: _busy || _disconnecting
                ? null
                : () => _load(refresh: true),
          ),
          IconButton(
            tooltip: 'Disconnect',
            icon: const Icon(Icons.logout),
            onPressed: _disconnecting ? null : _disconnect,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
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
                          Expanded(child: _albumGrid()),
                          const VerticalDivider(width: 1),
                          SizedBox(
                            width: 370,
                            child: Material(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainer,
                              child: _selected == null
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
                                              'Choose an album',
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
                    return _selected == null ? _albumGrid() : _trackPane();
                  },
                ),
              ),
              PlayerControls(playback: widget.playback, client: widget.client),
            ],
          ),
        ),
      ),
    ),
  );
}
