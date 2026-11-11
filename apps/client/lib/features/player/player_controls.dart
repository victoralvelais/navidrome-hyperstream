import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import '../../services/navidrome_client.dart';
import '../../services/playback_service.dart';
import '../library/cover_art.dart';
import 'volume_controls.dart';

String _time(Duration value) =>
    '${value.inMinutes}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';

class PlayerControls extends StatefulWidget {
  const PlayerControls({
    super.key,
    required this.playback,
    required this.client,
  });
  final PlaybackService playback;
  final NavidromeClient client;

  @override
  State<PlayerControls> createState() => _PlayerControlsState();
}

class _PlayerControlsState extends State<PlayerControls> {
  bool _showVolume = false;

  void _openPlayer() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (context) =>
        _NowPlaying(playback: widget.playback, client: widget.client),
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
        child: Material(
          color: Theme.of(context).colorScheme.surfaceContainer,
          elevation: 4,
          shadowColor: Colors.black26,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
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
                  child: VolumeControls(playback: widget.playback),
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

class _NowPlaying extends StatelessWidget {
  const _NowPlaying({required this.playback, required this.client});
  final PlaybackService playback;
  final NavidromeClient client;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
      child: _PlaybackView(
        playback: playback,
        builder: (context, item, state) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Now playing',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Close player',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.keyboard_arrow_down_rounded),
                ),
              ],
            ),
            const SizedBox(height: 24),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 28,
                      offset: Offset(0, 12),
                    ),
                  ],
                ),
                child: CoverArt(
                  client: client,
                  id: item?.extras?['coverArtId'] as String?,
                ),
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: _TrackLabels(item: item, large: true),
            ),
            const SizedBox(height: 16),
            _SeekBar(
              key: ValueKey(item?.id),
              playback: playback,
              item: item,
              state: state,
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  tooltip: 'Previous track',
                  iconSize: 36,
                  onPressed:
                      state.controls.contains(MediaControl.skipToPrevious) &&
                          state.processingState != AudioProcessingState.error
                      ? playback.skipToPrevious
                      : null,
                  icon: const Icon(Icons.skip_previous_rounded),
                ),
                _PlayButton(
                  playback: playback,
                  item: item,
                  state: state,
                  large: true,
                ),
                IconButton(
                  tooltip: 'Next track',
                  iconSize: 36,
                  onPressed:
                      state.controls.contains(MediaControl.skipToNext) &&
                          state.processingState != AudioProcessingState.error
                      ? playback.skipToNext
                      : null,
                  icon: const Icon(Icons.skip_next_rounded),
                ),
              ],
            ),
            const SizedBox(height: 24),
            VolumeControls(playback: playback),
            Text(
              'Music volume',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            if (state.processingState == AudioProcessingState.error)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(state.errorMessage ?? 'Playback failed.'),
              ),
            ValueListenableBuilder<String?>(
              valueListenable: playback.settingsError,
              builder: (context, error, _) =>
                  error == null ? const SizedBox.shrink() : Text(error),
            ),
          ],
        ),
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
    tooltip: state.playing ? 'Pause' : 'Play',
    iconSize: large ? 64 : 32,
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
