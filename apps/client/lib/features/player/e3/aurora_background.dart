import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'album_palette.dart';

/// Slowly orbiting, drifting blobs of album colour, heavily blurred.
/// Pauses whenever [running] is false (music paused or reduced motion).
class AuroraBackground extends StatefulWidget {
  const AuroraBackground({
    super.key,
    required this.palette,
    required this.running,
  });

  final AlbumPalette palette;
  final bool running;

  @override
  State<AuroraBackground> createState() => _AuroraBackgroundState();
}

class _AuroraBackgroundState extends State<AuroraBackground>
    with TickerProviderStateMixin {
  late final AnimationController _orbit = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 28),
  );
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 11),
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(AuroraBackground old) {
    super.didUpdateWidget(old);
    if (old.running != widget.running) _sync();
  }

  void _sync() {
    if (widget.running) {
      _orbit.repeat();
      _drift.repeat(reverse: true);
    } else {
      _orbit.stop();
      _drift.stop();
    }
  }

  @override
  void dispose() {
    _orbit.dispose();
    _drift.dispose();
    super.dispose();
  }

  Widget _blob(
    double left,
    double top,
    double size,
    Color color,
    double opacity,
  ) => Positioned(
    left: left,
    top: top,
    child: Opacity(
      opacity: opacity,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: p.deep),
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(
              sigmaX: 60,
              sigmaY: 60,
              tileMode: TileMode.decal,
            ),
            child: AnimatedBuilder(
              animation: Listenable.merge([_orbit, _drift]),
              builder: (context, _) {
                final d = Curves.easeInOut.transform(_drift.value);
                return OverflowBox(
                  minWidth: 790,
                  minHeight: 790,
                  maxWidth: 790,
                  maxHeight: 790,
                  child: Transform.rotate(
                    angle: _orbit.value * 2 * math.pi,
                    child: SizedBox(
                      width: 790,
                      height: 790,
                      child: Stack(
                        children: [
                          _blob(
                            180 + 60 * d,
                            120 + 90 * d,
                            340 * (1 + .25 * d),
                            p.blob1,
                            .85,
                          ),
                          _blob(
                            360 - 80 * d,
                            300 - 40 * d,
                            300 * (1.1 - .25 * d),
                            p.blob2,
                            .7,
                          ),
                          _blob(
                            220 + 40 * (1 - d),
                            420 - 60 * d,
                            220,
                            p.blob3,
                            .45,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x0D000000),
                  Color(0x59000000),
                  Color(0xBF000000),
                ],
                stops: [0, .55, 1],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
