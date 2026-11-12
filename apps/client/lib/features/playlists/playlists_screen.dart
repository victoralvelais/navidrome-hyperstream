import 'package:flutter/material.dart';

import '../../models/library.dart';
import '../../models/playlist_icon.dart';
import '../../models/smart_playlist.dart';
import '../../services/library_collections.dart';
import '../../services/playlist_icon_store.dart';
import '../../services/smart_playlist_store.dart';
import '../../widgets/floating_chrome.dart';
import '../../widgets/playlist_icon_picker.dart';
import '../../widgets/pull_to_refresh.dart';
import '../library/cover_art.dart';
import 'playlist_dialogs.dart';

class NewPlaylistMenu extends StatelessWidget {
  const NewPlaylistMenu({
    super.key,
    required this.collections,
    required this.onNewSmartPlaylist,
  });
  final LibraryCollections collections;
  final VoidCallback onNewSmartPlaylist;
  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: 'New playlist',
    onSelected: (action) {
      if (action == 'smart') {
        onNewSmartPlaylist();
      } else {
        editPlaylistName(
          context,
          onSave: (name) async {
            await collections.createPlaylist(name);
          },
        );
      }
    },
    itemBuilder: (_) => const [
      PopupMenuItem(value: 'manual', child: Text('New playlist')),
      PopupMenuItem(value: 'smart', child: Text('New smart playlist')),
    ],
    icon: const Icon(Icons.add_rounded),
  );
}

class PlaylistsScreen extends StatefulWidget {
  const PlaylistsScreen({
    super.key,
    required this.collections,
    required this.smartStore,
    required this.icons,
    required this.onSelected,
    required this.onSmartSelected,
    required this.onRecentRadio,
    required this.onNewSmartPlaylist,
  });
  final LibraryCollections collections;
  final SmartPlaylistStore smartStore;
  final PlaylistIconStore icons;
  final ValueChanged<MusicPlaylist> onSelected;
  final ValueChanged<SmartPlaylistDefinition> onSmartSelected;
  final VoidCallback onRecentRadio;
  final VoidCallback onNewSmartPlaylist;
  @override
  State<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

class _PlaylistsScreenState extends State<PlaylistsScreen> {
  final _search = TextEditingController();
  @override
  void initState() {
    super.initState();
    widget.smartStore.load();
    widget.icons.load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.collections, widget.smartStore]),
    builder: (context, _) {
      final query = _search.text.trim().toLowerCase();
      bool matches(String name) => name.toLowerCase().contains(query);
      final smart = widget.smartStore.items
          .where((item) => matches(item.name))
          .toList();
      final manual = (widget.collections.playlists ?? <MusicPlaylist>[])
          .where((item) => matches(item.name))
          .toList();
      final radio = matches('Recent Radio');
      return PullToRefresh(
        onRefresh: widget.collections.refreshPlaylists,
        child: CustomScrollView(
          key: const PageStorageKey('playlists'),
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  24,
                  PageChrome.insetOf(context) + 16,
                  24,
                  16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: ExcludeSemantics(
                            excluding: PageChrome.compactTitleOf(context),
                            child: Opacity(
                              opacity: PageChrome.compactTitleOf(context)
                                  ? 0
                                  : 1,
                              child: Text(
                                'Playlists',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineLarge,
                              ),
                            ),
                          ),
                        ),
                        if (!PageChrome.present(context))
                          NewPlaylistMenu(
                            collections: widget.collections,
                            onNewSmartPlaylist: widget.onNewSmartPlaylist,
                          ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: 'Search Playlists',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: query.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear playlist search',
                                onPressed: () => setState(_search.clear),
                                icon: const Icon(Icons.close_rounded),
                              ),
                        filled: true,
                        fillColor: Theme.of(context).colorScheme.onSurface
                            .withValues(alpha: .07),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    if (widget.collections.playlistsLoading ||
                        !widget.smartStore.loaded)
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: LinearProgressIndicator(),
                      ),
                    if (widget.collections.playlistsError
                        case final String error)
                      Text(error),
                    if (widget.smartStore.error case final String error)
                      Text(error),
                    if (!radio && smart.isEmpty && manual.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 24),
                        child: Text('No matching playlists.'),
                      ),
                  ],
                ),
              ),
            ),
            SliverList.list(
              children: [
                for (final item in smart)
                  _row(
                    context,
                    name: item.name,
                    id: 'smart:${item.id}',
                    fallback: PlaylistIcon.sparkles,
                    subtitle: item.type == SmartPlaylistType.rules
                        ? 'Smart playlist \u00b7 Rules'
                        : 'Smart playlist \u00b7 Mix',
                    onTap: () => widget.onSmartSelected(item),
                  ),
                if (radio)
                  _row(
                    context,
                    name: 'Recent Radio',
                    id: 'radio',
                    fallback: PlaylistIcon.radio,
                    onTap: widget.onRecentRadio,
                  ),
                for (final item in manual)
                  _row(
                    context,
                    name: item.name,
                    id: 'playlist:${item.id}',
                    fallback: PlaylistIcon.music,
                    subtitle: '${item.songCount} songs',
                    artwork: CoverArt(
                      client: widget.collections.client,
                      id: item.coverArt,
                    ),
                    onTap: () => widget.onSelected(item),
                  ),
              ],
            ),
            const SliverToBoxAdapter(child: DockSpacer()),
          ],
        ),
      );
    },
  );
  Widget _row(
    BuildContext context, {
    required String name,
    required String id,
    required PlaylistIcon fallback,
    required VoidCallback onTap,
    String? subtitle,
    Widget? artwork,
  }) => Column(
    children: [
      ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
        leading: PlaylistIconTile(
          store: widget.icons,
          id: id,
          name: name,
          fallback: fallback,
          artwork: artwork,
        ),
        title: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: subtitle == null
            ? null
            : Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
      const Padding(
        padding: EdgeInsets.only(left: 100, right: 24),
        child: Divider(height: 1),
      ),
    ],
  );
}
