import 'package:flutter/material.dart';

import '../../services/playback_service.dart';
import '../../widgets/glass_surface.dart';
import 'output_button.dart';
import 'tempo_button.dart';
import 'volume_button.dart';

class PlaybackSettingsGroup extends StatefulWidget {
  const PlaybackSettingsGroup({
    super.key,
    required this.playback,
    this.onExpandedChanged,
    this.onVolumeExpandedChanged,
  });
  final PlaybackService playback;
  final ValueChanged<bool>? onExpandedChanged;
  final ValueChanged<bool>? onVolumeExpandedChanged;

  @override
  State<PlaybackSettingsGroup> createState() => _PlaybackSettingsGroupState();
}

class _PlaybackSettingsGroupState extends State<PlaybackSettingsGroup> {
  bool _obscured = false;

  void _expanded(bool open) {
    setState(() => _obscured = open);
    widget.onExpandedChanged?.call(open);
  }

  @override
  Widget build(BuildContext context) => GlassSurface(
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TempoButton(playback: widget.playback, onExpandedChanged: _expanded),
        OutputButton(obscured: _obscured),
        VolumeButton(
          playback: widget.playback,
          onExpandedChanged: (open) {
            _expanded(open);
            widget.onVolumeExpandedChanged?.call(open);
          },
        ),
      ],
    ),
  );
}
