import 'package:flutter/material.dart';

import '../../widgets/floating_chrome.dart';
import '../../widgets/pull_to_refresh.dart';

import '../../models/library.dart';
import '../../services/library_collections.dart';
import '../../services/navidrome_client.dart';
import '../../services/playback_service.dart';
import 'collection_actions.dart';
import 'cover_art.dart';

class AlbumGrid extends StatelessWidget {
  const AlbumGrid({
    super.key,
    required this.albums,
    required this.client,
    required this.onSelected,
  });
  final List<Album> albums;
  final NavidromeClient client;
  final ValueChanged<Album> onSelected;
  @override
  Widget build(BuildContext context) => SliverPadding(
    padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
    sliver: SliverLayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.crossAxisExtent / 190).floor().clamp(2, 6);
        final size =
            (constraints.crossAxisExtent - 16 * (columns - 1)) / columns;
        return SliverGrid.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisExtent:
                size + 58 * MediaQuery.textScalerOf(context).scale(1),
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
          itemCount: albums.length,
          itemBuilder: (context, index) => AlbumCard(
            album: albums[index],
            client: client,
            onTap: () => onSelected(albums[index]),
          ),
        );
      },
    ),
  );
}

class AlbumCard extends StatelessWidget {
  const AlbumCard({
    super.key,
    required this.album,
    required this.client,
    required this.onTap,
  });
  final Album album;
  final NavidromeClient client;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(16),
    onTap: onTap,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CoverArt(client: client, id: album.coverArt, radius: 14),
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
}

class ArtistRow extends StatelessWidget {
  const ArtistRow({
    super.key,
    required this.artist,
    required this.client,
    required this.onTap,
  });
  final Artist artist;
  final NavidromeClient client;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
    leading: SizedBox(
      width: 56,
      height: 56,
      child: CoverArt(client: client, id: artist.coverArt, radius: 28),
    ),
    title: Text(artist.name, maxLines: 2, overflow: TextOverflow.ellipsis),
    subtitle: Text('${artist.albumCount} albums'),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: onTap,
  );
}

/// Lazy, independently paged full-library categories. Empty query is the
/// OpenSubsonic browse-all contract; it isn't used for an empty search field.
class CatalogPage extends StatefulWidget {
  const CatalogPage({
    super.key,
    required this.kind,
    required this.client,
    required this.playback,
    required this.collections,
    required this.onAlbum,
    required this.onArtist,
    this.artist,
  });
  final String kind;
  final NavidromeClient client;
  final PlaybackService playback;
  final LibraryCollections collections;
  final ValueChanged<Album> onAlbum;
  final ValueChanged<Artist> onArtist;
  final Artist? artist;
  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> {
  final _artists = <Artist>[];
  final _albums = <Album>[];
  final _songs = <Track>[];
  bool _busy = false;
  bool _more = true;
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
      if (widget.artist case final Artist artist) {
        final albums = await widget.client.artistAlbums(artist.id);
        if (!mounted) return;
        setState(() {
          if (refresh) _albums.clear();
          _albums.addAll(albums);
          _more = false;
        });
      } else {
        final result = await widget.client.search(
          '',
          browse: true,
          albumCount: widget.kind == 'Albums' ? 40 : 0,
          albumOffset: refresh ? 0 : _albums.length,
          artistCount: widget.kind == 'Artists' ? 40 : 0,
          artistOffset: refresh ? 0 : _artists.length,
          songCount: widget.kind == 'Songs' ? 40 : 0,
          songOffset: refresh ? 0 : _songs.length,
        );
        if (!mounted) return;
        setState(() {
          if (refresh) {
            _albums.clear();
            _artists.clear();
            _songs.clear();
          }
          _albums.addAll(result.albums);
          _artists.addAll(result.artists);
          _songs.addAll(result.tracks);
          _more =
              result.albums.length == 40 ||
              result.artists.length == 40 ||
              result.tracks.length == 40;
        });
      }
    } on NavidromeException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PullToRefresh(
    onRefresh: () => _load(refresh: true),
    child: CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              24,
              PageChrome.insetOf(context) + 12,
              24,
              16,
            ),
            child: Text(
              widget.artist?.name ?? widget.kind,
              style: Theme.of(context).textTheme.headlineLarge,
            ),
          ),
        ),
        if (_albums.isNotEmpty)
          AlbumGrid(
            albums: _albums,
            client: widget.client,
            onSelected: widget.onAlbum,
          ),
        SliverList.builder(
          itemCount: _artists.length,
          itemBuilder: (_, i) => ArtistRow(
            artist: _artists[i],
            client: widget.client,
            onTap: () => widget.onArtist(_artists[i]),
          ),
        ),
        SliverList.builder(
          itemCount: _songs.length,
          itemBuilder: (_, i) {
            final song = _songs[i];
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 4,
              ),
              leading: SizedBox(
                width: 48,
                height: 48,
                child: CoverArt(client: widget.client, id: song.coverArt),
              ),
              title: Text(
                song.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(song.artist, maxLines: 1),
              trailing: SongActions(
                collections: widget.collections,
                song: song,
              ),
              onTap: () =>
                  widget.playback.playAlbum(widget.client, List.of(_songs), i),
            );
          },
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
                        TextButton(
                          onPressed: _load,
                          child: const Text('Retry'),
                        ),
                      ],
                    )
                  : _more
                  ? TextButton(
                      onPressed: _load,
                      child: Text('More ${widget.kind.toLowerCase()}'),
                    )
                  : _albums.isEmpty && _artists.isEmpty && _songs.isEmpty
                  ? const Text('Nothing here yet.')
                  : const SizedBox.shrink(),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: DockSpacer()),
      ],
    ),
  );
}
