import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import '../../services/playback_service.dart';

class PlayerControls extends StatelessWidget {
  const PlayerControls({super.key, required this.playback});
  final PlaybackService playback;

  String _time(Duration value) =>
      '${value.inMinutes}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) => StreamBuilder<MediaItem?>(
    stream: playback.mediaItem,
    initialData: playback.mediaItem.value,
    builder: (context, itemSnapshot) => StreamBuilder<PlaybackState>(
      stream: playback.playbackState,
      initialData: playback.playbackState.value,
      builder: (context, stateSnapshot) {
        final item = itemSnapshot.data;
        final state = stateSnapshot.data!;
        final busy =
            state.processingState == AudioProcessingState.loading ||
            state.processingState == AudioProcessingState.buffering;
        final failed = state.processingState == AudioProcessingState.error;
        if (item == null && !busy && !failed) return const SizedBox.shrink();
        return Material(
          color: Theme.of(context).colorScheme.surfaceContainer,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (busy) const LinearProgressIndicator(),
                if (failed) Text(state.errorMessage ?? 'Playback failed.'),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item?.title ?? 'Loading…',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          Text(
                            item?.artist ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Previous track',
                      icon: const Icon(Icons.skip_previous),
                      onPressed:
                          state.controls.contains(
                                MediaControl.skipToPrevious,
                              ) &&
                              !failed
                          ? playback.skipToPrevious
                          : null,
                    ),
                    IconButton.filled(
                      tooltip: state.playing ? 'Pause' : 'Play',
                      icon: Icon(
                        state.playing ? Icons.pause : Icons.play_arrow,
                      ),
                      onPressed: item == null || failed
                          ? null
                          : state.playing
                          ? playback.pause
                          : playback.play,
                    ),
                    IconButton(
                      tooltip: 'Next track',
                      icon: const Icon(Icons.skip_next),
                      onPressed:
                          state.controls.contains(MediaControl.skipToNext) &&
                              !failed
                          ? playback.skipToNext
                          : null,
                    ),
                  ],
                ),
                StreamBuilder<Duration>(
                  stream: playback.positionStream,
                  initialData: playback.position,
                  builder: (context, snapshot) {
                    final duration = item?.duration ?? Duration.zero;
                    final max = duration.inMilliseconds.toDouble();
                    final position = busy
                        ? Duration.zero
                        : snapshot.data ?? Duration.zero;
                    return Row(
                      children: [
                        Text(_time(position)),
                        Expanded(
                          child: Slider(
                            value: position.inMilliseconds.toDouble().clamp(
                              0,
                              max > 0 ? max : 1,
                            ),
                            max: max > 0 ? max : 1,
                            label: _time(position),
                            onChanged: max <= 0 || busy || failed
                                ? null
                                : (value) => playback.seek(
                                    Duration(milliseconds: value.round()),
                                  ),
                          ),
                        ),
                        Text(_time(duration)),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
