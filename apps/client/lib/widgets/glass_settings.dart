import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_preferences.dart';
import 'glass_surface.dart';

/// Flutter doesn't expose iOS Reduce Transparency through MediaQuery.
/// This small bridge listens for changes and rechecks when returning to the app.
class GlassSettings extends StatefulWidget {
  const GlassSettings({super.key, this.preferences, required this.child});
  final AppPreferences? preferences;
  final Widget child;
  @override
  State<GlassSettings> createState() => _GlassSettingsState();
}

class _GlassSettingsState extends State<GlassSettings>
    with WidgetsBindingObserver {
  static const _channel = MethodChannel('dev.hyperstream/appearance');
  bool get _ios => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  late bool _reduceTransparency = _ios;
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    if (_ios) {
      WidgetsBinding.instance.addObserver(this);
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'reduceTransparencyChanged' &&
            call.arguments is bool) {
          _revision++;
          if (mounted) {
            setState(() => _reduceTransparency = call.arguments as bool);
          }
        }
      });
      unawaited(_refresh());
    }
  }

  Future<void> _refresh() async {
    final revision = ++_revision;
    var reduced = true;
    try {
      reduced =
          await _channel
              .invokeMethod<bool>('reduceTransparency')
              .timeout(const Duration(seconds: 3)) ??
          true;
    } on Object {
      // Missing or stalled native support uses the readable opaque material.
    }
    if (mounted && revision == _revision) {
      setState(() => _reduceTransparency = reduced);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  @override
  void dispose() {
    if (_ios) {
      WidgetsBinding.instance.removeObserver(this);
      _channel.setMethodCallHandler(null);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.preferences ?? const AlwaysStoppedAnimation(0),
    builder: (context, _) => GlassScope(
      enabled:
          (widget.preferences?.glassEffects ?? true) && !_reduceTransparency,
      child: widget.child,
    ),
  );
}
