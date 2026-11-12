import '../../widgets/collection_play_controls.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/smart_playlist.dart';
import '../../services/library_catalog.dart';
import '../../services/playback_service.dart';
import '../../services/smart_playlist_preview.dart';
import '../../widgets/library_sync_status.dart';

/// A bounded on-screen sample; Play always uses the full evaluated result.
class SmartPlaylistResults extends StatelessWidget {
  const SmartPlaylistResults({
    super.key,
    required this.catalog,
    required this.preview,
    required this.playback,
    this.definition,
  });
  final LibraryCatalog catalog;
  final SmartPlaylistPreview preview;
  final PlaybackService playback;
  final SmartPlaylistDefinition? definition;

  void _play(
    SmartPlaylistResult result, [
    int index = 0,
    bool shuffle = false,
  ]) => unawaited(
    playback.playAlbum(
      catalog.client,
      result.matches.map((match) => match.track).toList(),
      index,
      shuffle: shuffle,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final result = preview.result;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (catalog.loading)
          LibrarySyncStatus(catalog: catalog)
        else if (preview.busy)
          const LinearProgressIndicator(),
        if (catalog.error != null) ...[
          Text(
            catalog.error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          TextButton(
            onPressed: catalog.loading ? null : catalog.refresh,
            child: const Text('Retry library sync'),
          ),
        ],
        if (catalog.lastSyncedAt == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'A complete library sync is needed to preview these rules.',
            ),
          ),
        if (preview.error != null)
          Text(
            preview.error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (result != null) ...[
          Text(
            '${result.matchedCount} matched · ${result.matches.length} selected',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (definition?.type == SmartPlaylistType.mix) ...[
            const SizedBox(height: 8),
            for (final (index, pool) in definition!.pools.indexed)
              Text(
                '${pool.name}: ${result.contributions[index]} tracks · requested ${pool.share}% · actual ${result.matches.isEmpty ? 0 : (100 * result.contributions[index] / result.matches.length).round()}%',
              ),
            if (result.scarce)
              Text(
                definition!.fillWhenEmpty
                    ? 'An enabled pool ran out of distinct tracks. Remaining pools filled the mix.'
                    : 'Stopped because an enabled pool ran out of distinct tracks.',
              ),
          ],
          const SizedBox(height: 12),
          CollectionPlayControls(
            onPlay: result.matches.isEmpty || preview.busy
                ? null
                : () => _play(result),
            onShuffle: result.matches.isEmpty || preview.busy
                ? null
                : () => _play(result, 0, true),
          ),
          const SizedBox(height: 8),
          const Text(
            'Play uses this order; Shuffle randomizes it. Later updates leave the playing queue unchanged.',
          ),
          if (result.matches.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No tracks selected. Adjust your rules or pool shares.',
              ),
            ),
          for (final (index, match) in result.matches.take(50).indexed)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Text('${index + 1}'),
              title: Text(
                match.track.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text('${match.track.artist}\n${match.reason}'),
              onTap: preview.busy ? null : () => _play(result, index),
            ),
          if (result.matches.length > 50)
            Text(
              'Showing the first 50 tracks. Play includes all ${result.matches.length}.',
            ),
        ],
      ],
    );
  }
}
