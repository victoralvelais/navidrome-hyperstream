part of 'player_controls.dart';

class _NowPlaying extends StatefulWidget {
  const _NowPlaying({
    required this.playback,
    required this.client,
    this.collections,
    this.onAlbum,
    this.onArtist,
  });
  final PlaybackService playback;
  final NavidromeClient client;
  final LibraryCollections? collections;
  final ValueChanged<Album>? onAlbum;
  final ValueChanged<Artist>? onArtist;
  @override
  State<_NowPlaying> createState() => _NowPlayingState();
}

class _NowPlayingState extends State<_NowPlaying> {
  PlaybackService get playback => widget.playback;
  bool _volumeOpen = false;

  void _visitLibrary(VoidCallback action) {
    final route = ModalRoute.of(context);
    Navigator.of(context).popUntil((candidate) => candidate == route);
    Navigator.pop(context);
    action();
  }

  Widget _actions(Track track) => NowPlayingTrackActions(
    song: track,
    playback: playback,
    collections: widget.collections!,
    onAlbum: widget.onAlbum == null
        ? null
        : (album) => _visitLibrary(() => widget.onAlbum!(album)),
    onArtist: widget.onArtist == null
        ? null
        : (artist) => _visitLibrary(() => widget.onArtist!(artist)),
  );

