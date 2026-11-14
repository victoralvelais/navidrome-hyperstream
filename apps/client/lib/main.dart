import 'dart:async';

import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'features/connect/connection_screen.dart';
import 'features/library/library_screen.dart';
import 'features/startup/startup_screen.dart';
import 'services/account_session.dart';
import 'services/app_preferences.dart';
import 'services/playback_service.dart';
import 'services/remote_folder.dart';
import 'services/startup_stage.dart';
import 'services/third_party_licenses.dart';
import 'widgets/glass_settings.dart';

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
  registerNativeLicenses();
  unawaited(RemoteFolders.instance.restore());
  runApp(const HyperstreamApp());
}

class HyperstreamApp extends StatefulWidget {
  const HyperstreamApp({
    super.key,
    this.initialize = initializeHyperstream,
    this.accountSession,
  });
  final AppInitializer initialize;
  final AccountSession? accountSession;

  @override
  State<HyperstreamApp> createState() => _HyperstreamAppState();
}

class _HyperstreamAppState extends State<HyperstreamApp>
    with WidgetsBindingObserver {
  Future<PlaybackService>? _initialization;
  PlaybackService? _playback;
  late final AccountSession _account =
      widget.accountSession ?? AccountSession();
  StartupStage _stage = StartupStage.opening;
  Timer? _startupTimer;
  bool _takingLonger = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _account.addListener(_accountChanged);
    // Paint an identifiable screen before any preference or audio platform call.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _start();
    });
  }

  void _accountChanged() {
    final playback = _playback;
    final client = _account.client;
    if (playback != null &&
        client != null &&
        _account.phase == AccountPhase.connected) {
      unawaited(
        playback.attachAccount(client, remember: _account.hasSavedAccount),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _account.retryConnectionNow();
      _playback?.retryConnectionNow();
    } else {
      final playback = _playback;
      if (playback != null) unawaited(playback.savePlayback());
    }
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
        _setStage(StartupStage.account);
        await _account.restore();
        _accountChanged();
      }
      return service;
    } finally {
      _startupTimer?.cancel();
    }
  }

  Future<void> _disconnect() async {
    await _playback!.reset();
    await _account.disconnect();
    await _playback!.suspendForAccountSwitch();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _account.removeListener(_accountChanged);
    _startupTimer?.cancel();
    _account.dispose();
    final playback = _playback;
    if (playback != null) unawaited(playback.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        _account,
        if (_playback != null) _playback!.preferences,
      ]),
      builder: (context, _) => MaterialApp(
        title: 'Hyperstream',
        debugShowCheckedModeBanner: false,
        themeMode: _playback?.preferences.themeMode ?? ThemeMode.system,
        theme: hyperstreamTheme(Brightness.light),
        darkTheme: hyperstreamTheme(Brightness.dark),
        builder: (context, child) =>
            GlassSettings(preferences: _playback?.preferences, child: child!),
        home: FutureBuilder<PlaybackService>(
          future: _initialization,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return StartupScreen(stage: _stage, onRetry: _start);
            }
            if (!snapshot.hasData) {
              return StartupScreen(stage: _stage, takingLonger: _takingLonger);
            }
            final client = _account.client;
            return client == null
                ? ConnectionScreen(session: _account)
                : LibraryScreen(
                    key: ObjectKey(client),
                    client: client,
                    accountSession: _account,
                    playback: snapshot.data!,
                    onDisconnect: _disconnect,
                  );
          },
        ),
      ),
    );
  }
}
