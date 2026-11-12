import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Shares one vertical drag between the list and its enclosing sheet. Lists
/// use the supplied PrimaryScrollController; wheel and reorder scrolling keep
/// their normal behavior and never initiate sheet dismissal.
class PullDownSheet extends StatefulWidget {
  const PullDownSheet({super.key, required this.child});
  final Widget child;

  @override
  State<PullDownSheet> createState() => _PullDownSheetState();
}

class _PullDownSheetState extends State<PullDownSheet>
    with SingleTickerProviderStateMixin {
  late final _pull = AnimationController.unbounded(vsync: this)
    ..addListener(_stretchList);
  late final _scroll = _PullScrollController(this);
  bool _cancelled = false;
  bool _closing = false;

  // The list's extra movement fades toward 28 points. After 56 points of
  // finger travel, the panel eases into following the rest of the gesture.
  double get _stretch => 28 * (1 - math.exp(-_pull.value / 56));
  double get _panelOffset {
    final travel = math.max(0.0, _pull.value - 56);
    return travel - 28 * (1 - math.exp(-travel / 28));
  }

  void _stretchList() {
    for (final position in _scroll.positions) {
      if (position.hasContentDimensions) {
        (position as _PullScrollPosition).stretchTo(_stretch);
      }
    }
  }

  double _dragBy(double delta) {
    _pull.stop();
    final next = _pull.value + delta;
    _pull.value = math.max(0.0, next);
    return math.min(0.0, next);
  }

  void _release(double downVelocity) {
    if (_closing || !mounted) return;
    final dismiss =
        !_cancelled &&
        (_panelOffset >= 120 || (_panelOffset >= 32 && downVelocity > 900));
    if (dismiss && ModalRoute.of(context)?.isCurrent == true) {
      _closing = true;
      Navigator.of(context).pop();
    } else {
      _pull.animateTo(
        0,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _pull.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _pull,
    builder: (context, child) =>
        Transform.translate(offset: Offset(0, _panelOffset), child: child),
    child: Listener(
      // Flutter reports an accepted drag's pointer cancellation through onEnd.
      // Observe cancellation before the recognizer turns it into a release.
      onPointerCancel: (_) => _cancelled = true,
      child: PrimaryScrollController(controller: _scroll, child: widget.child),
    ),
  );
}

class _PullScrollController extends ScrollController {
  _PullScrollController(this.owner);
  final _PullDownSheetState owner;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => _PullScrollPosition(
    owner: owner,
    physics: _PullPhysics(parent: physics),
    context: context,
    oldPosition: oldPosition,
  );
}

class _PullScrollPosition extends ScrollPositionWithSingleContext {
  _PullScrollPosition({
    required this.owner,
    required super.physics,
    required super.context,
    super.oldPosition,
  });
  final _PullDownSheetState owner;

  void stretchTo(double stretch) {
    final target = minScrollExtent - stretch;
    if (activity?.isScrolling == true) {
      setPixels(target);
    } else if (pixels != target) {
      // On release the sheet's animation owns the elastic presentation offset;
      // the scroll activity is idle, so setPixels cannot drive that animation.
      forcePixels(target);
    }
  }

  @override
  void applyUserOffset(double delta) {
    if (owner._closing) return;
    if (owner._pull.value > 0) {
      final remainder = owner._dragBy(delta);
      if (remainder < 0) super.applyUserOffset(remainder);
    } else if (delta > 0 && pixels - minScrollExtent < delta) {
      final toTop = math.max(0.0, pixels - minScrollExtent);
      if (toTop > 0) super.applyUserOffset(toTop);
      owner._dragBy(delta - toTop);
    } else {
      super.applyUserOffset(delta);
    }
  }

  @override
  void goBallistic(double velocity) {
    if (owner._pull.value > 0) {
      goIdle();
      owner._release(-velocity);
    } else {
      super.goBallistic(velocity);
    }
  }

  @override
  ScrollHoldController hold(VoidCallback holdCancelCallback) {
    owner._pull.stop();
    return super.hold(holdCancelCallback);
  }

  @override
  Drag drag(DragStartDetails details, VoidCallback dragCancelCallback) {
    owner._cancelled = false;
    return _PullDrag(super.drag(details, dragCancelCallback), owner);
  }
}

class _PullDrag implements Drag {
  _PullDrag(this.drag, this.owner);
  final Drag drag;
  final _PullDownSheetState owner;

  @override
  void update(DragUpdateDetails details) => drag.update(details);
  @override
  void end(DragEndDetails details) => drag.end(details);
  @override
  void cancel() {
    owner._cancelled = true;
    drag.cancel();
  }
}

class _PullPhysics extends ScrollPhysics {
  const _PullPhysics({super.parent});

  @override
  bool shouldAcceptUserOffset(ScrollMetrics position) => true;

  @override
  double applyBoundaryConditions(ScrollMetrics position, double value) {
    // The coordinator owns the elastic distance above the first row. Normal
    // physics still owns the bottom of the list and every non-touch scroll.
    if (value <= position.minScrollExtent) return 0;
    return super.applyBoundaryConditions(position, value);
  }
}
