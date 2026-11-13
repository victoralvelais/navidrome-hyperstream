import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
import 'player_actions.dart';
import '../../widgets/glass_overlays.dart';
import '../../widgets/edge_back_gesture.dart';
import '../playlists/playlist_dialogs.dart';

part 'now_playing_part.dart';

String _time(Duration value) =>
    '${value.inMinutes}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';

class PlayerControls extends StatelessWidget {
  const PlayerControls({
    super.key,
    required this.playback,
    required this.client,
    this.collections,
    this.compact = false,
    this.onAlbum,
    this.onArtist,
  });
  final PlaybackService playback;
  final NavidromeClient client;
  final LibraryCollections? collections;
  final bool compact;
  final ValueChanged<Album>? onAlbum;
  final ValueChanged<Artist>? onArtist;

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
      final media = MediaQuery.of(context);
      final labels = InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          useSafeArea: false,
          backgroundColor: Colors.transparent,
          showDragHandle: false,
          constraints: const BoxConstraints(maxWidth: 560),
          builder: (_) => MediaQuery(
            data: media,
            child: _NowPlaying(
              playback: playback,
              client: client,
              collections: collections,
              onAlbum: onAlbum,
              onArtist: onArtist,
            ),
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
                padding: EdgeInsets.fromLTRB(compact ? 18 : 12, 8, 12, 8),
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
        maxLines: large
            ? (MediaQuery.textScalerOf(context).scale(1) > 1.2 ? 3 : 2)
            : 1,
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
    onPressed: item == null && !playback.canRetryPlayback
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
      if (playback.reconnecting)
        TextButton(
          onPressed: playback.pause,
          child: const Text('Stop retrying'),
        ),
      ValueListenableBuilder<String?>(
        valueListenable: playback.settingsError,
        builder: (context, error, _) => error == null
            ? const SizedBox.shrink()
            : Padding(padding: const EdgeInsets.all(12), child: Text(error)),
      ),
      ValueListenableBuilder<String?>(
        valueListenable: playback.continuityNotice,
        builder: (context, notice, _) => notice == null
            ? const SizedBox.shrink()
            : Padding(padding: const EdgeInsets.all(12), child: Text(notice)),
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
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      widget.item?.extras?['audioDetails'] as String? ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
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
