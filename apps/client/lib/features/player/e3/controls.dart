import 'package:flutter/material.dart';

import '../../../widgets/app_icon.dart';
import '../../../widgets/glass_surface.dart';
import 'album_palette.dart';

/// The native Flutter slider retains keyboard, screen reader and drag support;
/// only its painted track is replaced with the handoff's glowing gradient.
class GlowSlider extends StatefulWidget {
  const GlowSlider({
    super.key,
    required this.value,
    required this.onChanged,
    required this.palette,
    required this.label,
    this.onChangeEnd,
    this.semanticFormatter,
    this.shimmer = false,
    this.running = false,
  });
  final double value;
  final ValueChanged<double>? onChanged, onChangeEnd;
  final AlbumPalette palette;
  final String label;
  final String Function(double)? semanticFormatter;
  final bool shimmer, running;
  @override
  State<GlowSlider> createState() => _GlowSliderState();
}

class _GlowSliderState extends State<GlowSlider>
    with SingleTickerProviderStateMixin {
  late final _shimmer = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  );
  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(GlowSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (widget.running && widget.shimmer) {
      if (!_shimmer.isAnimating) _shimmer.repeat();
    } else {
      _shimmer.stop();
    }
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: widget.label,
    child: SizedBox(
      height: 44,
      child: LayoutBuilder(
        builder: (context, bounds) {
          final value = widget.value.clamp(0.0, 1.0);
          return Stack(
            alignment: Alignment.centerLeft,
            children: [
              Positioned(
                left: 8,
                right: 8,
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .18),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              Positioned(
                left: 8,
                width:
                    (bounds.maxWidth - 16).clamp(0.0, double.infinity) * value,
                child: AnimatedBuilder(
                  animation: _shimmer,
                  builder: (context, _) => Container(
                    height: 4,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(3),
                      boxShadow:
                          widget.shimmer && GlassScope.effectsEnabled(context)
                          ? [
                              BoxShadow(
                                color: widget.palette.accent.withValues(
                                  alpha: .3,
                                ),
                                blurRadius: 10,
                              ),
                            ]
                          : null,
                      gradient: widget.shimmer
                          ? LinearGradient(
                              colors: [
                                widget.palette.blob1,
                                widget.palette.accent,
                                Colors.white,
                                widget.palette.accent,
                              ],
                              stops: [
                                0,
                                .25 + .25 * _shimmer.value,
                                .65 + .25 * _shimmer.value,
                                1,
                              ],
                            )
                          : null,
                      color: widget.shimmer
                          ? null
                          : Colors.white.withValues(alpha: .8),
                    ),
                  ),
                ),
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4,
                  activeTrackColor: Colors.transparent,
                  inactiveTrackColor: Colors.transparent,
                  disabledActiveTrackColor: Colors.transparent,
                  disabledInactiveTrackColor: Colors.transparent,
                  thumbColor: Colors.white,
                  disabledThumbColor: Colors.white38,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 5,
                  ),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
                  trackShape: const RoundedRectSliderTrackShape(),
                ),
                child: Slider(
                  value: value,
                  padding: EdgeInsets.zero,
                  semanticFormatterCallback:
                      widget.semanticFormatter ??
                      (v) => '${(v * 100).round()}%',
                  onChanged: widget.onChanged,
                  onChangeEnd: widget.onChangeEnd,
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

class PulsePlayButton extends StatefulWidget {
  const PulsePlayButton({
    super.key,
    required this.playing,
    required this.running,
    required this.onPressed,
    required this.palette,
    this.busy = false,
  });
  final bool playing, running, busy;
  final VoidCallback? onPressed;
  final AlbumPalette palette;
  @override
  State<PulsePlayButton> createState() => _PulsePlayButtonState();
}

class _PulsePlayButtonState extends State<PulsePlayButton>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );
  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(PulsePlayButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (widget.running && widget.playing) {
      if (!_pulse.isAnimating) _pulse.repeat();
    } else {
      _pulse.stop();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 76,
    child: Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        if (widget.running && widget.playing)
          IgnorePointer(
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (context, _) => Transform.scale(
                scale: 1 + .45 * _pulse.value,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: widget.palette.accent.withValues(
                        alpha: .5 * (1 - _pulse.value),
                      ),
                      width: 2,
                    ),
                  ),
                ),
              ),
            ),
          ),
        IconButton.filled(
          tooltip: widget.playing ? 'Pause' : 'Play',
          style: IconButton.styleFrom(
            fixedSize: const Size.square(76),
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
          ),
          onPressed: widget.onPressed,
          icon: AppIcon(
            widget.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            size: 32,
          ),
        ),
        if (widget.busy)
          const Positioned.fill(
            child: IgnorePointer(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
                semanticsLabel: 'Loading audio',
              ),
            ),
          ),
      ],
    ),
  );
}

class SheenSweep extends StatefulWidget {
  const SheenSweep({super.key, required this.running});
  final bool running;
  @override
  State<SheenSweep> createState() => _SheenSweepState();
}

class _SheenSweepState extends State<SheenSweep>
    with SingleTickerProviderStateMixin {
  late final _animation = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 7),
  );
  @override
  void initState() {
    super.initState();
    if (widget.running) _animation.repeat();
  }

  @override
  void didUpdateWidget(SheenSweep oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.running && !_animation.isAnimating) _animation.repeat();
    if (!widget.running) _animation.stop();
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RepaintBoundary(
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, _) {
          final t = _animation.value < .7
              ? 0.0
              : Curves.easeInOut.transform((_animation.value - .7) / .3);
          return FractionalTranslation(
            translation: Offset(-1.2 + 3.8 * t, 0),
            child: Transform(
              transform: Matrix4.skewX(-.31),
              child: const FractionallySizedBox(
                widthFactor: .4,
                alignment: Alignment.centerLeft,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color(0x00FFFFFF),
                        Color(0x38FFFFFF),
                        Color(0x00FFFFFF),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}
