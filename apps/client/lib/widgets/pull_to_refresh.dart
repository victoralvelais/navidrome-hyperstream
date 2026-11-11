import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shared gesture and desktop shortcut. Scrollables must always accept drags,
/// even when the current collection is empty or shorter than the viewport.
class PullToRefresh extends StatefulWidget {
  const PullToRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
  });
  final Future<void> Function() onRefresh;
  final Widget child;
  @override
  State<PullToRefresh> createState() => _PullToRefreshState();
}

class _PullToRefreshState extends State<PullToRefresh> {
  final _focus = FocusNode();
  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {const SingleActivator(LogicalKeyboardKey.f5): widget.onRefresh},
    child: Focus(
      focusNode: _focus,
      child: Listener(
        onPointerDown: (_) => _focus.requestFocus(),
        onPointerSignal: (_) => _focus.requestFocus(),
        child: RefreshIndicator.adaptive(
          onRefresh: widget.onRefresh,
          child: widget.child,
        ),
      ),
    ),
  );
}

class DockSpacer extends StatelessWidget {
  const DockSpacer({super.key});
  @override
  Widget build(BuildContext context) =>
      SizedBox(height: MediaQuery.paddingOf(context).bottom + 16);
}
