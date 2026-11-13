import 'package:flutter/material.dart';

import '../../models/library.dart';
import '../../models/smart_playlist.dart';
import '../../services/library_catalog.dart';
import '../../services/navidrome_client.dart';
import '../../services/smart_playlist_publisher.dart';
import '../../widgets/glass_overlays.dart';

class PlaylistPublishDialog extends StatefulWidget {
  const PlaylistPublishDialog({
    super.key,
    required this.publisher,
    required this.definition,
    required this.result,
    required this.catalog,
  });
  final SmartPlaylistPublisher publisher;
  final SmartPlaylistDefinition definition;
  final SmartPlaylistResult result;
  final LibraryCatalog catalog;
  @override
  State<PlaylistPublishDialog> createState() => _PlaylistPublishDialogState();
}

class _PlaylistPublishDialogState extends State<PlaylistPublishDialog> {
  late final _name = TextEditingController(text: widget.definition.name);
  bool _busy = true;
  String? _error;
  MusicPlaylist? _conflict;
  List<MusicPlaylist>? _copies;
  PublishedPlaylist? get _link => widget.publisher.link(widget.definition.id);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await widget.publisher.load();
    } on Object catch (error) {
      _error = _message(error);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String _message(Object error) => switch (error) {
    PlaylistPublishException() => error.message,
    NavidromeException() => error.message,
    _ =>
      'The server copy could not be verified. Check your connection and retry.',
  };

  Future<void> _run(Future<MusicPlaylist> Function() operation) async {
    setState(() {
      _busy = true;
      _error = null;
      _conflict = null;
    });
    try {
      final result = await operation();
      if (!mounted) return;
      setState(() => _busy = false);
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.pop(context, result);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _message(error);
          if (error is PlaylistPublishConflict) _conflict = error.remote;
        });
      }
    }
  }

  void _publish({bool separate = false, MusicPlaylist? reviewed}) => _run(
    () => widget.publisher.publish(
      definitionId: widget.definition.id,
      name: _name.text,
      result: widget.result,
      catalog: widget.catalog,
      separateCopy: separate,
      reviewed: reviewed,
    ),
  );

  Future<void> _separate() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => GlassAlertDialog(
        title: const Text('Create a separate copy?'),
        content: Text(
          'Create “${_name.text.trim()}” with ${widget.result.matches.length} songs? Existing server playlists stay as they are. If an earlier request succeeded, this creates an additional copy.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Create separate copy'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) _publish(separate: true);
  }

  Future<void> _findCopies() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final copies = await widget.publisher.client.playlists();
      if (mounted) {
        setState(
          () => _copies = copies
              .where(
                (p) =>
                    p.owner == widget.publisher.client.username && !p.readOnly,
              )
              .toList(),
        );
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: GlassAlertDialog(
      title: const Text('Publish to Navidrome'),
      content: SizedBox(
        width: 510,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .5,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${widget.result.matches.length} songs in the preview order. This creates or updates an ordinary server playlist usable in other clients.',
                ),
                const SizedBox(height: 12),
                const Text(
                  'Updates happen only when you publish here. The smart configuration stays on this device. Your playing queue stays unchanged.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _name,
                  enabled: !_busy,
                  maxLength: 120,
                  decoration: InputDecoration(
                    labelText: _link == null
                        ? 'Server copy name'
                        : 'Name for a separate copy',
                  ),
                ),
                if (_link?.remoteId != null)
                  Text(
                    'Linked server copy: ${_link!.name}. Updating replaces its songs and keeps its server name and sharing settings.',
                  ),
                if (_link?.creationUncertain == true) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'A previous create has an uncertain result. Select an existing copy to verify its full song order, or deliberately create another.',
                  ),
                  TextButton(
                    onPressed: _busy ? null : _findCopies,
                    child: const Text('Check existing copies'),
                  ),
                ],
                if (_copies != null) ...[
                  if (_copies!.isEmpty)
                    const Text('No owned writable playlists were returned.'),
                  for (final copy in _copies!)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(copy.name),
                      subtitle: Text('${copy.songCount} songs · ${copy.id}'),
                      onTap: _busy
                          ? null
                          : () => _run(
                              () => widget.publisher.recover(
                                widget.definition.id,
                                copy.id,
                              ),
                            ),
                    ),
                ],
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (_conflict != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Server copy “${_conflict!.name}”: ${_conflict!.tracks.length} songs. Replacing will use the ${widget.result.matches.length} preview songs.',
                  ),
                  const SizedBox(height: 8),
                  const Text('First songs currently on the server:'),
                  for (final track in _conflict!.tracks.take(5))
                    Text('${track.title} · ${track.artist}'),
                ],
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: LinearProgressIndicator(),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(_conflict == null ? 'Cancel' : 'Keep server edits'),
        ),
        if (_link != null && widget.publisher.canWrite)
          TextButton(
            onPressed: _busy ? null : _separate,
            child: const Text('Create separate copy'),
          ),
        if (_conflict != null)
          FilledButton(
            onPressed: _busy
                ? null
                : () {
                    final reviewed = _conflict!;
                    _publish(reviewed: reviewed);
                  },
            child: const Text('Replace reviewed copy'),
          )
        else if (_link?.creationUncertain != true && widget.publisher.canWrite)
          FilledButton(
            onPressed: _busy ? null : () => _publish(),
            child: Text(
              _link == null ? 'Create server copy' : 'Update server copy',
            ),
          ),
      ],
    ),
  );
}
