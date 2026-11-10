import 'dart:async';

import 'package:flutter/material.dart';

import 'features/connect/connection_screen.dart';
import 'features/library/library_screen.dart';
import 'services/navidrome_client.dart';
import 'services/playback_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HyperstreamApp());
}

class HyperstreamApp extends StatefulWidget {
  const HyperstreamApp({super.key});

  @override
  State<HyperstreamApp> createState() => _HyperstreamAppState();
}

class _HyperstreamAppState extends State<HyperstreamApp> {
  late Future<PlaybackService> _initialization;
  PlaybackService? _playback;
  NavidromeClient? _client;

  @override
  void initState() {
    super.initState();
    _initialization = _initialize();
  }

  Future<PlaybackService> _initialize() async {
    final service = await PlaybackService.initialize();
    if (!mounted) {
      await service.dispose();
    } else {
      _playback = service;
    }
    return service;
  }

  Future<void> _disconnect() async {
    await _playback!.reset();
    _client?.close();
    if (mounted) setState(() => _client = null);
  }

  @override
  void dispose() {
    _client?.close();
    final playback = _playback;
    if (playback != null) unawaited(playback.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hyperstream',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff326b61)),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff82d8bd),
          brightness: Brightness.dark,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      home: FutureBuilder<PlaybackService>(
        future: _initialization,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Scaffold(
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Could not start the audio player.'),
                    TextButton(
                      onPressed: () =>
                          setState(() => _initialization = _initialize()),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
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
    );
  }
}
