import 'package:flutter/material.dart';

/// The four colors the screen is painted with, pulled from the album artwork.
///
/// * [accent] – light, readable tint for glows, the AirPlay icon, active toggles.
/// * [blob1]..[blob3] – saturated mid tones for the moving aurora.
/// * [deep] – near-black base, tinted toward the album.
@immutable
class AlbumPalette {
  const AlbumPalette({
    required this.accent,
    required this.blob1,
    required this.blob2,
    required this.blob3,
    required this.deep,
  });

  static const fallback = AlbumPalette(
    accent: Color(0xFFF2A7C0),
    blob1: Color(0xFF8B6FD6),
    blob2: Color(0xFFF2A7C0),
    blob3: Color(0xFFF5C451),
    deep: Color(0xFF120A14),
  );

  final Color accent;
  final Color blob1;
  final Color blob2;
  final Color blob3;
  final Color deep;

  /// Builds a palette from artwork using Flutter's built-in Material color
  /// extraction (no extra package needed).
  static Future<AlbumPalette> fromImage(ImageProvider image) async {
    try {
      final scheme = await ColorScheme.fromImageProvider(
        provider: image,
        brightness: Brightness.dark,
      );
      Color tone(Color c, double lightness, double minSaturation) {
        final hsl = HSLColor.fromColor(c);
        return hsl
            .withLightness(lightness)
            .withSaturation(
              hsl.saturation < minSaturation ? minSaturation : hsl.saturation,
            )
            .toColor();
      }

      return AlbumPalette(
        accent: scheme.primary,
        blob1: tone(scheme.secondary, 0.55, 0.45),
        blob2: tone(scheme.primary, 0.62, 0.55),
        blob3: tone(scheme.tertiary, 0.68, 0.55),
        deep: tone(scheme.primary, 0.06, 0.35),
      );
    } catch (_) {
      return fallback;
    }
  }

  static AlbumPalette lerp(AlbumPalette a, AlbumPalette b, double t) =>
      AlbumPalette(
        accent: Color.lerp(a.accent, b.accent, t)!,
        blob1: Color.lerp(a.blob1, b.blob1, t)!,
        blob2: Color.lerp(a.blob2, b.blob2, t)!,
        blob3: Color.lerp(a.blob3, b.blob3, t)!,
        deep: Color.lerp(a.deep, b.deep, t)!,
      );

  @override
  bool operator ==(Object other) =>
      other is AlbumPalette &&
      other.accent == accent &&
      other.blob1 == blob1 &&
      other.blob2 == blob2 &&
      other.blob3 == blob3 &&
      other.deep == deep;

  @override
  int get hashCode => Object.hash(accent, blob1, blob2, blob3, deep);
}

/// Lets [TweenAnimationBuilder] cross-fade between album palettes on skip.
class AlbumPaletteTween extends Tween<AlbumPalette> {
  AlbumPaletteTween({super.begin, super.end});

  @override
  AlbumPalette lerp(double t) => AlbumPalette.lerp(begin!, end!, t);
}
