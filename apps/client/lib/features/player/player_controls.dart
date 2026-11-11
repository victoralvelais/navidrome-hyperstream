import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import '../../models/library.dart';
import '../../services/library_collections.dart';
import '../../services/navidrome_client.dart';
import '../../services/playback_service.dart';
import '../library/cover_art.dart';
import '../library/artwork_backdrop.dart';
import '../library/collection_actions.dart';
import '../../widgets/glass_surface.dart';
import 'volume_controls.dart';

String _time(Duration value) =>
    '${value.inMinutes}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';

class PlayerControls extends StatefulWidget {
  const PlayerControls({
    super.key,
    required this.playback,
    required this.client,
    this.collections,
  });
  final PlaybackService playback;
  final NavidromeClient client;
  final LibraryCollections? collections;

  @override
  State<PlayerControls> createState() => _PlayerControlsState();
}

class _PlayerControlsState extends State<PlayerControls> {
  bool _showVolume = false;

  void _openPlayer() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    showDragHandle: false,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (context) => _NowPlaying(
      playback: widget.playback,
      client: widget.client,
      collections: widget.collections,
    ),
  );

  @override
  Widget build(BuildContext context) => _PlaybackView(
    playback: widget.playback,
    builder: (context, item, state) {
      if (item == null && state.processingState != AudioProcessingState.error) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
        child: GlassSurface(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: _openPlayer,
                        borderRadius: BorderRadius.circular(12),
                        child: Semantics(
                          button: true,
                          label: 'Open now playing',
                          child: Row(
                            children: [
                              SizedBox(
                                width: 48,
                                height: 48,
                                child: CoverArt(
                                  client: widget.client,
                                  id: item?.extras?['coverArtId'] as String?,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(child: _TrackLabels(item: item)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    _PlayButton(
                      playback: widget.playback,
                      item: item,
                      state: state,
                    ),
                    IconButton(
                      tooltip: 'Next track',
                      onPressed:
                          state.controls.contains(MediaControl.skipToNext) &&
                              state.processingState !=
                                  AudioProcessingState.error
                          ? widget.playback.skipToNext
                          : null,
                      icon: const Icon(Icons.skip_next_rounded),
                    ),
                    ListenableBuilder(
                      listenable: widget.playback.preferences,
                      builder: (context, _) => IconButton(
                        tooltip: _showVolume
                            ? 'Hide music volume'
                            : 'Show music volume',
                        isSelected: _showVolume,
                        onPressed: () =>
                            setState(() => _showVolume = !_showVolume),
                        icon: Icon(
                          widget.playback.preferences.volume == 0
                              ? Icons.volume_off_rounded
                              : Icons.volume_up_rounded,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_showVolume)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 18, 4),
                  child: Column(
                    children: [
                      Text(
                        'Music volume',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      VolumeControls(playback: widget.playback),
                    ],
                  ),
                ),
              if (state.processingState == AudioProcessingState.error)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(state.errorMessage ?? 'Playback failed.'),
                ),
              ValueListenableBuilder<String?>(
                valueListenable: widget.playback.settingsError,
                builder: (context, error, _) => error == null
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(error),
                      ),
              ),
              StreamBuilder<Duration>(
                stream: widget.playback.positionStream,
                initialData: widget.playback.position,
                builder: (context, snapshot) {
                  final duration = item?.duration?.inMilliseconds ?? 0;
                  final busy =
                      state.processingState == AudioProcessingState.loading ||
                      state.processingState == AudioProcessingState.buffering;
                  return LinearProgressIndicator(
                    minHeight: 2,
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
  bool _showVolume = false;

  Track _track(MediaItem item) => Track(
    id: item.id,
    title: item.title,
    artist: item.artist ?? 'Unknown artist',
    album: item.album ?? 'Unknown album',
    duration: item.duration ?? Duration.zero,
    coverArt: item.extras?['coverArtId'] as String?,
    starred: item.extras?['starred'] as bool? ?? false,
  );

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    heightFactor: .94,
    child: ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      child: _PlaybackView(
        playback: widget.playback,
        builder: (context, item, state) {
          final scheme = Theme.of(context).colorScheme;
          final coverSize = (MediaQuery.sizeOf(context).height * .35).clamp(
            180.0,
            340.0,
          );
          return ArtworkBackdrop(
            client: widget.client,
            coverArt: item?.extras?['coverArtId'] as String?,
            child: SafeArea(
              top: false,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 14, 16, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Now playing',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        GlassSurface(
                          radius: 24,
                          child: IconButton(
                            tooltip: 'Close player',
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.keyboard_arrow_down_rounded),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
                      child: Column(
                        children: [
                          Center(
                            child: ConstrainedBox(
                              constraints: BoxConstraints(maxWidth: coverSize),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(22),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: .24,
                                      ),
                                      blurRadius: 32,
                                      offset: const Offset(0, 16),
                                    ),
                                  ],
                                ),
                                child: CoverArt(
                                  client: widget.client,
                                  id: item?.extras?['coverArtId'] as String?,
                                  radius: 22,
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
                              if (item != null &&
                                  widget.collections != null) ...[
                                const SizedBox(width: 12),
                                GlassSurface(
                                  radius: 26,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      FavoriteButton(
                                        collections: widget.collections!,
                                        song: _track(item),
                                      ),
                                      SongActions(
                                        collections: widget.collections!,
                                        song: _track(item),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 14),
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              activeTrackColor: scheme.onSurface,
                              inactiveTrackColor: scheme.onSurface.withValues(
                                alpha: .15,
                              ),
                              thumbColor: scheme.onSurface,
                              thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 5,
                              ),
                            ),
                            child: _SeekBar(
                              key: ValueKey(item?.id),
                              playback: widget.playback,
                              item: item,
                              state: state,
                            ),
                          ),
                          const SizedBox(height: 20),
                          GlassSurface(
                            radius: 40,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: [
                                  IconButton(
                                    tooltip: 'Previous track',
                                    iconSize: 34,
                                    onPressed:
                                        state.controls.contains(
                                              MediaControl.skipToPrevious,
                                            ) &&
                                            state.processingState !=
                                                AudioProcessingState.error
                                        ? widget.playback.skipToPrevious
                                        : null,
                                    icon: const Icon(
                                      Icons.skip_previous_rounded,
                                    ),
                                  ),
                                  _PlayButton(
                                    playback: widget.playback,
                                    item: item,
                                    state: state,
                                    large: true,
                                  ),
                                  IconButton(
                                    tooltip: 'Next track',
                                    iconSize: 34,
                                    onPressed:
                                        state.controls.contains(
                                              MediaControl.skipToNext,
                                            ) &&
                                            state.processingState !=
                                                AudioProcessingState.error
                                        ? widget.playback.skipToNext
                                        : null,
                                    icon: const Icon(Icons.skip_next_rounded),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextButton.icon(
                            onPressed: () =>
                                setState(() => _showVolume = !_showVolume),
                            icon: Icon(
                              _showVolume
                                  ? Icons.expand_less_rounded
                                  : Icons.volume_up_rounded,
                            ),
                            label: Text(
                              _showVolume
                                  ? 'Hide music volume'
                                  : 'Music volume',
                            ),
                          ),
                          if (_showVolume)
                            GlassSurface(
                              radius: 24,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  4,
                                  4,
                                  16,
                                  12,
                                ),
                                child: Column(
                                  children: [
                                    VolumeControls(playback: widget.playback),
                                    Text(
                                      'Adjusts Hyperstream only',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          if (state.processingState ==
                              AudioProcessingState.error)
                            Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: Text(
                                state.errorMessage ?? 'Playback failed.',
                              ),
                            ),
                          ValueListenableBuilder<String?>(
                            valueListenable: widget.playback.settingsError,
                            builder: (context, error, _) => error == null
                                ? const SizedBox.shrink()
                                : Text(error),
                          ),
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
        style: TextStyle(
          color: large
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ],
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
    style: large
        ? IconButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.onSurface,
            foregroundColor: Theme.of(context).colorScheme.surface,
            padding: const EdgeInsets.all(6),
          )
        : null,
    tooltip: state.playing ? 'Pause' : 'Play',
    iconSize: large ? 52 : 32,
    onPressed:
        item == null || state.processingState == AudioProcessingState.error
        ? null
        : state.playing
        ? playback.pause
        : playback.play,
    icon: Icon(state.playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_time(Duration(milliseconds: position.round()))),
              Text(_time(duration)),
            ],
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
