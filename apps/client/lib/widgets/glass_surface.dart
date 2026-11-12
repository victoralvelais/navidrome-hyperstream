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

class GlassSurface extends StatefulWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.radius = 28,
    this.prominent = false,
  });
  final Widget child;
  final double radius;
  final bool prominent;

  @override
  State<GlassSurface> createState() => _GlassSurfaceState();
}

class _GlassSurfaceState extends State<GlassSurface> {
  static Future<FragmentProgram?>? _program;
  FragmentShader? _shader;

  @override
  void initState() {
    super.initState();
    if (ImageFilter.isShaderFilterSupported) {
      _program ??= FragmentProgram.fromAsset('shaders/glass.frag')
          .then<FragmentProgram?>((program) => program)
          .catchError((Object _) => null);
      _program!.then((program) {
        if (mounted && program != null) {
          setState(() => _shader = program.fragmentShader());
        }
      });
    }
  }

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    final glass = GlassScope.effectsEnabled(context);
    final tint = ArtworkTint.of(context);
    Color tinted(Color base) =>
        tint == null ? base : Color.lerp(base, tint, dark ? .35 : .16)!;
    final corners = BorderRadius.circular(widget.radius);
    final density = widget.prominent ? .18 : 0.0;
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
                        tinted(const Color(0xff59616b))
                            .withValues(alpha: .18 + density),
                        tinted(const Color(0xff141a21))
                            .withValues(alpha: .15 + density),
                      ]
                    : [
                        tinted(Colors.white).withValues(alpha: .30 + density),
                        tinted(const Color(0xfffaf8f3))
                            .withValues(alpha: .22 + density),
                      ],
              )
            : null,
        border: Border.all(
          color: glass
              ? Colors.white.withValues(alpha: dark ? .34 : .80)
              : scheme.outline,
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          colorScheme: scheme.copyWith(
            // A translucent sheet can sit over a dimmed cover in either theme.
            // Keep secondary labels legible instead of using mid-gray on gray.
            onSurfaceVariant: scheme.onSurface.withValues(alpha: .82),
          ),
        ),
        child: Material(type: MaterialType.transparency, child: widget.child),
      ),
    );
    final blur = ImageFilter.blur(
      sigmaX: widget.prominent ? 10 : 4,
      sigmaY: widget.prominent ? 10 : 4,
    );
    final shader = _shader;
    if (shader != null) {
      final scale = MediaQuery.devicePixelRatioOf(context);
      shader.setFloat(2, widget.radius * scale);
      shader.setFloat(3, scale);
    }
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
                filter: shader == null
                    ? blur
                    : ImageFilter.compose(
                        outer: ImageFilter.shader(shader),
                        inner: ImageFilter.blur(
                          sigmaX: widget.prominent ? 6 : 1.5,
                          sigmaY: widget.prominent ? 6 : 1.5,
                        ),
                      ),
                child: surface,
              )
            : surface,
      ),
    );
  }
}
