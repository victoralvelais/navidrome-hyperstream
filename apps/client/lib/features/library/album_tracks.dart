import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import '../../widgets/floating_chrome.dart';
import '../../widgets/pull_to_refresh.dart';

import '../../models/library.dart';
import '../../services/library_collections.dart';
import '../../services/navidrome_client.dart';
import '../../services/playback_service.dart';
import 'cover_art.dart';
import 'collection_actions.dart';
import 'artwork_backdrop.dart';
import '../../widgets/collection_play_controls.dart';

class AlbumTracks extends StatefulWidget {
  const AlbumTracks({
    super.key,
    required this.client,
    required this.album,
    required this.onPlay,
    required this.playback,
    this.collections,
  });
  final NavidromeClient client;
  final Album album;
  final void Function(List<Track>, int) onPlay;
  final PlaybackService playback;
  final LibraryCollections? collections;

  @override
  State<AlbumTracks> createState() => _AlbumTracksState();
}

class _AlbumTracksState extends State<AlbumTracks> {
  late Future<List<Track>> _tracks;

  @override
  void initState() {
    super.initState();
    _tracks = widget.client.tracks(widget.album.id);
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<MediaItem?>(
    stream: widget.playback.mediaItem,
    initialData: widget.playback.mediaItem.value,
    builder: (context, playing) => FutureBuilder<List<Track>>(
      future: _tracks,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    snapshot.error is NavidromeException
                        ? (snapshot.error! as NavidromeException).message
                        : 'Could not load this album.',
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: () => setState(
                      () => _tracks = widget.client.tracks(widget.album.id),
                    ),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }
        final tracks = snapshot.data!;
        return ArtworkBackdrop(
          client: widget.client,
          coverArt: widget.album.coverArt,
          child: PullToRefresh(
            onRefresh: () async {
              final future = widget.client.tracks(widget.album.id);
              setState(() => _tracks = future);
              try {
                await future;
              } on Object {
                /* Rendered by FutureBuilder. */
              }
            },
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.only(
                top: PageChrome.insetOf(context) + 16,
                bottom: MediaQuery.paddingOf(context).bottom + 24,
              ),
              itemCount: tracks.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    child: Column(
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 280),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(22),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: .2),
                                  blurRadius: 28,
                                  offset: const Offset(0, 14),
                                ),
                              ],
                            ),
                            child: CoverArt(
                              client: widget.client,
                              id: widget.album.coverArt,
                              radius: 22,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          widget.album.name,
                          style: Theme.of(context).textTheme.headlineSmall,
                          textAlign: TextAlign.center,
                        ),
                        Text(
                          widget.album.artist,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${tracks.length} songs',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 16),
                        CollectionPlayControls(
                          onPlay: tracks.isEmpty
                              ? null
                              : () => widget.onPlay(tracks, 0),
                          onShuffle: tracks.isEmpty
                              ? null
                              : () => widget.playback.playAlbum(
                                  widget.client,
                                  tracks,
                                  0,
                                  coverArtId: widget.album.coverArt,
                                  shuffle: true,
                                ),
                          trailing: widget.collections == null
                              ? null
                              : FavoriteButton(
                                  collections: widget.collections!,
                                  album: widget.album,
                                ),
                        ),
                      ],
                    ),
                  );
                }
                final track = tracks[index - 1];
                final seconds = track.duration.inSeconds;
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 4,
                  ),
                  selected: playing.data?.id == track.id,
                  selectedTileColor: Theme.of(context).colorScheme.primary
                      .withValues(alpha: .08),
                  leading: SizedBox(
                    width: 28,
                    child: playing.data?.id == track.id
                        ? const Icon(Icons.graphic_eq_rounded, size: 20)
                        : Text('${track.number ?? index}'),
                  ),
                  title: Text(
                    track.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}',
                      ),
                      if (widget.collections != null)
                        SongActions(
                          collections: widget.collections!,
                          song: track,
                        ),
                    ],
                  ),
                  onTap: () => widget.onPlay(tracks, index - 1),
                );
              },
            ),
          ),
        );
      },
    ),
  );
}
