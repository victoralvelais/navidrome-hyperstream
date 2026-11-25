import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Provider identity stays recognizable when the app's action icon style changes.
class MusicSourceIcon extends StatelessWidget {
  const MusicSourceIcon({
    super.key,
    required this.sourceId,
    required this.name,
    this.size = 18,
  });
  final String sourceId, name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final slug = switch (sourceId) {
      'mornye:spotify-web' => 'spotify',
      'mornye:soundcloud' => 'soundcloud',
      'mornye:ytmusic-spotiflac' => 'youtube',
      'mornye:tidal-web' => 'tidal',
      _ => null,
    };
    final color = Theme.of(context).colorScheme.onSurface;
    return Tooltip(
      message: 'Source: $name',
      excludeFromSemantics: true,
      child: Semantics(
        label: 'Source: $name',
        child: ExcludeSemantics(
          child: SizedBox.square(
            dimension: size,
            child: slug == null
                ? Center(
                    child: Text(
                      sourceId == 'mornye:qobuz-web' ? 'Q' : 'M',
                      style: TextStyle(
                        fontSize: size * .8,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                  )
                : SvgPicture.asset(
                    'assets/icons/sources/$slug.svg',
                    colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
                  ),
          ),
        ),
      ),
    );
  }
}
