import '../../widgets/collection_play_controls.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/recent_radio.dart';
import '../../services/playback_service.dart';
import '../../services/recent_radio_service.dart';
import '../../widgets/pull_to_refresh.dart';
import '../../widgets/floating_chrome.dart';
import '../../widgets/library_sync_status.dart';
import '../library/cover_art.dart';

class RecentRadioScreen extends StatefulWidget {
  const RecentRadioScreen({
    super.key,
    required this.radio,
    required this.playback,
  });
  final RecentRadioService radio;
  final PlaybackService playback;
  @override
  State<RecentRadioScreen> createState() => _RecentRadioScreenState();
}

class _RecentRadioScreenState extends State<RecentRadioScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.radio.ensureLoaded());
  }

  String _updated(DateTime time) {
    final local = time.toLocal();
    final labels = MaterialLocalizations.of(context);
    return '${labels.formatShortDate(local)} ${labels.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
  }

  void _play(RadioPreview preview, [int index = 0, bool shuffle = false]) =>
      unawaited(
        widget.playback.playAlbum(
          widget.radio.client,
          preview.matches.map((match) => match.track).toList(),
          index,
          shuffle: shuffle,
        ),
      );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.radio, widget.playback.preferences]),
    builder: (context, _) {
      final radio = widget.radio;
      final preview = radio.preview;
      return PullToRefresh(
        onRefresh: radio.refresh,
        child: CustomScrollView(
          key: const PageStorageKey('recent-radio'),
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
                      'Recent Radio',
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                    const SizedBox(height: 24),
                    CollectionPlayControls(
                      onPlay: preview == null || preview.matches.isEmpty
                          ? null
                          : () => _play(preview),
                      onShuffle: preview == null || preview.matches.isEmpty
                          ? null
                          : () => _play(preview, 0, true),
                    ),
                    const SizedBox(height: 16),
                    if (!widget.playback.preferences.reportListens)
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: Text(
                          'Listening reports are off on this device. Enable them in Home > Playback to count your Hyperstream listens.',
                        ),
                      ),
                    LibrarySyncStatus(catalog: radio),
                    if (radio.error case final String error) ...[
                      const SizedBox(height: 16),
                      Text(
                        error,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      if (radio.lastSyncedAt != null)
                        const Text(
                          'Showing the last synced library with local listening updates.',
                        ),
                      TextButton(
                        onPressed: radio.loading ? null : radio.refresh,
                        child: const Text('Retry'),
                      ),
                    ],
                    if (preview != null) ...[
                      const SizedBox(height: 24),
                      Text(
                        '${preview.matches.length} ${preview.matches.length == 1 ? 'song' : 'songs'} · 30 days',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      if (radio.lastSyncedAt case final DateTime syncedAt)
                        Text('Library synced ${_updated(syncedAt)}')
                      else
                        const Text(
                          'Showing listens from this session until the library sync succeeds.',
                        ),
                      if (!preview.hasPlayDates && preview.libraryCount > 0)
                        const Text(
                          'No usable play dates are available yet. Only addition dates can contribute to this radio.',
                        ),
                      if (preview.missingDates > 0)
                        Text(
                          '${preview.missingDates} songs have no usable activity dates and were omitted.',
                        ),
                      if (preview.invalidDates > 0)
                        Text(
                          '${preview.invalidDates} songs contain invalid or future dates. Those dates were ignored.',
                        ),
                      if (preview.matches.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 16),
                          child: Text(
                            'No songs were added or played in the last 30 days.',
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
            if (preview != null)
              SliverList.builder(
                itemCount: preview.matches.length,
                itemBuilder: (context, index) {
                  final match = preview.matches[index];
                  return ListTile(
                    key: ValueKey(match.track.id),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 4,
                    ),
                    leading: SizedBox(
                      width: 48,
                      height: 48,
                      child: CoverArt(
                        client: radio.client,
                        id: match.track.coverArt,
                      ),
                    ),
                    title: Text(
                      match.track.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${match.track.artist}\n${match.reason}',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => _play(preview, index),
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
