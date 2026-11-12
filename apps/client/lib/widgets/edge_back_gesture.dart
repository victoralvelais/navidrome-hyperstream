import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Observe an intentional touch swipe from the left edge without taking gestures
/// away from scrolling, sliders or text selection in the rest of the page.
class EdgeBackGesture extends StatefulWidget {
  const EdgeBackGesture({super.key, required this.child, this.onBack});
  final Widget child;
  final VoidCallback? onBack;
  @override
  State<EdgeBackGesture> createState() => _EdgeBackGestureState();
}

class _EdgeBackGestureState extends State<EdgeBackGesture> {
  int? _pointer;
  Offset? _start;
  Offset _delta = Offset.zero;

  void _reset() {
    _pointer = null;
    _start = null;
    _delta = Offset.zero;
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (event) {
      if (_pointer != null) {
        _reset();
        return;
      }
      if (widget.onBack == null ||
          event.kind == PointerDeviceKind.mouse ||
          event.localPosition.dx > 28 ||
          !(ModalRoute.of(context)?.isCurrent ?? true)) {
        return;
      }
      _pointer = event.pointer;
      _start = event.position;
    },
    onPointerMove: (event) {
      if (event.pointer != _pointer || _start == null) return;
      _delta = event.position - _start!;
      if (_delta.dy.abs() > 32 && _delta.dy.abs() > _delta.dx.abs()) _reset();
    },
    onPointerCancel: (_) => _reset(),
    onPointerUp: (event) {
      if (event.pointer != _pointer) return;
      final goBack = _delta.dx >= 64 && _delta.dx > _delta.dy.abs() * 2;
      _reset();
      if (goBack && (ModalRoute.of(context)?.isCurrent ?? true)) {
        widget.onBack?.call();
      }
    },
    child: widget.child,
  );
}

/// Route gestures use the same guard as Back, including unsaved-edit prompts.
class MenuPageRoute<T> extends MaterialPageRoute<T> {
  MenuPageRoute({required WidgetBuilder builder})
    : super(
        builder: (context) => EdgeBackGesture(
          onBack: () => Navigator.maybePop(context),
          child: builder(context),
        ),
      );
  @override
  bool get popGestureEnabled => false; // One recognizer owns the edge gesture.
}