  Widget _volumeSpace(Widget child) => AnimatedPadding(
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180),
    curve: Curves.easeOutCubic,
    padding: EdgeInsets.only(right: _volumeOpen ? 72 : 0),
    child: child,
  );

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    heightFactor: 1,
    child: Semantics(
      label: 'Music player',
      onDismiss: () => Navigator.pop(context),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              Navigator.maybePop(context),
        },
        child: Focus(
          autofocus: true,
          child: EdgeBackGesture(
            onBack: () => Navigator.pop(context),
            child: _PlaybackView(
              playback: playback,
              builder: (context, item, state) {
                final track = playback.trackAt(state.queueIndex ?? -1);
                final coverSize = (MediaQuery.sizeOf(context).height * .44)
                    .clamp(180.0, 380.0);
                final scheme = Theme.of(context).colorScheme;
                return ArtworkBackdrop(
                  client: widget.client,
                  coverArt: item?.extras?['coverArtId'] as String?,
                  child: Builder(
                    builder: (context) => SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        24,
                        MediaQuery.paddingOf(context).top + 28,
                        24,
                        MediaQuery.paddingOf(context).bottom + 28,
                      ),
                      child: Column(
                        children: [
                          Center(
                            child: ConstrainedBox(
                              constraints: BoxConstraints(maxWidth: coverSize),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: .24,
                                      ),
                                      blurRadius: 32,
                                      offset: const Offset(0, 12),
                                    ),
                                  ],
                                ),
                                child: CoverArt(
                                  client: widget.client,
                                  id: item?.extras?['coverArtId'] as String?,
                                  radius: 20,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 28),
                          Row(
                            children: [
                              Expanded(
                                child: _TrackLabels(item: item, large: true),
                              ),
                              if (track != null &&
                                  widget.collections != null) ...[
                                const SizedBox(width: 8),
                                FavoriteButton(
                                  collections: widget.collections!,
                                  song: track,
                                ),
                                _actions(track),
                              ],
                            ],
                          ),
                          const SizedBox(height: 12),
                          _volumeSpace(
                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                activeTrackColor: scheme.onSurface,
                                inactiveTrackColor: scheme.onSurface.withValues(
                                  alpha: .20,
                                ),
                                thumbColor: scheme.onSurface,
                                thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 4,
                                ),
                                overlayShape: const RoundSliderOverlayShape(
                                  overlayRadius: 14,
                                ),
                              ),
                              child: _SeekBar(
                                key: ValueKey(item?.id),
                                playback: playback,
                                item: item,
                                state: state,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          _volumeSpace(
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                _Previous(
                                  playback: playback,
                                  state: state,
                                  large: true,
                                ),
                                _PlayButton(
                                  playback: playback,
                                  item: item,
                                  state: state,
                                  large: true,
                                ),
                                _Next(
                                  playback: playback,
                                  state: state,
                                  large: true,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 28),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              GlassSurface(
                                child: IconButton(
                                  tooltip: 'Show queue',
                                  icon: const Icon(Icons.queue_music_rounded),
                                  onPressed: () => showGlassSheet<void>(
                                    context: context,
                                    pullFromList: true,
                                    builder: (_) => _QueuePage(
                                      playback: playback,
                                      client: widget.client,
                                      collections: widget.collections,
                                      trackActions: _actions,
                                    ),
                                  ),
                                ),
                              ),
                              ValueListenableBuilder<SleepTimerState?>(
                                valueListenable: playback.sleepTimer,
                                builder: (context, timer, _) => IconButton(
                                  tooltip: timer == null
                                      ? 'Sleep timer'
                                      : 'Sleep timer active',
                                  isSelected: timer != null,
                                  color: timer == null ? null : scheme.primary,
                                  icon: const Icon(Icons.bedtime_outlined),
                                  onPressed: item == null
                                      ? null
                                      : () => showSleepTimer(context, playback),
                                ),
                              ),
                              GlassSurface(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const OutputButton(),
                                    VolumeButton(
                                      playback: playback,
                                      onExpandedChanged: (open) =>
                                          setState(() => _volumeOpen = open),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          _SleepStatus(playback: playback),
                          _PlayerErrors(playback: playback, state: state),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    ),
  );
}

class _SleepStatus extends StatelessWidget {
  const _SleepStatus({required this.playback});
  final PlaybackService playback;
  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<SleepTimerState?>(
    valueListenable: playback.sleepTimer,
    builder: (context, timer, _) {
      if (timer == null) return const SizedBox.shrink();
      final label = timer.endOfTrack
          ? 'Sleep at the end of this track'
          : 'Sleep at ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(timer.deadline!), alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context))}';
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(label, style: Theme.of(context).textTheme.bodySmall),
      );
    },
  );
}

class _QueuePage extends StatefulWidget {
  const _QueuePage({
    required this.playback,
    required this.client,
    required this.collections,
    required this.trackActions,
  });
  final PlaybackService playback;
  final NavidromeClient client;
  final LibraryCollections? collections;
  final Widget Function(Track) trackActions;
  @override
  State<_QueuePage> createState() => _QueuePageState();
}

class _QueuePageState extends State<_QueuePage> {
  ScrollController get _scroll => PrimaryScrollController.of(context);

  Future<void> _option(String option) async {
    final playback = widget.playback;
    final track = playback.trackAt(
      playback.playbackState.value.queueIndex ?? -1,
    );
    switch (option) {
      case 'sleep':
        await showSleepTimer(context, playback);
      case 'top':
        await _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
        );
      case 'save':
        if (widget.collections != null) {
          await addTracksToPlaylist(
            context,
            widget.collections!,
            playback.queue.value.map((item) => item.id).toList(),
          );
        }
      case 'clear':
        final clear = await showDialog<bool>(
          context: context,
          builder: (context) => GlassAlertDialog(
            title: const Text('Clear queue?'),
            content: const Text('Playback will stop.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Clear'),
              ),
            ],
          ),
        );
        if (clear == true) {
          await playback.reset();
          if (mounted) Navigator.pop(context);
        }
      case 'speed':
        final speed = await showGlassSheet<double>(
          context: context,
          builder: (context) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Playback rate',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                for (final speed in [.5, .75, 1.0, 1.25, 1.5, 2.0])
                  ListTile(
                    title: Text('$speed×'),
                    trailing: playback.playbackState.value.speed == speed
                        ? const Icon(Icons.check_rounded)
                        : null,
                    onTap: () => Navigator.pop(context, speed),
                  ),
              ],
            ),
          ),
        );
        if (speed != null) await playback.setSpeed(speed);
      case 'info':
        await showDialog<void>(
          context: context,
          builder: (context) => GlassAlertDialog(
            title: const Text('Player info'),
            content: Text(
              track == null
                  ? 'Nothing playing'
                  : '${track.title}\n${track.artist}\n${track.album}\n\nOriginal file${track.audioDetails.isEmpty ? '' : ' · ${track.audioDetails}'}\nPlayback rate: ${playback.playbackState.value.speed}×',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ],
          ),
        );
      case 'lyrics':
        if (track == null) return;
        final lyrics = widget.client.lyrics(track);
        await showGlassSheet<void>(
          context: context,
          builder: (context) => FractionallySizedBox(
            heightFactor: .75,
            child: Column(
              children: [
                Text(
                  'Lyrics',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Expanded(
                  child: FutureBuilder<String?>(
                    future: lyrics,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      return SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: SelectableText(
                          snapshot.hasError
                              ? 'Could not load lyrics from this server.'
                              : snapshot.data ??
                                    'No lyrics were provided by this server.',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    heightFactor: .90,
    child: EdgeBackGesture(
      onBack: () => Navigator.pop(context),
      child: StreamBuilder<List<MediaItem>>(
        stream: widget.playback.queue,
        initialData: widget.playback.queue.value,
        builder: (context, queue) => _PlaybackView(
          playback: widget.playback,
          builder: (context, item, state) {
            final playback = widget.playback;
            final track = playback.trackAt(state.queueIndex ?? -1);
            final upcoming = playback.upcomingIndices;
            final shuffle = state.shuffleMode != AudioServiceShuffleMode.none;
            final busy = state.processingState == AudioProcessingState.loading;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 4, 12),
                  child: Row(
                    children: [
                      SizedBox.square(
                        dimension: 52,
                        child: CoverArt(
                          client: widget.client,
                          id: item?.extras?['coverArtId'] as String?,
                          radius: 12,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: _TrackLabels(item: item)),
                      if (track != null && widget.collections != null) ...[
                        if (MediaQuery.sizeOf(context).width >= 360)
                          FavoriteButton(
                            collections: widget.collections!,
                            song: track,
                          ),
                        widget.trackActions(track),
                      ],
                      IconButton(
                        tooltip: 'Close queue',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded, size: 20),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: CustomScrollView(
                    key: const ValueKey('up-next-list'),
                    controller: _scroll,
                    slivers: [
                      SliverPersistentHeader(
                        pinned: true,
                        delegate: _QueueHeader(
                          child: GlassSurface(
                            radius: 24,
                            child: Padding(
                              padding: const EdgeInsets.only(
                                left: 16,
                                right: 4,
                              ),
                              child: Row(
                                children: [
                                  const Expanded(
                                    child: Text('Up next', maxLines: 1),
                                  ),
                                  IconButton(
                                    tooltip: shuffle
                                        ? 'Turn shuffle off'
                                        : 'Shuffle queue',
                                    isSelected: shuffle,
                                    icon: const Icon(Icons.shuffle_rounded),
                                    onPressed: busy
                                        ? null
                                        : () => playback.setShuffleMode(
                                            shuffle
                                                ? AudioServiceShuffleMode.none
                                                : AudioServiceShuffleMode.all,
                                          ),
                                  ),
                                  IconButton(
                                    tooltip: switch (state.repeatMode) {
                                      AudioServiceRepeatMode.none =>
                                        'Repeat off',
                                      AudioServiceRepeatMode.one =>
                                        'Repeat one',
                                      _ => 'Repeat all',
                                    },
                                    isSelected:
                                        state.repeatMode !=
                                        AudioServiceRepeatMode.none,
                                    icon: Icon(
                                      state.repeatMode ==
                                              AudioServiceRepeatMode.one
                                          ? Icons.repeat_one_rounded
                                          : Icons.repeat_rounded,
                                    ),
                                    onPressed: busy
                                        ? null
                                        : () => playback.setRepeatMode(
                                            switch (state.repeatMode) {
                                              AudioServiceRepeatMode.none =>
                                                AudioServiceRepeatMode.all,
                                              AudioServiceRepeatMode.all =>
                                                AudioServiceRepeatMode.one,
                                              _ => AudioServiceRepeatMode.none,
                                            },
                                          ),
                                  ),
                                  GlassPopupMenuButton<String>(
                                    tooltip: 'Queue options',
                                    icon: const Icon(Icons.more_horiz_rounded),
                                    onSelected: _option,
                                    itemBuilder: (_) => [
                                      menuAction(
                                        'info',
                                        'Player info',
                                        Icons.info_outline_rounded,
                                      ),
                                      menuAction(
                                        'top',
                                        'Scroll to next track',
                                        Icons.vertical_align_top_rounded,
                                      ),
                                      menuAction(
                                        'save',
                                        'Add queue to playlist',
                                        Icons.playlist_add_rounded,
                                        enabled:
                                            widget.collections != null &&
                                            queue.data!.isNotEmpty,
                                      ),
                                      menuAction(
                                        'lyrics',
                                        'Show lyrics',
                                        Icons.lyrics_outlined,
                                        enabled: track != null,
                                      ),
                                      menuAction(
                                        'speed',
                                        'Playback rate',
                                        Icons.speed_rounded,
                                      ),
                                      menuAction(
                                        'sleep',
                                        'Sleep timer',
                                        Icons.bedtime_outlined,
                                        enabled: track != null,
                                      ),
                                      const PopupMenuDivider(),
                                      menuAction(
                                        'clear',
                                        'Clear queue',
                                        Icons.clear_all_rounded,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (upcoming.isEmpty)
                        const SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(child: Text('You’re all caught up.')),
                        ),
                      SliverReorderableList(
                        itemCount: upcoming.length,
                        onReorderItem: (from, to) {
                          playback.moveUpcoming(upcoming[from], upcoming[to]);
                        },
                        itemBuilder: (context, position) {
                          final index = upcoming[position];
                          final next = queue.data![index];
                          final song = playback.trackAt(index);
                          return ListTile(
                            key: ValueKey(index),
                            contentPadding: const EdgeInsets.only(
                              left: 16,
                              right: 4,
                            ),
                            leading: SizedBox.square(
                              dimension: 44,
                              child: CoverArt(
                                client: widget.client,
                                id: next.extras?['coverArtId'] as String?,
                                radius: 10,
                              ),
                            ),
                            title: Text(
                              next.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              next.artist ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface
                                    .withValues(alpha: .82),
                              ),
                            ),
                            onTap: busy
                                ? null
                                : () => playback.skipToQueueItem(index),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (song != null && widget.collections != null)
                                  if (MediaQuery.sizeOf(context).width >= 360)
                                    FavoriteButton(
                                      collections: widget.collections!,
                                      song: song,
                                    ),
                                GlassPopupMenuButton<String>(
                                  tooltip: 'Queue actions for ${next.title}',
                                  icon: const Icon(Icons.more_horiz_rounded),
                                  enabled: !busy,
                                  itemBuilder: (_) => [
                                    menuAction(
                                      'remove',
                                      'Remove from queue',
                                      Icons.remove_circle_outline_rounded,
                                    ),
                                  ],
                                  onSelected: (_) =>
                                      playback.removeUpcoming(index),
                                ),
                                if (!shuffle && !busy)
                                  ReorderableDragStartListener(
                                    index: position,
                                    child: const Tooltip(
                                      message: 'Drag to reorder',
                                      child: Padding(
                                        padding: EdgeInsets.all(10),
                                        child: Icon(
                                          Icons.drag_handle_rounded,
                                          size: 20,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                  child: _SeekBar(playback: playback, item: item, state: state),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _Previous(playback: playback, state: state),
                    _PlayButton(playback: playback, item: item, state: state),
                    _Next(playback: playback, state: state),
                  ],
                ),
                _SleepStatus(playback: playback),
                _PlayerErrors(playback: playback, state: state),
              ],
            );
          },
        ),
      ),
    ),
  );
}

class _QueueHeader extends SliverPersistentHeaderDelegate {
  _QueueHeader({required this.child});
  final Widget child;
  @override
  double get minExtent => 56;
  @override
  double get maxExtent => 56;
  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => SizedBox(height: maxExtent, child: child);
  @override
  bool shouldRebuild(_QueueHeader oldDelegate) => true;
}
