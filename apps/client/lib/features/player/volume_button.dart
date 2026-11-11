import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/playback_service.dart';
import '../../widgets/glass_surface.dart';

/// Tap to expand, or drag straight from the speaker. The starting value is
/// preserved when the control opens, so a grab never makes the volume jump.
class VolumeButton extends StatefulWidget {
  const VolumeButton({
    super.key,
    required this.playback,
    this.onExpandedChanged,
  });
  final PlaybackService playback;
  final ValueChanged<bool>? onExpandedChanged;
  @override
  State<VolumeButton> createState() => _VolumeButtonState();
}

class _VolumeButtonState extends State<VolumeButton> {
  final _anchor = GlobalKey();
  final _buttonFocus = FocusNode();
  final _sliderFocus = FocusNode();
  OverlayEntry? _entry;
  double _startY = 0;
  double _startVolume = 0;
  double _dragExtent = 184;

  @override
  void initState() {
    super.initState();
    widget.playback.preferences.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
    _entry?.markNeedsBuild();
  }

  void _close({bool restoreFocus = true}) {
    _entry?.remove();
    _entry?.dispose();
    _entry = null;
    if (restoreFocus && mounted) {
      _buttonFocus.requestFocus();
      widget.onExpandedChanged?.call(false);
    }
  }

  void _show() {
    if (_entry != null) return;
    final overlay = Overlay.of(context);
    final box = _anchor.currentContext!.findRenderObject()! as RenderBox;
    final overlayBox = overlay.context.findRenderObject()! as RenderBox;
    final anchor = box.localToGlobal(Offset.zero, ancestor: overlayBox);
    final buttonBottom = anchor.dy + box.size.height;
    _entry = OverlayEntry(
      builder: (overlayContext) {
        final theme = Theme.of(overlayContext);
        final glass = GlassScope.effectsEnabled(overlayContext);
        final media = MediaQuery.of(overlayContext);
        final height = math.min(
          244.0,
          media.size.height - media.padding.vertical - 32,
        );
        final top = (buttonBottom - height).clamp(
          media.padding.top + 8,
          math.max(
            media.padding.top + 8,
            media.size.height - media.padding.bottom - height - 8,
          ),
        );
        final left = (anchor.dx + box.size.width / 2 - 36).clamp(
          media.padding.left + 12,
          math.max(
            media.padding.left + 12,
            media.size.width - media.padding.right - 84,
          ),
        );
        _dragExtent = math.max(64, height - 60);
        final value = widget.playback.preferences.volume;
        void step(double delta) => widget.playback.setAppVolume(value + delta);
        return Theme(
          data: theme,
          child: GlassScope(
            enabled: glass,
            child: Stack(
              children: [
                Positioned.fill(
                  child: ModalBarrier(
                    color: Colors.transparent,
                    dismissible: true,
                    onDismiss: _close,
                    semanticsLabel: 'Close music volume',
                  ),
                ),
                Positioned(
                  left: left.toDouble(),
                  top: top.toDouble(),
                  width: 72,
                  height: height,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: .20, end: 1),
                    duration: media.disableAnimations
                        ? Duration.zero
                        : const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    builder: (context, scale, child) => Transform.scale(
                      scaleY: scale,
                      alignment: Alignment.bottomCenter,
                      child: child,
                    ),
                    child: Focus(
                      focusNode: _sliderFocus,
                      onKeyEvent: (_, event) {
                        if (event is! KeyDownEvent &&
                            event is! KeyRepeatEvent) {
                          return KeyEventResult.ignored;
                        }
                        switch (event.logicalKey) {
                          case LogicalKeyboardKey.escape:
                            _close();
                          case LogicalKeyboardKey.arrowUp:
                          case LogicalKeyboardKey.arrowRight:
                            step(.05);
                          case LogicalKeyboardKey.arrowDown:
                          case LogicalKeyboardKey.arrowLeft:
                            step(-.05);
                          default:
                            return KeyEventResult.ignored;
                        }
                        return KeyEventResult.handled;
                      },
                      child: Semantics(
                        label: 'Music volume',
                        value: '${(value * 100).round()} percent',
                        increasedValue:
                            '${((value + .05).clamp(0, 1) * 100).round()} percent',
                        decreasedValue:
                            '${((value - .05).clamp(0, 1) * 100).round()} percent',
                        onIncrease: () => step(.05),
                        onDecrease: () => step(-.05),
                        child: GlassSurface(
                          radius: 36,
                          child: Column(
                            children: [
                              SizedBox(
                                height: 44,
                                child: Center(
                                  child: ExcludeSemantics(
                                    child: Text(
                                      '${(value * 100).round()}%',
                                      style: theme.textTheme.labelLarge,
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: GestureDetector(
                                  key: const ValueKey('vertical-volume-track'),
                                  behavior: HitTestBehavior.opaque,
                                  onVerticalDragStart: _startDrag,
                                  onVerticalDragUpdate: _drag,
                                  onTapUp: (details) {
                                    // Tap position inside the filled track is absolute.
                                    widget.playback.setAppVolume(
                                      1 -
                                          details.localPosition.dy /
                                              (height - 44),
                                    );
                                  },
                                  child: ClipRRect(
                                    borderRadius: const BorderRadius.vertical(
                                      bottom: Radius.circular(36),
                                    ),
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        Align(
                                          alignment: Alignment.bottomCenter,
                                          child: FractionallySizedBox(
                                            widthFactor: 1,
                                            heightFactor: value,
                                            child: ColoredBox(
                                              color: theme.colorScheme.onSurface
                                                  .withValues(alpha: .87),
                                            ),
                                          ),
                                        ),
                                        Align(
                                          alignment: Alignment.bottomCenter,
                                          child: Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 8,
                                            ),
                                            child: IconButton(
                                              tooltip: value == 0
                                                  ? 'Unmute music'
                                                  : 'Mute music',
                                              color: value > .18
                                                  ? theme.colorScheme.surface
                                                  : theme.colorScheme.onSurface,
                                              onPressed:
                                                  widget.playback.toggleMute,
                                              icon: Icon(
                                                value == 0
                                                    ? Icons.volume_off_rounded
                                                    : Icons.volume_up_rounded,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    overlay.insert(_entry!);
    widget.onExpandedChanged?.call(true);
    _sliderFocus.requestFocus();
  }

  void _startDrag(DragStartDetails details) {
    _startY = details.globalPosition.dy;
    _startVolume = widget.playback.preferences.volume;
    _show();
  }

  void _drag(DragUpdateDetails details) => widget.playback.setAppVolume(
    _startVolume + (_startY - details.globalPosition.dy) / _dragExtent,
  );

  @override
  void dispose() {
    _close(restoreFocus: false);
    widget.playback.preferences.removeListener(_changed);
    _buttonFocus.dispose();
    _sliderFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    key: _anchor,
    onVerticalDragStart: _startDrag,
    onVerticalDragUpdate: _drag,
    child: IconButton(
      focusNode: _buttonFocus,
      tooltip: 'Music volume',
      onPressed: _show,
      icon: Icon(
        widget.playback.preferences.volume == 0
            ? Icons.volume_off_rounded
            : Icons.volume_up_rounded,
      ),
    ),
  );
}
