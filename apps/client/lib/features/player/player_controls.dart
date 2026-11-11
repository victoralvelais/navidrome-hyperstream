import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import '../../models/library.dart';
import '../../services/library_collections.dart';
import '../../services/navidrome_client.dart';
import '../../services/playback_service.dart';
import '../../widgets/glass_surface.dart';
import '../library/artwork_backdrop.dart';
import '../library/collection_actions.dart';
import '../library/cover_art.dart';
import 'volume_button.dart';
import 'output_button.dart';

String _time(Duration value) =>
    '${value.inMinutes}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';

class PlayerControls extends StatelessWidget {
  const PlayerControls({
    super.key,
    required this.playback,
    required this.client,
    this.collections,
    this.compact = false,
  });
  final PlaybackService playback;
  final NavidromeClient client;
  final LibraryCollections? collections;
  final bool compact;

  @override
  Widget build(BuildContext context) => _PlaybackView(
    playback: playback,
    builder: (context, item, state) {
      if (item == null && state.processingState != AudioProcessingState.error) {
        return compact
            ? const GlassSurface(
                radius: 28,
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Not playing', maxLines: 1),
                ),
              )
            : const SizedBox.shrink();
      }
      final labels = InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          backgroundColor: Colors.transparent,
          showDragHandle: false,
          constraints: const BoxConstraints(maxWidth: 560),
          builder: (_) => _NowPlaying(
            playback: playback,
            client: client,
            collections: collections,
          ),
        ),
        child: Semantics(
          button: true,
          label: 'Open now playing',
          child: Row(
            children: [
              if (!compact)
                SizedBox(
                  width: 42,
                  height: 42,
                  child: CoverArt(
                    client: client,
                    id: item?.extras?['coverArtId'] as String?,
                    radius: 12,
                  ),
                ),
              if (!compact) const SizedBox(width: 10),
              Expanded(child: _TrackLabels(item: item)),
            ],
          ),
        ),
      );
      final controls = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Previous(playback: playback, state: state),
          _PlayButton(playback: playback, item: item, state: state),
          _Next(playback: playback, state: state),
          if (!compact) VolumeButton(playback: playback),
        ],
      );
      return Padding(
        padding: compact
            ? EdgeInsets.zero
            : const EdgeInsets.fromLTRB(12, 6, 12, 8),
        child: GlassSurface(
          radius: 28,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: LayoutBuilder(
                  builder: (context, bounds) {
                    final narrow =
                        !compact &&
                        (bounds.maxWidth < 330 ||
                            MediaQuery.textScalerOf(context).scale(1) > 1.2);
                    return IconButtonTheme(
                      data: IconButtonThemeData(
                        style: IconButton.styleFrom(
                          minimumSize: const Size(44, 44),
                          maximumSize: const Size(44, 44),
                          padding: EdgeInsets.zero,
                        ),
                      ),
                      child: narrow
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                labels,
                                const SizedBox(height: 4),
                                controls,
                              ],
                            )
                          : Row(
                              children: [
                                Expanded(child: labels),
                                const SizedBox(width: 4),
                                controls,
                              ],
                            ),
                    );
                  },
                ),
              ),
              _PlayerErrors(playback: playback, state: state),
              StreamBuilder<Duration>(
                stream: playback.positionStream,
                initialData: playback.position,
                builder: (context, snapshot) {
                  final duration = item?.duration?.inMilliseconds ?? 0;
                  final busy =
                      state.processingState == AudioProcessingState.loading ||
                      state.processingState == AudioProcessingState.buffering;
                  return LinearProgressIndicator(
                    minHeight: 1.5,
                    color: Theme.of(context).colorScheme.onSurface
                        .withValues(alpha: .6),
                    value: busy
                        ? null
                        : duration <= 0
                        ? 0
                        : ((snapshot.data?.inMilliseconds ?? 0) / duration)
                              .clamp(0, 1),
                    backgroundColor: Colors.transparent,
                  );
                },
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _NowPlaying extends StatefulWidget {
  const _NowPlaying({
    required this.playback,
    required this.client,
    this.collections,
  });
  final PlaybackService playback;
  final NavidromeClient client;
  final LibraryCollections? collections;

  @override
  State<_NowPlaying> createState() => _NowPlayingState();
}

class _NowPlayingState extends State<_NowPlaying> {
  PlaybackService get playback => widget.playback;
  NavidromeClient get client => widget.client;
  LibraryCollections? get collections => widget.collections;
  bool _volumeOpen = false;

  Widget _volumeSpace(Widget child) => AnimatedPadding(
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180),
    curve: Curves.easeOutCubic,
    padding: EdgeInsets.only(right: _volumeOpen ? 72 : 0),
    child: child,
  );

  Track _track(MediaItem item) => Track(
    id: item.id,
    title: item.title,
    artist: item.artist ?? 'Unknown artist',
    album: item.album ?? 'Unknown album',
    duration: item.duration ?? Duration.zero,
    coverArt: item.extras?['coverArtId'] as String?,
    starred: item.extras?['starred'] as bool? ?? false,
  );

  void _showQueue(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (context) => FractionallySizedBox(
      heightFactor: .7,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Up next',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                IconButton(
                  tooltip: 'Close queue',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<List<MediaItem>>(
              stream: playback.queue,
              initialData: playback.queue.value,
              builder: (context, queue) => StreamBuilder<PlaybackState>(
                stream: playback.playbackState,
                initialData: playback.playbackState.value,
                builder: (context, state) => ListView.builder(
                  itemCount: queue.data?.length ?? 0,
                  itemBuilder: (context, index) {
                    final item = queue.data![index];
                    return ListTile(
                      selected: index == state.data?.queueIndex,
                      leading: SizedBox(
                        width: 44,
                        height: 44,
                        child: CoverArt(
                          client: client,
                          id: item.extras?['coverArtId'] as String?,
                        ),
                      ),
                      title: Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(item.artist ?? '', maxLines: 1),
                      trailing: index == state.data?.queueIndex
                          ? const Icon(Icons.graphic_eq_rounded)
                          : null,
                      onTap: () => playback.skipToQueueItem(index),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    heightFactor: .98,
    child: ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      child: _PlaybackView(
        playback: playback,
        builder: (context, item, state) {
          final scheme = Theme.of(context).colorScheme;
          final coverSize = (MediaQuery.sizeOf(context).height * .42).clamp(
            180.0,
            360.0,
          );
          return ArtworkBackdrop(
            client: client,
            coverArt: item?.extras?['coverArtId'] as String?,
            child: SafeArea(
              top: false,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'Close player',
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.keyboard_arrow_down_rounded),
                        ),
                        Expanded(
                          child: Center(
                            child: Semantics(
                              header: true,
                              child: Text(
                                'Now playing',
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 48),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 14, 24, 24),
                      child: Column(
                        children: [
                          Center(
                            child: ConstrainedBox(
                              constraints: BoxConstraints(maxWidth: coverSize),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
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
                                  client: client,
                                  id: item?.extras?['coverArtId'] as String?,
                                  radius: 16,
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
                              if (item != null && collections != null) ...[
                                const SizedBox(width: 8),
                                GlassSurface(
                                  radius: 24,
                                  child: FavoriteButton(
                                    collections: collections!,
                                    song: _track(item),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                GlassSurface(
                                  radius: 24,
                                  child: SongActions(
                                    collections: collections!,
                                    song: _track(item),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 16),
                          _volumeSpace(
                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                activeTrackColor: scheme.onSurface,
                                inactiveTrackColor: scheme.onSurface.withValues(
                                  alpha: .25,
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
                                radius: 26,
                                child: IconButton(
                                  tooltip: 'Show queue',
                                  onPressed: () => _showQueue(context),
                                  icon: const Icon(Icons.queue_music_rounded),
                                ),
                              ),
                              GlassSurface(
                                radius: 26,
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
                          _PlayerErrors(playback: playback, state: state),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
}

class _TrackLabels extends StatelessWidget {
  const _TrackLabels({required this.item, this.large = false});
  final MediaItem? item;
  final bool large;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        item?.title ?? 'Nothing playing',
        maxLines: large ? 2 : 1,
        overflow: TextOverflow.ellipsis,
        style: large
            ? Theme.of(context).textTheme.headlineSmall
            : Theme.of(context).textTheme.titleSmall,
      ),
      Text(
        item?.artist ?? '',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    ],
  );
}

class _Previous extends StatelessWidget {
  const _Previous({
    required this.playback,
    required this.state,
    this.large = false,
  });
  final PlaybackService playback;
  final PlaybackState state;
  final bool large;
  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Previous track',
    color: Theme.of(context).colorScheme.onSurface,
    iconSize: large ? 38 : 24,
    onPressed:
        state.controls.contains(MediaControl.skipToPrevious) &&
            state.processingState != AudioProcessingState.error
        ? playback.skipToPrevious
        : null,
    icon: const Icon(Icons.skip_previous_rounded),
  );
}

class _Next extends StatelessWidget {
  const _Next({
    required this.playback,
    required this.state,
    this.large = false,
  });
  final PlaybackService playback;
  final PlaybackState state;
  final bool large;
  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Next track',
    color: Theme.of(context).colorScheme.onSurface,
    iconSize: large ? 38 : 24,
    onPressed:
        state.controls.contains(MediaControl.skipToNext) &&
            state.processingState != AudioProcessingState.error
        ? playback.skipToNext
        : null,
    icon: const Icon(Icons.skip_next_rounded),
  );
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({
    required this.playback,
    required this.item,
    required this.state,
    this.large = false,
  });
  final PlaybackService playback;
  final MediaItem? item;
  final PlaybackState state;
  final bool large;
  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: state.playing ? 'Pause' : 'Play',
    color: Theme.of(context).colorScheme.onSurface,
    iconSize: large ? 64 : 28,
    onPressed:
        item == null || state.processingState == AudioProcessingState.error
        ? null
        : state.playing
        ? playback.pause
        : playback.play,
    icon: Icon(state.playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
  );
}

class _PlayerErrors extends StatelessWidget {
  const _PlayerErrors({required this.playback, required this.state});
  final PlaybackService playback;
  final PlaybackState state;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (state.processingState == AudioProcessingState.error)
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(state.errorMessage ?? 'Playback failed.'),
        ),
      ValueListenableBuilder<String?>(
        valueListenable: playback.settingsError,
        builder: (context, error, _) => error == null
            ? const SizedBox.shrink()
            : Padding(padding: const EdgeInsets.all(12), child: Text(error)),
      ),
    ],
  );
}

class _SeekBar extends StatefulWidget {
  const _SeekBar({
    super.key,
    required this.playback,
    required this.item,
    required this.state,
  });
  final PlaybackService playback;
  final MediaItem? item;
  final PlaybackState state;
  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  double? _drag;
  @override
  Widget build(BuildContext context) => StreamBuilder<Duration>(
    stream: widget.playback.positionStream,
    initialData: widget.playback.position,
    builder: (context, snapshot) {
      final duration = widget.item?.duration ?? Duration.zero;
      final max = duration.inMilliseconds.toDouble();
      final position =
          (_drag ?? (snapshot.data ?? Duration.zero).inMilliseconds.toDouble())
              .clamp(0.0, max > 0 ? max : 1.0);
      final enabled =
          max > 0 && widget.state.processingState == AudioProcessingState.ready;
      return Column(
        children: [
          Slider(
            value: position,
            max: max > 0 ? max : 1,
            semanticFormatterCallback: (value) =>
                '${_time(Duration(milliseconds: value.round()))} of ${_time(duration)}',
            onChanged: enabled
                ? (value) => setState(() => _drag = value)
                : null,
            onChangeEnd: enabled
                ? (value) async {
                    await widget.playback.seek(
                      Duration(milliseconds: value.round()),
                    );
                    if (mounted) setState(() => _drag = null);
                  }
                : null,
          ),
          DefaultTextStyle(
            style: Theme.of(context).textTheme.bodySmall!.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_time(Duration(milliseconds: position.round()))),
                Text(
                  '-${_time(duration - Duration(milliseconds: position.round()))}',
                ),
              ],
            ),
          ),
        ],
      );
    },
  );
}

class _PlaybackView extends StatelessWidget {
  const _PlaybackView({required this.playback, required this.builder});
  final PlaybackService playback;
  final Widget Function(BuildContext, MediaItem?, PlaybackState) builder;
  @override
  Widget build(BuildContext context) => StreamBuilder<MediaItem?>(
    stream: playback.mediaItem,
    initialData: playback.mediaItem.value,
    builder: (context, item) => StreamBuilder<PlaybackState>(
      stream: playback.playbackState,
      initialData: playback.playbackState.value,
      builder: (context, state) => builder(context, item.data, state.data!),
    ),
  );
}
