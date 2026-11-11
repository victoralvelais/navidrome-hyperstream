import 'package:flutter/material.dart';

import '../../models/library.dart';
import '../../services/library_collections.dart';
import '../library/cover_art.dart';
import 'playlist_dialogs.dart';

class PlaylistsScreen extends StatelessWidget {
  const PlaylistsScreen({
    super.key,
    required this.collections,
    required this.onSelected,
  });
  final LibraryCollections collections;
  final ValueChanged<MusicPlaylist> onSelected;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: collections,
    builder: (context, _) {
      final playlists = collections.playlists ?? [];
      return CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Playlists',
                          style: Theme.of(context).textTheme.headlineLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Refresh playlists',
                        onPressed: collections.playlistsLoading
                            ? null
                            : collections.refreshPlaylists,
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('New playlist'),
                    onPressed: () => editPlaylistName(
                      context,
                      onSave: (name) async {
                        await collections.createPlaylist(name);
                      },
                    ),
                  ),
                  if (collections.playlistsLoading)
                    const LinearProgressIndicator(),
                  if (collections.playlistsError case final String error)
                    Text(error),
                  if (!collections.playlistsLoading &&
                      collections.playlistsError == null &&
                      playlists.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 24),
                      child: Text(
                        'Your playlists will appear here. Create one to get started.',
                      ),
                    ),
                ],
              ),
            ),
          ),
          SliverList.builder(
            itemCount: playlists.length,
            itemBuilder: (context, index) {
              final playlist = playlists[index];
              return ListTile(
                leading: SizedBox(
                  width: 56,
                  height: 56,
                  child: CoverArt(
                    client: collections.client,
                    id: playlist.coverArt,
                  ),
                ),
                title: Text(
                  playlist.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${playlist.songCount} songs${playlist.owner.isEmpty ? '' : ' · ${playlist.owner}'}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => onSelected(playlist),
              );
            },
          ),
        ],
      );
    },
  );
}
