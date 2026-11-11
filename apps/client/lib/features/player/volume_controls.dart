import 'package:flutter/material.dart';

import '../../services/playback_service.dart';

class VolumeControls extends StatelessWidget {
  const VolumeControls({super.key, required this.playback});
  final PlaybackService playback;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: playback.preferences,
    builder: (context, _) {
      final volume = playback.preferences.volume;
      return Row(
        children: [
          IconButton(
            tooltip: volume == 0 ? 'Unmute music' : 'Mute music',
            onPressed: playback.toggleMute,
            icon: Icon(
              volume == 0
                  ? Icons.volume_off_rounded
                  : Icons.volume_down_rounded,
            ),
          ),
          Expanded(
            child: Slider(
              value: volume,
              label: '${(volume * 100).round()}%',
              semanticFormatterCallback: (value) =>
                  'Music volume ${(value * 100).round()} percent',
              onChanged: playback.setAppVolume,
            ),
          ),
          SizedBox(
            width: 46,
            child: Text('${(volume * 100).round()}%', textAlign: TextAlign.end),
          ),
        ],
      );
    },
  );
}
