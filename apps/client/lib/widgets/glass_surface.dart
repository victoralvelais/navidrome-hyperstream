import 'dart:ui';

import 'package:flutter/material.dart';

/// Shared Flutter material, inspired by Liquid Glass; no native-view dependency.
/// Keep blur bounded to controls, rather than applying it to every content row.
class GlassScope extends InheritedWidget {
  const GlassScope({super.key, required this.enabled, required super.child});
  final bool enabled;

  static bool effectsEnabled(BuildContext context) =>
      (context.dependOnInheritedWidgetOfExactType<GlassScope>()?.enabled ??
          true) &&
      !MediaQuery.highContrastOf(context);

  @override
  bool updateShouldNotify(GlassScope oldWidget) => enabled != oldWidget.enabled;
}

/// Artwork tint flows through the full page and its floating controls.
class ArtworkTint extends InheritedWidget {
  const ArtworkTint({super.key, required this.color, required super.child});
  final Color? color;
  static Color? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ArtworkTint>()?.color;
  @override
  bool updateShouldNotify(ArtworkTint oldWidget) => color != oldWidget.color;
}

class GlassSurface extends StatelessWidget {
  const GlassSurface({super.key, required this.child, this.radius = 28});
  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    final glass = GlassScope.effectsEnabled(context);
    final tint = ArtworkTint.of(context);
    Color tinted(Color base) =>
        tint == null ? base : Color.lerp(base, tint, dark ? .35 : .16)!;
    final corners = BorderRadius.circular(radius);
    final surface = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: corners,
        color: glass ? null : scheme.surfaceContainer,
        gradient: glass
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: dark
                    ? [
                        tinted(const Color(0xff59616b)).withValues(alpha: .46),
                        tinted(const Color(0xff141a21)).withValues(alpha: .42),
                      ]
                    : [
                        tinted(Colors.white).withValues(alpha: .72),
                        tinted(const Color(0xfffaf8f3)).withValues(alpha: .56),
                      ],
              )
            : null,
        border: Border.all(
          color: glass
              ? Colors.white.withValues(alpha: dark ? .36 : .95)
              : scheme.outline,
        ),
      ),
      child: Material(type: MaterialType.transparency, child: child),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: corners,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? .18 : .07),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: corners,
        child: glass
            ? BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: surface,
              )
            : surface,
      ),
    );
  }
}
