import 'package:flutter/material.dart';

import '../../models/library.dart';
import '../../services/navidrome_client.dart';
import 'cover_art.dart';

class AlbumTracks extends StatefulWidget {
  const AlbumTracks({
    super.key,
    required this.client,
    required this.album,
    required this.onPlay,
  });
  final NavidromeClient client;
  final Album album;
  final void Function(List<Track>, int) onPlay;

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
  Widget build(BuildContext context) => FutureBuilder<List<Track>>(
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
                    width: 200,
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
                  Text(widget.album.artist, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: tracks.isEmpty
                        ? null
                        : () => widget.onPlay(tracks, 0),
                    icon: const Icon(Icons.play_arrow),
                    label: Text(
                      tracks.isEmpty ? 'No tracks in this album' : 'Play album',
                    ),
                  ),
                ],
              ),
            );
          }
          final track = tracks[index - 1];
          final seconds = track.duration.inSeconds;
          return ListTile(
            leading: SizedBox(
              width: 28,
              child: Text('${track.number ?? index}'),
            ),
            title: Text(track.title),
            subtitle: Text(track.artist),
            trailing: Text(
              '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}',
            ),
            onTap: () => widget.onPlay(tracks, index - 1),
          );
        },
      );
    },
  );
}
