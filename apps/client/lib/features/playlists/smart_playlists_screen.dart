import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/smart_playlist.dart';
import '../../services/library_catalog.dart';
import '../../services/playback_service.dart';
import '../../services/smart_playlist_preview.dart';
import '../../services/smart_playlist_store.dart';
import '../../widgets/pull_to_refresh.dart';
import 'smart_playlist_editor.dart';
import 'smart_playlist_results.dart';

class SmartPlaylistsScreen extends StatefulWidget {
  const SmartPlaylistsScreen({
    super.key,
    required this.catalog,
    required this.store,
    required this.playback,
    required this.onPageChanged,
    this.createOnOpen = false,
  });
  final LibraryCatalog catalog;
  final SmartPlaylistStore store;
  final PlaybackService playback;
  final ValueChanged<bool> onPageChanged;
  final bool createOnOpen;
  @override
  State<SmartPlaylistsScreen> createState() => SmartPlaylistsScreenState();
}

class SmartPlaylistsScreenState extends State<SmartPlaylistsScreen> {
  late final _preview = SmartPlaylistPreview(widget.catalog);
  String? _selected;
  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  Future<void> _open() async {
    await widget.store.load();
    if (!mounted) return;
    unawaited(widget.catalog.ensureLoaded());
    if (widget.createOnOpen && widget.store.canWrite) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_edit());
      });
    }
  }

  @override
  void dispose() {
    _preview.dispose();
    super.dispose();
  }

  bool back() {
    if (_selected == null) return false;
    _preview.clear();
    setState(() => _selected = null);
    widget.onPageChanged(false);
    return true;
  }

  void _select(SmartPlaylistDefinition definition) {
    setState(() => _selected = definition.id);
    widget.onPageChanged(true);
    unawaited(widget.catalog.ensureLoaded());
    unawaited(_preview.update(definition));
  }

  Future<void> _edit([SmartPlaylistDefinition? initial]) async {
    final id = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => SmartPlaylistEditor(
          initial:
              initial ??
              SmartPlaylistDefinition.initial(SmartPlaylistStore.newId()),
          catalog: widget.catalog,
          store: widget.store,
          playback: widget.playback,
        ),
      ),
    );
    if (!mounted || id == null) return;
    final definition = widget.store.items
        .where((item) => item.id == id)
        .firstOrNull;
    if (definition != null) _select(definition);
  }

  Future<void> _delete(SmartPlaylistDefinition definition) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete smart playlist?'),
        content: Text('Delete “${definition.name}” from this device?'),
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
    if (confirmed == true &&
        await widget.store.remove(definition.id) &&
        mounted) {
      back();
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.store, widget.catalog, _preview]),
    builder: (context, _) {
      final definition = widget.store.items
          .where((item) => item.id == _selected)
          .firstOrNull;
      return PullToRefresh(
        onRefresh: widget.catalog.refresh,
        child: ListView(
          key: ValueKey(_selected ?? 'smart-playlists'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    definition?.name ?? 'Smart playlists',
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                ),
                if (definition == null)
                  IconButton(
                    tooltip: 'New smart playlist',
                    onPressed: widget.store.canWrite ? () => _edit() : null,
                    icon: const Icon(Icons.add_rounded),
                  )
                else
                  PopupMenuButton<String>(
                    tooltip: 'Playlist options',
                    onSelected: (action) {
                      if (action == 'edit') {
                        unawaited(_edit(definition));
                      } else {
                        unawaited(_delete(definition));
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'edit',
                        enabled: widget.store.canWrite,
                        child: const Text('Edit configuration'),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        enabled: widget.store.canWrite,
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (!widget.store.loaded) const LinearProgressIndicator(),
            if (widget.store.error != null)
              Text(
                widget.store.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (definition == null) ...[
              const Text(
                'Rules select and order one list. Mix combines pools with their own conditions and shares.',
              ),
              const SizedBox(height: 8),
              const Text(
                'Saved on this device for the current server and account.',
              ),
              const SizedBox(height: 16),
              if (widget.store.loaded &&
                  widget.store.items.isEmpty &&
                  widget.store.canWrite)
                const Text('Create a smart playlist with the plus button.'),
              for (final item in widget.store.items)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    item.type == SmartPlaylistType.rules
                        ? Icons.filter_alt_outlined
                        : Icons.shuffle_rounded,
                  ),
                  title: Text(item.name),
                  subtitle: Text(
                    item.type == SmartPlaylistType.rules
                        ? 'Rules · ${item.order.label}'
                        : 'Mix · ${item.pools.length} pools',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _select(item),
                ),
            ] else ...[
              Text(
                definition.type == SmartPlaylistType.rules
                    ? 'Rules · ${definition.order.label}'
                    : 'Mix · ${definition.pools.length} pools',
              ),
              const SizedBox(height: 8),
              const Text(
                'Local listening updates automatically. Pull to sync the library; it also syncs every 30 minutes while active.',
              ),
              const SizedBox(height: 20),
              SmartPlaylistResults(
                catalog: widget.catalog,
                preview: _preview,
                playback: widget.playback,
                definition: definition,
              ),
            ],
            const DockSpacer(),
          ],
        ),
      );
    },
  );
}
