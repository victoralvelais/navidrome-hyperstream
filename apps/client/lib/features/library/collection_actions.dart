import 'package:flutter/material.dart';

import '../../models/library.dart';
import '../../services/library_collections.dart';
import '../../services/navidrome_client.dart';
import '../playlists/playlist_dialogs.dart';

Future<void> collectionAction(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
  } on NavidromeException catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }
}

class FavoriteButton extends StatelessWidget {
  const FavoriteButton({
    super.key,
    required this.collections,
    this.album,
    this.song,
  }) : assert((album == null) != (song == null));
  final LibraryCollections collections;
  final Album? album;
  final Track? song;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: collections,
    builder: (context, _) {
      final id = album?.id ?? song!.id;
      final selected = collections.isFavorite(
        id,
        album: album != null,
        fallback: album?.starred ?? song!.starred,
      );
      return IconButton(
        tooltip: selected ? 'Remove from favorites' : 'Add to favorites',
        isSelected: selected,
        color: selected ? Theme.of(context).colorScheme.primary : null,
        icon: Icon(
          selected ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        ),
        onPressed: collections.favoritePending(id, album: album != null)
            ? null
            : () => collectionAction(
                context,
                () => album != null
                    ? collections.toggleAlbum(album!)
                    : collections.toggleSong(song!),
              ),
      );
    },
  );
}

enum _SongAction { favorite, playlist, remove }

class SongActions extends StatelessWidget {
  const SongActions({
    super.key,
    required this.collections,
    required this.song,
    this.onRemove,
    this.enabled = true,
  });
  final LibraryCollections collections;
  final Track song;
  final Future<void> Function()? onRemove;
  final bool enabled;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: collections,
    builder: (context, _) {
      final favorite = collections.isFavorite(
        song.id,
        album: false,
        fallback: song.starred,
      );
      return PopupMenuButton<_SongAction>(
        tooltip: 'Song actions for ${song.title}',
        enabled: enabled,
        icon: const Icon(Icons.more_horiz_rounded),
        itemBuilder: (_) => [
          PopupMenuItem(
            value: _SongAction.favorite,
            enabled: !collections.favoritePending(song.id, album: false),
            child: Text(
              favorite ? 'Remove from favorites' : 'Add to favorites',
            ),
          ),
          const PopupMenuItem(
            value: _SongAction.playlist,
            child: Text('Add to playlist'),
          ),
          if (onRemove != null)
            const PopupMenuItem(
              value: _SongAction.remove,
              child: Text('Remove from playlist'),
            ),
        ],
        onSelected: (action) async {
          switch (action) {
            case _SongAction.favorite:
              await collectionAction(
                context,
                () => collections.toggleSong(song),
              );
            case _SongAction.playlist:
              await addSongToPlaylist(context, collections, song);
            case _SongAction.remove:
              await collectionAction(context, onRemove!);
          }
        },
      );
    },
  );
}
