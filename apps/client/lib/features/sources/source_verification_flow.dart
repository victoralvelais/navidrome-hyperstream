import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/mornye_sources.dart';
import '../../services/music_provider.dart';

/// Presents above the active route, including Now Playing and camera sheets.
/// A request made with the screen off waits until the app is visible again.
class SourceVerificationHost extends StatefulWidget {
  const SourceVerificationHost({
    super.key,
    required this.sources,
    required this.navigatorKey,
    required this.child,
  });
  final MornyeSources sources;
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;
  @override
  State<SourceVerificationHost> createState() => _SourceVerificationHostState();
}

class _SourceVerificationHostState extends State<SourceVerificationHost>
    with WidgetsBindingObserver {
  Completer<void>? _resumed;
  late final Future<bool> Function(String) _present = _presentVerification;
  Future<bool> _presentVerification(String id) async {
    if (!await _foreground()) return false;
    final context = widget.navigatorKey.currentContext;
    if (context == null || !context.mounted) return false;
    return showSourceVerification(
      context,
      widget.sources,
      id,
      foreground: _foreground,
    );
  }

  @override
  void initState() {
    super.initState();
    widget.sources.presentVerification = _present;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(SourceVerificationHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sources != widget.sources) {
      if (identical(oldWidget.sources.presentVerification, _present)) {
        oldWidget.sources.presentVerification = null;
      }
      widget.sources.presentVerification = _present;
    }
  }

  Future<bool> _foreground() async {
    while (mounted) {
      final state = WidgetsBinding.instance.lifecycleState;
      if (state == null || state == AppLifecycleState.resumed) return true;
      await (_resumed ??= Completer<void>()).future;
    }
    return false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _resumed?.complete();
      _resumed = null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (identical(widget.sources.presentVerification, _present)) {
      widget.sources.presentVerification = null;
    }
    _resumed?.complete();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

Future<bool> showSourceVerification(
  BuildContext context,
  MornyeSources sources,
  String id, {
  Future<bool> Function()? foreground,
}) async {
  if (await sources.verify(id)) return true;
  if (foreground != null && !await foreground()) return false;
  if (!context.mounted) return false;
  return await showDialog<bool>(
        context: context,
        builder: (_) =>
            SourceVerificationDialog(sources: sources, providerId: id),
      ) ??
      false;
}

class SourceVerificationDialog extends StatefulWidget {
  const SourceVerificationDialog({
    super.key,
    required this.sources,
    required this.providerId,
  });
  final MornyeSources sources;
  final String providerId;
  @override
  State<SourceVerificationDialog> createState() =>
      _SourceVerificationDialogState();
}

class _SourceVerificationDialogState extends State<SourceVerificationDialog> {
  final controller = TextEditingController();
  bool saving = false;
  String? error;

  Future<void> _submit() async {
    if (saving) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.sources.pasteVerification(
        widget.providerId,
        controller.text,
      );
      controller.clear();
      if (mounted) Navigator.pop(context, true);
    } on Object catch (failure) {
      if (mounted) {
        setState(() {
          saving = false;
          error = failure is SourceException
              ? failure.message
              : 'Verification could not finish. Try again.';
        });
      }
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: AlertDialog(
      scrollable: true,
      title: Text('Verify ${widget.sources.name(widget.providerId)}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'If verification did not return to Hyperstream, copy the link or code from the completed browser page and paste it here. Use it promptly; verification codes expire.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: controller,
            enabled: !saving,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            enableIMEPersonalizedLearning: false,
            keyboardType: TextInputType.visiblePassword,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'Verification link or code',
            ),
            onSubmitted: (_) => _submit(),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(error!),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: saving ? null : _submit,
          child: Text(saving ? 'Verifying…' : 'Complete verification'),
        ),
      ],
    ),
  );
}
