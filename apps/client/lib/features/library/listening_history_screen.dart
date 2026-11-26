import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/library_catalog.dart';
import '../../services/playback_service.dart';
import '../../widgets/floating_chrome.dart';
import '../../widgets/pull_to_refresh.dart';
import '../search/source_import_action.dart';
import 'cover_art.dart';

/// One row per recording, with its most recent qualified listen and play count.
class ListeningHistoryScreen extends StatefulWidget {
  const ListeningHistoryScreen({
    super.key,
    required this.catalog,
    required this.playback,
  });
  final LibraryCatalog catalog;
  final PlaybackService playback;
  @override
  State<ListeningHistoryScreen> createState() => _ListeningHistoryScreenState();
}

class _ListeningHistoryScreenState extends State<ListeningHistoryScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.catalog.ensureLoaded());
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.catalog,
    builder: (context, _) {
      final catalog = widget.catalog;
      final tracks =
          catalog.tracks
              .where(
                (t) =>
                    t.lastPlayedAt != null &&
                    !t.lastPlayedAt!.isAfter(catalog.currentTime),
              )
              .toList()
            ..sort((a, b) {
              final byTime = b.lastPlayedAt!.compareTo(a.lastPlayedAt!);
              return byTime == 0 ? a.id.compareTo(b.id) : byTime;
            });
      final labels = MaterialLocalizations.of(context);
      return PullToRefresh(
        onRefresh: catalog.refresh,
        child: CustomScrollView(
          key: const PageStorageKey('listening-history'),
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  24,
                  PageChrome.insetOf(context) + 16,
                  24,
                  24,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'History',
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Your latest listens, from your library and online sources.',
                    ),
                    if (!widget.playback.preferences.reportListens)
                      const Text(
                        'Listening history is paused. Enable it in Home > Playback to record new listens.',
                      ),
                    if (catalog.loading) const LinearProgressIndicator(),
                    if (catalog.error != null) Text(catalog.error!),
                    if (tracks.isEmpty && !catalog.loading)
                      const Padding(
                        padding: EdgeInsets.only(top: 24),
                        child: Text(
                          'No listening history yet. Songs appear after a qualified listen.',
                        ),
                      ),
                  ],
                ),
              ),
            ),
            SliverList.builder(
              itemCount: tracks.length,
              itemBuilder: (context, index) {
                final track = tracks[index];
                final date = track.lastPlayedAt!.toLocal();
                return ListTile(
                  key: ValueKey('history-${track.id}'),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 4,
                  ),
                  leading: SizedBox.square(
                    dimension: 48,
                    child: CoverArt(
                      client: catalog.client,
                      id: track.coverArt,
                      externalUri: track.source?.artwork,
                      sourceId: track.source?.sourceId,
                    ),
                  ),
                  title: Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${track.artist}\n${labels.formatShortDate(date)} · ${labels.formatTimeOfDay(TimeOfDay.fromDateTime(date))}',
                    maxLines: 2,
                  ),
                  trailing: track.source == null
                      ? null
                      : SourceDownloadButton(
                          client: catalog.client,
                          tracks: [track],
                        ),
                  onTap: () => unawaited(
                    widget.playback.playAlbum(catalog.client, tracks, index),
                  ),
                );
              },
            ),
            const SliverToBoxAdapter(child: DockSpacer()),
          ],
        ),
      );
    },
  );
}
