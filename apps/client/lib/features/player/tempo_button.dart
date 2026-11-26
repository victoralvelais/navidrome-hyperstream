import 'package:hyperstream_client/widgets/app_icon.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import '../../services/playback_service.dart';
import '../../widgets/glass_overlays.dart';

class TempoButton extends StatelessWidget {
  const TempoButton({
    super.key,
    required this.playback,
    this.onExpandedChanged,
  });

  final PlaybackService playback;
  final ValueChanged<bool>? onExpandedChanged;

  @override
  Widget build(BuildContext context) => StreamBuilder<PlaybackState>(
    stream: playback.playbackState,
    initialData: playback.playbackState.value,
    builder: (context, snapshot) => GlassPopupMenuButton<void>(
      tooltip: 'Playback tempo',
      enabled: playback.mediaItem.value != null,
      onOpened: () => onExpandedChanged?.call(true),
      onCanceled: () => onExpandedChanged?.call(false),
      itemBuilder: (_) => [
        GlassMenuContent<void>(child: _TempoControls(playback: playback)),
      ],
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 56, minHeight: 44),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Center(
            child: Text(
              '${(snapshot.data?.speed ?? 1).toStringAsFixed(2)}×',
              style: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
    ),
  );
}

class _TempoControls extends StatelessWidget {
  const _TempoControls({required this.playback});
  final PlaybackService playback;

  @override
  Widget build(BuildContext context) => StreamBuilder<PlaybackState>(
    stream: playback.playbackState,
    initialData: playback.playbackState.value,
    builder: (context, snapshot) {
      final speed = (snapshot.data?.speed ?? 1).clamp(.5, 2.0);
      final enabled = playback.mediaItem.value != null;
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Tempo',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton(
                  onPressed: enabled ? () => playback.setSpeed(1) : null,
                  child: const Text('Reset 1×'),
                ),
              ],
            ),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final preset in [.5, .75, 1.0, 1.25, 1.5, 2.0])
                  ChoiceChip(
                    label: Text('${preset.toStringAsFixed(2)}×'),
                    selected: (speed - preset).abs() < .001,
                    showCheckmark: false,
                    onSelected: enabled
                        ? (_) => playback.setSpeed(preset)
                        : null,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton(
                  tooltip: 'Decrease tempo by 0.01',
                  onPressed: enabled && speed > .5
                      ? () => playback.adjustSpeed(-.01)
                      : null,
                  icon: const AppIcon(Icons.remove),
                ),
                Expanded(
                  child: Text(
                    '${speed.toStringAsFixed(2)}×',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Increase tempo by 0.01',
                  onPressed: enabled && speed < 2
                      ? () => playback.adjustSpeed(.01)
                      : null,
                  icon: const AppIcon(Icons.add),
                ),
              ],
            ),
            Slider(
              key: const ValueKey('tempo-slider'),
              value: speed,
              min: .5,
              max: 2,
              divisions: 150,
              label: '${speed.toStringAsFixed(2)}×',
              semanticFormatterCallback: (value) =>
                  'Tempo ${value.toStringAsFixed(2)} times normal',
              onChanged: enabled ? playback.setSpeed : null,
            ),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [Text('0.50×'), Text('2.00×')],
            ),
            ListenableBuilder(
              listenable: playback.preferences,
              builder: (context, _) => SwitchListTile.adaptive(
                key: const ValueKey('keep-pitch-toggle'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Keep pitch'),
                subtitle: Text(
                  !playback.supportsPitchControl
                      ? 'Pitch control is not available on Windows yet'
                      : playback.preferences.keepPitch
                      ? 'Original pitch at every speed'
                      : 'Pitch changes with speed',
                ),
                value:
                    !playback.supportsPitchControl ||
                    playback.preferences.keepPitch,
                onChanged: enabled && playback.supportsPitchControl
                    ? playback.setKeepPitch
                    : null,
              ),
            ),
            ValueListenableBuilder<String?>(
              valueListenable: playback.settingsError,
              builder: (context, error, _) => error == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Semantics(liveRegion: true, child: Text(error)),
                    ),
            ),
          ],
        ),
      );
    },
  );
}
