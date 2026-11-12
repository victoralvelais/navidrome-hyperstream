import '../../widgets/glass_overlays.dart';

import 'package:flutter/material.dart';

import '../../models/library.dart';
import '../../services/library_collections.dart';
import '../../services/navidrome_client.dart';

Future<bool?> editPlaylistName(
  BuildContext context, {
  String? initialName,
  required Future<void> Function(String) onSave,
}) => showDialog<bool>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _PlaylistNameDialog(initialName: initialName, onSave: onSave),
);

class _PlaylistNameDialog extends StatefulWidget {
  const _PlaylistNameDialog({this.initialName, required this.onSave});
  final String? initialName;
  final Future<void> Function(String) onSave;
  @override
  State<_PlaylistNameDialog> createState() => _PlaylistNameDialogState();
}

class _PlaylistNameDialogState extends State<_PlaylistNameDialog> {
  late final _name = TextEditingController(text: widget.initialName);
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    if (_saving) return;
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Enter a playlist name.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(_name.text.trim());
      if (mounted) Navigator.pop(context, true);
    } on NavidromeException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: GlassAlertDialog(
      scrollable: true,
      title: Text(
        widget.initialName == null ? 'New playlist' : 'Rename playlist',
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            enabled: !_saving,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Playlist name'),
            onSubmitted: (_) => _save(),
          ),
          if (_saving) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(_error!),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

Future<void> addSongToPlaylist(
  BuildContext context,
  LibraryCollections collections,
  Track song,
) => addTracksToPlaylist(context, collections, [song.id]);

Future<void> addTracksToPlaylist(
  BuildContext context,
  LibraryCollections collections,
  List<String> songIds,
) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _PlaylistPicker(
    collections: collections,
    songIds: List.unmodifiable(songIds),
  ),
);

class _PlaylistPicker extends StatefulWidget {
  const _PlaylistPicker({required this.collections, required this.songIds});
  final LibraryCollections collections;
  final List<String> songIds;
  @override
  State<_PlaylistPicker> createState() => _PlaylistPickerState();
}

class _PlaylistPickerState extends State<_PlaylistPicker> {
  bool _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.collections.refreshPlaylists();
    });
  }

  Future<void> _add(MusicPlaylist playlist) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (widget.songIds.length == 1) {
        await widget.collections.addToPlaylist(
          playlist.id,
          widget.songIds.single,
        );
      } else {
        await widget.collections.addSongsToPlaylist(
          playlist.id,
          widget.songIds,
        );
      }
      if (mounted) Navigator.pop(context);
    } on NavidromeException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: GlassAlertDialog(
      title: const Text('Add to playlist'),
      content: SizedBox(
        width: 400,
        height: 320,
        child: ListenableBuilder(
          listenable: widget.collections,
          builder: (context, _) {
            final store = widget.collections;
            final owned = (store.playlists ?? [])
                .where((p) => p.owner == store.client.username)
                .toList();
            return Column(
              children: [
                if (_saving || store.playlistsLoading)
                  const LinearProgressIndicator(),
                if (_error ?? store.playlistsError case final String error) ...[
                  Text(error),
                  TextButton(
                    onPressed: _saving ? null : store.refreshPlaylists,
                    child: const Text('Reload playlists'),
                  ),
                ],
                Expanded(
                  child: ListView(
                    children: [
                      for (final playlist in owned)
                        ListTile(
                          leading: const Icon(Icons.queue_music_rounded),
                          title: Text(playlist.name),
                          subtitle: Text('${playlist.songCount} songs'),
                          enabled: !_saving,
                          onTap: () => _add(playlist),
                        ),
                      if (!store.playlistsLoading &&
                          store.playlistsError == null &&
                          owned.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('Create a playlist to save this song.'),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _saving
              ? null
              : () async {
                  final saved = await editPlaylistName(
                    context,
                    onSave: (name) async {
                      await widget.collections.createPlaylist(
                        name,
                        songIds: widget.songIds,
                      );
                    },
                  );
                  if (context.mounted && saved == true) Navigator.pop(context);
                },
          child: const Text('New playlist'),
        ),
      ],
    ),
  );
}
