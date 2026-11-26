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
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = switch (sourceId) {
      'mornye:spotify-web' => Color(dark ? 0xFF1ED760 : 0xFF008A3E),
      'mornye:soundcloud' => const Color(0xFFFF5500),
      'mornye:ytmusic-spotiflac' => const Color(0xFFFF0033),
      'mornye:qobuz-web' => Color(dark ? 0xFF79B4FF : 0xFF2165BA),
      // TIDAL's identity is monochrome; keep contrast in both themes.
      'mornye:tidal-web' => Theme.of(context).colorScheme.onSurface,
      _ => Theme.of(context).colorScheme.primary,
    };
    return Tooltip(
      message: 'Source: $name',
      excludeFromSemantics: true,
      child: Semantics(
        label: 'Source: $name',
        child: ExcludeSemantics(
          child: SizedBox.square(
            dimension: size,
            child: sourceId == 'navidrome'
                ? Icon(Icons.library_music_rounded, size: size, color: color)
                : slug == null
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
