import 'glass_overlays.dart';

import 'package:flutter/material.dart';

import '../models/playlist_icon.dart';
import '../services/playlist_icon_store.dart';

extension PlaylistIconGraphic on PlaylistIcon {
  IconData get graphic => switch (this) {
    PlaylistIcon.automatic => Icons.restart_alt_rounded,
    PlaylistIcon.sparkles => Icons.auto_awesome_outlined,
    PlaylistIcon.music => Icons.music_note_rounded,
    PlaylistIcon.radio => Icons.radio_rounded,
    PlaylistIcon.favorite => Icons.favorite_rounded,
    PlaylistIcon.star => Icons.star_rounded,
    PlaylistIcon.shuffle => Icons.shuffle_rounded,
    PlaylistIcon.moon => Icons.nightlight_round,
    PlaylistIcon.bolt => Icons.bolt_rounded,
    PlaylistIcon.headphones => Icons.headphones_rounded,
    PlaylistIcon.album => Icons.album_rounded,
    PlaylistIcon.coffee => Icons.coffee_rounded,
  };
}

Future<void> choosePlaylistIcon(
  BuildContext context, {
  required PlaylistIconStore store,
  required String id,
  required String name,
}) async {
  await store.load();
  if (!context.mounted) return;
  if (!store.canWrite) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(store.error!)));
    return;
  }
  final icon = await showGlassSheet<PlaylistIcon>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: .55,
      maxChildSize: .9,
      minChildSize: .35,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Text('Choose icon', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(name),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final icon in PlaylistIcon.values)
                SizedBox(
                  width: 88,
                  child: Semantics(
                    selected: store.iconFor(id) == icon,
                    child: TextButton(
                      onPressed: () => Navigator.pop(context, icon),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(icon.graphic),
                          const SizedBox(height: 6),
                          Text(icon.label, textAlign: TextAlign.center),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    ),
  );
  if (icon == null) return;
  final saved = await store.setIcon(id, icon);
  if (!saved && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(store.error ?? 'Could not save this icon.')),
    );
  }
}

class PlaylistIconTile extends StatelessWidget {
  const PlaylistIconTile({
    super.key,
    required this.store,
    required this.id,
    required this.name,
    required this.fallback,
    this.artwork,
  });
  final PlaylistIconStore store;
  final String id;
  final String name;
  final PlaylistIcon fallback;
  final Widget? artwork;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final icon = store.iconFor(id);
      return Tooltip(
        message: 'Choose icon for $name',
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () =>
              choosePlaylistIcon(context, store: store, id: id, name: name),
          child: SizedBox.square(
            dimension: 60,
            child: icon == PlaylistIcon.automatic && artwork != null
                ? artwork!
                : DecoratedBox(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.onSurface
                          .withValues(alpha: .08),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      (icon == PlaylistIcon.automatic ? fallback : icon)
                          .graphic,
                      size: 28,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
          ),
        ),
      );
    },
  );
}
