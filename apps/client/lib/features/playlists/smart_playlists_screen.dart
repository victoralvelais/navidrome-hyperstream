import '../../widgets/glass_overlays.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/smart_playlist.dart';
import '../../models/playlist_icon.dart';
import '../../services/library_catalog.dart';
import '../../services/playback_service.dart';
import '../../services/smart_playlist_preview.dart';
import '../../services/smart_playlist_store.dart';
import '../../services/playlist_icon_store.dart';
import '../../services/library_collections.dart';
import '../../models/library.dart';
import '../../widgets/edge_back_gesture.dart';
import '../../widgets/floating_chrome.dart';
import '../../widgets/playlist_icon_picker.dart';
import '../../widgets/pull_to_refresh.dart';
import 'smart_playlist_editor.dart';
import 'smart_playlist_results.dart';
import 'playlist_publish_dialog.dart';

Future<String?> editSmartPlaylist(
  BuildContext context, {
  SmartPlaylistDefinition? initial,
  required LibraryCatalog catalog,
  required SmartPlaylistStore store,
  required PlaybackService playback,
}) async {
  await store.load();
  if (!context.mounted) return null;
  if (!store.canWrite) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(store.error ?? 'Saved playlists are unavailable.'),
      ),
    );
    return null;
  }
  return Navigator.push<String>(
    context,
    MenuPageRoute(
      builder: (_) => SmartPlaylistEditor(
        initial:
            initial ??
            SmartPlaylistDefinition.initial(SmartPlaylistStore.newId()),
        catalog: catalog,
        store: store,
        playback: playback,
      ),
    ),
  );
}

class SmartPlaylistScreen extends StatefulWidget {
  const SmartPlaylistScreen({
    super.key,
    required this.id,
    required this.catalog,
    required this.store,
    required this.icons,
    required this.playback,
    required this.onDeleted,
    this.collections,
  });
  final String id;
  final LibraryCatalog catalog;
  final SmartPlaylistStore store;
  final PlaylistIconStore icons;
  final PlaybackService playback;
  final VoidCallback onDeleted;
  final LibraryCollections? collections;
  @override
  State<SmartPlaylistScreen> createState() => SmartPlaylistScreenState();
}

class SmartPlaylistScreenState extends State<SmartPlaylistScreen> {
  bool _reshuffling = false;
  late final _preview = SmartPlaylistPreview(widget.catalog);
  SmartPlaylistDefinition? get definition =>
      widget.store.items.where((item) => item.id == widget.id).firstOrNull;
  @override
  void initState() {
    super.initState();
    widget.store.addListener(_updated);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(widget.catalog.ensureLoaded());
      _updated();
    });
  }

  void _updated() {
    final value = definition;
    if (value != null) unawaited(_preview.update(value));
  }

  @override
  void dispose() {
    widget.store.removeListener(_updated);
    _preview.dispose();
    super.dispose();
  }

  Future<void> edit() async {
    if (definition == null) return;
    await editSmartPlaylist(
      context,
      initial: definition,
      catalog: widget.catalog,
      store: widget.store,
      playback: widget.playback,
    );
  }

  Future<void> _reshuffle() async {
    if (_reshuffling || !widget.store.canWrite || definition == null) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    setState(() => _reshuffling = true);
    final saved = await widget.store.reshuffle(widget.id);
    if (!mounted) return;
    setState(() => _reshuffling = false);
    if (!saved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save the new shuffle. Try again.'),
        ),
      );
    }
  }

  Future<void> delete() async {
    final value = definition;
    if (value == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => GlassAlertDialog(
        title: const Text('Delete smart playlist?'),
        content: Text('Delete "${value.name}" from this device?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final removed = await widget.store.remove(value.id);
    if (!mounted) return;
    if (removed) {
      widget.onDeleted();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.store.error ?? 'Could not delete playlist.'),
        ),
      );
    }
  }

  Future<void> publish() async {
    final value = definition;
    final result = _preview.result;
    final collections = widget.collections;
    if (value == null || collections == null) return;
    if (result == null ||
        result.matches.isEmpty ||
        _preview.busy ||
        widget.catalog.loading ||
        widget.catalog.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Finish a successful library sync and a nonempty preview before publishing.',
          ),
        ),
      );
      return;
    }
    final published = await showDialog<MusicPlaylist>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PlaylistPublishDialog(
        publisher: collections.smartPublisher,
        definition: value,
        result: result,
        catalog: widget.catalog,
      ),
    );
    if (published == null) return;
    await collections.refreshPlaylists();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Server copy verified: ${published.name} · ${published.tracks.length} songs.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.store, widget.catalog, _preview]),
    builder: (context, _) {
      final value = definition;
      if (value == null) {
        return const Center(child: Text('Playlist unavailable.'));
      }
      return PullToRefresh(
        onRefresh: widget.catalog.refresh,
        child: ListView(
          key: ValueKey(widget.id),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            24,
            PageChrome.insetOf(context) + 16,
            24,
            24,
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: PlaylistIconTile(
                store: widget.icons,
                id: 'smart:${value.id}',
                name: value.name,
                fallback: PlaylistIcon.sparkles,
              ),
            ),
            const SizedBox(height: 16),
            Text(value.name, style: Theme.of(context).textTheme.headlineLarge),
            const SizedBox(height: 8),
            Text(
              value.type == SmartPlaylistType.rules
                  ? 'Rules \u00b7 ${value.order.label}'
                  : 'Mix \u00b7 ${value.pools.length} pools',
            ),
            if (!PageChrome.present(context))
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: edit,
                  child: const Text('Edit configuration'),
                ),
              ),
            const SizedBox(height: 20),
            if (!PageChrome.present(context) && widget.collections != null)
              TextButton.icon(
                onPressed: publish,
                icon: const Icon(Icons.cloud_upload_outlined),
                label: const Text('Publish to Navidrome'),
              ),
            SmartPlaylistResults(
              catalog: widget.catalog,
              preview: _preview,
              playback: widget.playback,
              definition: value,
              onReshuffle: widget.store.canWrite ? _reshuffle : null,
              reshuffling: _reshuffling,
            ),
            const DockSpacer(),
          ],
        ),
      );
    },
  );
}
