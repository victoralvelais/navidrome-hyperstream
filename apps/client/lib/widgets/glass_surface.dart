import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

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
    // A light neutral frost improves label contrast without hiding cover colors.
    Color frosted(Color base, double alpha) => Color.alphaBlend(
      scheme.surface.withValues(alpha: .12),
      tinted(base).withValues(alpha: alpha + density),
    );
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
                        frosted(const Color(0xff59616b), .18),
                        frosted(const Color(0xff141a21), .15),
                      ]
                    : [
                        frosted(Colors.white, .30),
                        frosted(const Color(0xfffaf8f3), .22),
                      ],
              )
            : null,
        border: glass ? null : Border.all(color: scheme.outline),
      ),
      child: CustomPaint(
        foregroundPainter: glass
            ? GlassRimPainter(radius: widget.radius, dark: dark)
            : null,
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
      ),
    );
    final blur = ImageFilter.blur(
      sigmaX: widget.prominent ? 5 : 2,
      sigmaY: widget.prominent ? 5 : 2,
    );
    final shader = _shader;
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
            ? shader == null
                  ? BackdropFilter(
                      filter: blur,
                      blendMode: BlendMode.src,
                      child: surface,
                    )
                  : _GlassBackdrop(
                      shader: shader,
                      radius: widget.radius,
                      scale: MediaQuery.devicePixelRatioOf(context),
                      softness: widget.prominent ? 2.5 : 1.0,
                      child: surface,
                    )
            : surface,
      ),
    );
  }
}

/// Backdrop texture coordinates belong to the render target, not this widget.
/// Refresh shape bounds during composition so retained layers also follow
/// scrolling and sheet transitions. Avoid a composed blur's padded input texture.
class _GlassBackdrop extends SingleChildRenderObjectWidget {
  const _GlassBackdrop({
    required this.shader,
    required this.radius,
    required this.scale,
    required this.softness,
    required super.child,
  });
  final FragmentShader shader;
  final double radius, scale, softness;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderGlassBackdrop(shader, radius, scale, softness);
  @override
  void updateRenderObject(
    BuildContext context,
    _RenderGlassBackdrop renderObject,
  ) {
    renderObject
      ..shader = shader
      ..radius = radius
      ..scale = scale
      ..softness = softness
      ..markNeedsPaint();
  }
}

class _RenderGlassBackdrop extends RenderProxyBox {
  _RenderGlassBackdrop(this.shader, this.radius, this.scale, this.softness);
  FragmentShader shader;
  double radius, scale, softness;
  @override
  bool get alwaysNeedsCompositing => child != null;
  @override
  BackdropFilterLayer? get layer => super.layer as BackdropFilterLayer?;
  ImageFilter _filterForScene() {
    final bounds = MatrixUtils.transformRect(
      getTransformTo(null),
      Offset.zero & size,
    );
    final effectScale = size.isEmpty
        ? scale
        : scale * bounds.shortestSide / size.shortestSide;
    shader
      ..setFloat(2, bounds.left * scale)
      ..setFloat(3, bounds.top * scale)
      ..setFloat(4, bounds.width * scale)
      ..setFloat(5, bounds.height * scale)
      ..setFloat(6, radius * effectScale)
      ..setFloat(7, effectScale)
      ..setFloat(8, softness * effectScale);
    return ImageFilter.shader(shader);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    layer ??= _GlassFilterLayer(_filterForScene);
    context.pushLayer(layer!, super.paint, offset);
  }
}

class _GlassFilterLayer extends BackdropFilterLayer {
  // Replace the captured backdrop instead of blending it over itself again in
  // a sheet/menu opacity layer (which can produce doubled translucent content).
  _GlassFilterLayer(this.filterForScene) : super(blendMode: BlendMode.src);
  final ImageFilter Function() filterForScene;
  // A parent's transform can move a retained child without calling its paint.
  @override
  bool get alwaysNeedsAddToScene => true;
  @override
  void addToScene(SceneBuilder builder) {
    filter = filterForScene();
    super.addToScene(builder);
  }
}

/// Directional outer reflection, a dark inner cut, and a softer inner glint.
/// Keeps the bevel readable on renderers without backdrop shader support too.
class GlassRimPainter extends CustomPainter {
  const GlassRimPainter({required this.radius, required this.dark});
  final double radius;
  final bool dark;
  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    void stroke(double inset, double width, List<Color> colors) {
      final r = (radius - inset).clamp(0.0, size.shortestSide / 2);
      if (rect.width <= inset * 2 || rect.height <= inset * 2) return;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.deflate(inset), Radius.circular(r)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
            stops: const [0, .4, .65, 1],
          ).createShader(rect),
      );
    }

    stroke(.7, 1.3, [
      Colors.white.withValues(alpha: dark ? .68 : .95),
      Colors.white.withValues(alpha: .12),
      Colors.black.withValues(alpha: dark ? .22 : .18),
      Colors.white.withValues(alpha: .52),
    ]);
    stroke(2, 1.2, [
      Colors.black.withValues(alpha: .22),
      Colors.black.withValues(alpha: .06),
      Colors.white.withValues(alpha: .06),
      Colors.white.withValues(alpha: .27),
    ]);
    stroke(3.8, 2.2, [
      Colors.white.withValues(alpha: .10),
      Colors.transparent,
      Colors.transparent,
      Colors.white.withValues(alpha: .10),
    ]);
  }

  @override
  bool shouldRepaint(GlassRimPainter oldDelegate) =>
      radius != oldDelegate.radius || dark != oldDelegate.dark;
}
