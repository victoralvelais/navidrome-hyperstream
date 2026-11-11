import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import '../../models/library.dart';
import '../../services/library_collections.dart';
import '../../services/navidrome_client.dart';
import '../../services/playback_service.dart';
import 'cover_art.dart';
import 'collection_actions.dart';

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
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 16),
          itemCount: tracks.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Column(
                  children: [
                    SizedBox(
                      width: 240,
                      child: CoverArt(
                        client: widget.client,
                        id: widget.album.coverArt,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      widget.album.name,
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    Text(
                      widget.album.artist,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${tracks.length} songs',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: tracks.isEmpty
                          ? null
                          : () => widget.onPlay(tracks, 0),
                      icon: const Icon(Icons.play_arrow),
                      label: Text(
                        tracks.isEmpty
                            ? 'No tracks in this album'
                            : 'Play album',
                      ),
                    ),
                    if (widget.collections != null)
                      FavoriteButton(
                        collections: widget.collections!,
                        album: widget.album,
                      ),
                  ],
                ),
              );
            }
            final track = tracks[index - 1];
            final seconds = track.duration.inSeconds;
            return ListTile(
              selected: playing.data?.id == track.id,
              selectedTileColor: Theme.of(context).colorScheme.primary
                  .withValues(alpha: .08),
              leading: SizedBox(
                width: 28,
                child: Text('${track.number ?? index}'),
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
                    SongActions(collections: widget.collections!, song: track),
                ],
              ),
              onTap: () => widget.onPlay(tracks, index - 1),
            );
          },
        );
      },
    ),
  );
}
