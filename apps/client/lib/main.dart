import 'dart:async';

import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'features/connect/connection_screen.dart';
import 'features/library/library_screen.dart';
import 'features/startup/startup_screen.dart';
import 'services/navidrome_client.dart';
import 'services/app_preferences.dart';
import 'services/playback_service.dart';
import 'services/startup_stage.dart';

typedef AppInitializer = Future<PlaybackService> Function(
  ValueChanged<StartupStage> onStage,
);

Future<PlaybackService> initializeHyperstream(
  ValueChanged<StartupStage> onStage,
) async {
  onStage(StartupStage.preferences);
  final preferences = await AppPreferences.load();
  return PlaybackService.initialize(preferences: preferences, onStage: onStage);
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HyperstreamApp());
}

class HyperstreamApp extends StatefulWidget {
  const HyperstreamApp({super.key, this.initialize = initializeHyperstream});
  final AppInitializer initialize;

  @override
  State<HyperstreamApp> createState() => _HyperstreamAppState();
}

class _HyperstreamAppState extends State<HyperstreamApp> {
  Future<PlaybackService>? _initialization;
  PlaybackService? _playback;
  NavidromeClient? _client;
  StartupStage _stage = StartupStage.opening;
  Timer? _startupTimer;
  bool _takingLonger = false;

  @override
  void initState() {
    super.initState();
    // Paint an identifiable screen before any preference or audio platform call.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _start();
    });
  }

  void _setStage(StartupStage stage) {
    if (!mounted) return;
    _startupTimer?.cancel();
    setState(() {
      _stage = stage;
      _takingLonger = false;
    });
    _startupTimer = Timer(const Duration(seconds: 15), () {
      if (mounted) setState(() => _takingLonger = true);
    });
  }

  void _start() {
    _setStage(StartupStage.opening);
    final future = _initialize();
    // FutureBuilder attaches next frame; observe early failures immediately.
    future.ignore();
    setState(() {
      _initialization = future;
    });
  }

  Future<PlaybackService> _initialize() async {
    try {
      final service = await widget.initialize(_setStage);
      if (!mounted) {
        await service.dispose();
      } else {
        setState(() => _playback = service);
      }
      return service;
    } finally {
      _startupTimer?.cancel();
    }
  }

  Future<void> _disconnect() async {
    await _playback!.reset();
    _client?.close();
    if (mounted) setState(() => _client = null);
  }

  @override
  void dispose() {
    _startupTimer?.cancel();
    _client?.close();
    final playback = _playback;
    if (playback != null) unawaited(playback.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _playback?.preferences ?? const AlwaysStoppedAnimation(0),
      builder: (context, _) => MaterialApp(
        title: 'Hyperstream',
        debugShowCheckedModeBanner: false,
        themeMode: _playback?.preferences.themeMode ?? ThemeMode.system,
        theme: hyperstreamTheme(Brightness.light),
        darkTheme: hyperstreamTheme(Brightness.dark),
        home: FutureBuilder<PlaybackService>(
          future: _initialization,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return StartupScreen(stage: _stage, onRetry: _start);
            }
            if (!snapshot.hasData) {
              return StartupScreen(stage: _stage, takingLonger: _takingLonger);
            }
            final client = _client;
            return client == null
                ? ConnectionScreen(
                    onConnected: (client) => setState(() => _client = client),
                  )
                : LibraryScreen(
                    client: client,
                    playback: snapshot.data!,
                    onDisconnect: _disconnect,
                  );
          },
        ),
      ),
    );
  }
}
