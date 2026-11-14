import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/library.dart';
import '../../services/library_collections.dart';
import '../../services/navidrome_client.dart';
import '../../services/playback_service.dart';
import '../../services/remote_folder.dart';
import '../../widgets/glass_overlays.dart';
import '../library/collection_actions.dart';
import '../playlists/playlist_dialogs.dart';
import 'audio_share_dialog.dart';
import 'remote_send_dialog.dart';

class NowPlayingTrackActions extends StatefulWidget {
  const NowPlayingTrackActions({
    super.key,
    required this.song,
    required this.playback,
    required this.collections,
    this.onAlbum,
    this.onArtist,
  });
  final Track song;
  final PlaybackService playback;
  final LibraryCollections collections;
  final ValueChanged<Album>? onAlbum;
  final ValueChanged<Artist>? onArtist;
  @override
  State<NowPlayingTrackActions> createState() => _NowPlayingTrackActionsState();
}

class _NowPlayingTrackActionsState extends State<NowPlayingTrackActions> {
  bool _busy = false;
  String? _action;
  Future<void> _select(String action) async {
    if (_busy) return;
    final song = widget.song;
    final collections = widget.collections;
    setState(() {
      _busy = true;
      _action = action;
    });
    await collectionAction(context, () async {
      switch (action) {
        case 'remote':
          await sendSongToRemote(context, collections.client, song);
        case 'mix':
          final tracks = await collections.client.instantMix(song.id);
          if (mounted) {
            await widget.playback.playAlbum(collections.client, [
              song,
              ...tracks,
            ], 0);
          }
        case 'album':
        case 'artist':
          final track =
              (action == 'album' ? song.albumId : song.artistId) == null
              ? await collections.client.song(song.id)
              : song;
          if (!mounted) return;
          if (action == 'album') {
            if (track.albumId == null) {
              throw const NavidromeException(
                'This server did not provide an album link.',
              );
            }
            widget.onAlbum?.call(
              Album(
                id: track.albumId!,
                name: track.album,
                artist: track.artist,
                coverArt: track.coverArt,
              ),
            );
          } else {
            if (track.artistId == null) {
              throw const NavidromeException(
                'This server did not provide an artist link.',
              );
            }
            widget.onArtist?.call(
              Artist(id: track.artistId!, name: track.artist),
            );
          }
        case 'favorite':
          await collections.toggleSong(song);
        case 'rating':
          final rating = await showGlassSheet<int>(
            context: context,
            builder: (context) => SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Rating',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  for (var rating = 5; rating >= 0; rating--)
                    ListTile(
                      title: Text(
                        rating == 0
                            ? 'No rating'
                            : '$rating ${rating == 1 ? 'star' : 'stars'}',
                      ),
                      leading: Icon(
                        rating == 0
                            ? Icons.star_border_rounded
                            : Icons.star_rounded,
                      ),
                      trailing: collections.rating(song) == rating
                          ? const Icon(Icons.check_rounded)
                          : null,
                      onTap: () => Navigator.pop(context, rating),
                    ),
                ],
              ),
            ),
          );
          if (rating != null) await collections.rate(song, rating);
        case 'playlist':
          await addSongToPlaylist(context, collections, song);
        case 'share':
          final text = '${song.title} — ${song.artist}\n${song.album}';
          try {
            if (defaultTargetPlatform == TargetPlatform.iOS) {
              await shareAudioFile(context, collections.client, song);
            } else {
              await Clipboard.setData(ClipboardData(text: text));
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Song details copied.')),
                );
              }
            }
          } on NavidromeException {
            rethrow;
          } on Object {
            throw const NavidromeException(
              'Could not share this song. Try again.',
            );
          }
      }
    });
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.collections, RemoteFolders.instance]),
    builder: (context, _) {
      final song = widget.song;
      final store = widget.collections;
      final favorite = store.isFavorite(
        song.id,
        album: false,
        fallback: song.starred,
      );
      return GlassPopupMenuButton<String>(
        tooltip: 'Song actions for ${song.title}',
        enabled: !_busy,
        icon:
            _busy &&
                !['rating', 'playlist', 'share', 'remote'].contains(_action)
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.more_horiz_rounded),
        onSelected: _select,
        itemBuilder: (_) => [
          menuAction('mix', 'Instant Mix', Icons.auto_awesome_rounded),
          menuAction(
            'album',
            'Show album',
            Icons.album_outlined,
            enabled: widget.onAlbum != null,
          ),
          menuAction(
            'artist',
            'Show artist',
            Icons.person_outline_rounded,
            enabled: widget.onArtist != null,
          ),
          const PopupMenuDivider(),
          menuAction(
            'favorite',
            favorite ? 'Remove from favorites' : 'Add to favorites',
            favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            enabled: !store.favoritePending(song.id, album: false),
          ),
          menuAction(
            'rating',
            'Rating · ${store.rating(song)}/5',
            Icons.star_outline_rounded,
            enabled: !store.ratingPending(song),
          ),
          menuAction('playlist', 'Add to playlist', Icons.playlist_add_rounded),
          if (RemoteFolders.instance.destination != null)
            menuAction(
              'remote',
              'Send to remote folder',
              Icons.drive_folder_upload_outlined,
              enabled: !RemoteFolders.instance.busy,
            ),
          menuAction(
            'share',
            defaultTargetPlatform == TargetPlatform.iOS
                ? 'Share audio file'
                : 'Share · copy details',
            Icons.ios_share_rounded,
          ),
        ],
      );
    },
  );
}

PopupMenuItem<String> menuAction(
  String value,
  String label,
  IconData icon, {
  bool enabled = true,
}) => PopupMenuItem(
  value: value,
  enabled: enabled,
  child: Row(
    children: [
      Icon(icon, size: 22),
      const SizedBox(width: 14),
      Expanded(child: Text(label)),
    ],
  ),
);

Future<void> showSleepTimer(BuildContext context, PlaybackService playback) =>
    showGlassSheet<void>(
      context: context,
      builder: (context) => SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Sleep timer',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            for (final minutes in [15, 30, 45, 60, 90])
              ListTile(
                leading: const Icon(Icons.bedtime_outlined),
                title: Text('$minutes minutes'),
                onTap: () {
                  playback.setSleepTimer(duration: Duration(minutes: minutes));
                  Navigator.pop(context);
                },
              ),
            ListTile(
              leading: const Icon(Icons.music_note_rounded),
              title: const Text('End of current track'),
              onTap: () {
                playback.setSleepTimer(endOfTrack: true);
                Navigator.pop(context);
              },
            ),
            if (playback.sleepTimer.value != null)
              ListTile(
                leading: const Icon(Icons.timer_off_outlined),
                title: const Text('Cancel sleep timer'),
                onTap: () {
                  playback.cancelSleepTimer();
                  Navigator.pop(context);
                },
              ),
          ],
        ),
      ),
    );
