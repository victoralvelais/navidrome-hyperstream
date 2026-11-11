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

class GlassSurface extends StatelessWidget {
  const GlassSurface({super.key, required this.child, this.radius = 28});
  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    final glass = GlassScope.effectsEnabled(context);
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
                        const Color(0xff41414b).withValues(alpha: .84),
                        const Color(0xff202027).withValues(alpha: .82),
                      ]
                    : [
                        Colors.white.withValues(alpha: .92),
                        const Color(0xfff2eef5).withValues(alpha: .86),
                      ],
              )
            : null,
        border: Border.all(
          color: glass
              ? Colors.white.withValues(alpha: dark ? .22 : .9)
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
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: surface,
              )
            : surface,
      ),
    );
  }
}
