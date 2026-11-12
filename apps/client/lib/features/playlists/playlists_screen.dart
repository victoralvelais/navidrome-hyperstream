import 'package:flutter/material.dart';

import '../../widgets/pull_to_refresh.dart';

import '../../models/library.dart';
import '../../services/library_collections.dart';
import '../library/cover_art.dart';
import 'playlist_dialogs.dart';

class PlaylistsScreen extends StatelessWidget {
  const PlaylistsScreen({
    super.key,
    required this.collections,
    required this.onSelected,
    this.onRecentRadio,
    this.onSmartPlaylists,
    this.onNewSmartPlaylist,
  });
  final LibraryCollections collections;
  final ValueChanged<MusicPlaylist> onSelected;
  final VoidCallback? onRecentRadio;
  final VoidCallback? onSmartPlaylists;
  final VoidCallback? onNewSmartPlaylist;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: collections,
    builder: (context, _) {
      final playlists = collections.playlists ?? [];
      return PullToRefresh(
        onRefresh: collections.refreshPlaylists,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
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
                        PopupMenuButton<String>(
                          tooltip: 'New playlist',
                          onSelected: (action) {
                            if (action == 'smart') {
                              onNewSmartPlaylist?.call();
                              return;
                            }
                            if (action == 'radio') {
                              onRecentRadio?.call();
                              return;
                            }
                            editPlaylistName(
                              context,
                              onSave: (name) async {
                                await collections.createPlaylist(name);
                              },
                            );
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'manual',
                              child: Text('New playlist'),
                            ),
                            if (onNewSmartPlaylist != null)
                              const PopupMenuItem(
                                value: 'smart',
                                child: Text('New smart playlist'),
                              ),
                            if (onRecentRadio != null)
                              const PopupMenuItem(
                                value: 'radio',
                                child: Text('Recent Radio'),
                              ),
                          ],
                          icon: const Icon(Icons.add_rounded),
                        ),
                      ],
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
            if (onRecentRadio != null)
              SliverToBoxAdapter(
                child: ListTile(
                  leading: const SizedBox(
                    width: 56,
                    height: 56,
                    child: Icon(Icons.radio_rounded),
                  ),
                  title: const Text('Recent Radio'),
                  subtitle: const Text(
                    'Recently added and played · Auto-updating preview',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: onRecentRadio,
                ),
              ),
            if (onSmartPlaylists != null)
              SliverToBoxAdapter(
                child: ListTile(
                  leading: const SizedBox(
                    width: 56,
                    height: 56,
                    child: Icon(Icons.auto_awesome_outlined),
                  ),
                  title: const Text('Smart playlists'),
                  subtitle: const Text('Rules and custom mixes'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: onSmartPlaylists,
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
            const SliverToBoxAdapter(child: DockSpacer()),
          ],
        ),
      );
    },
  );
}
