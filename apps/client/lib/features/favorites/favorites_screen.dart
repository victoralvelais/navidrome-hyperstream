import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import '../../widgets/pull_to_refresh.dart';

import '../../models/library.dart';
import '../../services/library_collections.dart';
import '../../services/playback_service.dart';
import '../library/collection_actions.dart';
import '../library/cover_art.dart';

class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({
    super.key,
    required this.collections,
    required this.playback,
    required this.onAlbumSelected,
  });
  final LibraryCollections collections;
  final PlaybackService playback;
  final ValueChanged<Album> onAlbumSelected;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: collections,
    builder: (context, _) {
      final albums = collections.favoriteAlbums;
      final songs = collections.favoriteSongs;
      return StreamBuilder<MediaItem?>(
        stream: playback.mediaItem,
        initialData: playback.mediaItem.value,
        builder: (context, playing) => PullToRefresh(
          onRefresh: collections.refreshFavorites,
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
                              'Favorites',
                              style: Theme.of(context).textTheme.headlineLarge,
                            ),
                          ),
                        ],
                      ),
                      const Text('The music you keep coming back to.'),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: songs.isEmpty
                            ? null
                            : () => playback.playAlbum(
                                collections.client,
                                songs,
                                0,
                              ),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('Play favorite songs'),
                      ),
                      if (collections.favoritesLoading)
                        const LinearProgressIndicator(),
                      if (collections.favoritesError case final String error)
                        Text(error),
                      if (!collections.favoritesLoading &&
                          collections.favoritesError == null &&
                          albums.isEmpty &&
                          songs.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 24),
                          child: Text(
                            'No favorites yet. Use the heart on an album or the song menu to add one.',
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (albums.isNotEmpty)
                SliverToBoxAdapter(child: _heading(context, 'Albums')),
              SliverList.builder(
                itemCount: albums.length,
                itemBuilder: (context, index) {
                  final album = albums[index];
                  return ListTile(
                    leading: SizedBox(
                      width: 48,
                      height: 48,
                      child: CoverArt(
                        client: collections.client,
                        id: album.coverArt,
                      ),
                    ),
                    title: Text(
                      album.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      album.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: FavoriteButton(
                      collections: collections,
                      album: album,
                    ),
                    onTap: () => onAlbumSelected(album),
                  );
                },
              ),
              if (songs.isNotEmpty)
                SliverToBoxAdapter(child: _heading(context, 'Songs')),
              SliverList.builder(
                itemCount: songs.length,
                itemBuilder: (context, index) {
                  final song = songs[index];
                  return ListTile(
                    selected: playing.data?.id == song.id,
                    leading: SizedBox(
                      width: 48,
                      height: 48,
                      child: CoverArt(
                        client: collections.client,
                        id: song.coverArt,
                      ),
                    ),
                    title: Text(
                      song.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${song.artist} · ${song.album}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: SongActions(collections: collections, song: song),
                    onTap: () =>
                        playback.playAlbum(collections.client, songs, index),
                  );
                },
              ),
              const SliverToBoxAdapter(child: DockSpacer()),
            ],
          ),
        ),
      );
    },
  );

  Widget _heading(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
    child: Text(text, style: Theme.of(context).textTheme.titleLarge),
  );
}
