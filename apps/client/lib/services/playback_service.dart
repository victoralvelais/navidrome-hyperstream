import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../models/library.dart';
import 'app_preferences.dart';
import 'navidrome_client.dart';

/// One instance for the application, independent of navigation and widgets.
/// just_audio owns the native queue, including transitions while backgrounded.
class PlaybackService extends BaseAudioHandler {
  PlaybackService({
    AudioPlayer? player,
    AppPreferences? preferences,
    Future<void> Function(AudioSessionConfiguration)? configureSession,
  }) : _player = player ?? AudioPlayer(),
       preferences = preferences ?? AppPreferences(),
       _configureSession = configureSession ?? _configureNativeSession {
    _subscriptions.addAll([
      _player.playbackEventStream.listen((_) => _publishState()),
      _player.playerStateStream.listen((_) => _publishState()),
      _player.currentIndexStream.listen((_) => _publishItem()),
      _player.durationStream.listen((_) => _publishItem()),
      _player.errorStream.listen((_) => _reportFailure()),
    ]);
  }

  static Future<PlaybackService> initialize({
    AppPreferences? preferences,
  }) async {
    PlaybackService build() => PlaybackService(preferences: preferences);
    final handler = Platform.isIOS
        ? await AudioService.init<PlaybackService>(builder: build)
        : build();
    try {
      // Configure before the first play on every platform. just_audio also
      // consults this shared session on Windows; lazy first-play setup can race
      // with WinRT's initial paused-state notification and cancel playback.
      await handler._configureSession(
        sessionConfiguration(handler.preferences.mixWithOthers),
      );
      await handler._player.setVolume(handler.preferences.volume);
    } on Object {
      await handler.dispose();
      rethrow;
    }
    return handler;
  }

  final AudioPlayer _player;
  final AppPreferences preferences;
  final Future<void> Function(AudioSessionConfiguration) _configureSession;
  final ValueNotifier<String?> settingsError = ValueNotifier(null);
  Future<void> _settingsPending = Future.value();
  bool get supportsMixing => Platform.isIOS;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final ValueNotifier<String?> error = ValueNotifier(null);
  Future<void> _pending = Future.value();
  int _revision = 0;
  bool _loading = false;
  bool _playWhenReady = false;

  Stream<Duration> get positionStream => _player.positionStream;
  Duration get position => _player.position;

  static AudioSessionConfiguration sessionConfiguration(bool mix) =>
      const AudioSessionConfiguration.music().copyWith(
        // Explicit zero also clears an earlier mixWithOthers choice.
        avAudioSessionCategoryOptions: mix
            ? AVAudioSessionCategoryOptions.mixWithOthers
            : AVAudioSessionCategoryOptions.none,
      );

  static Future<void> _configureNativeSession(
    AudioSessionConfiguration configuration,
  ) async => (await AudioSession.instance).configure(configuration);

  Future<void> _changeSetting(Future<void> Function() apply) {
    _settingsPending = _settingsPending.then((_) async {
      try {
        await apply();
        settingsError.value = null;
      } on Object {
        // A setting failure must not put the playing queue into an error state.
        settingsError.value = 'Could not change the audio setting. Try again.';
      }
    });
    return _settingsPending;
  }

  Future<void> setAppVolume(double value) {
    if (!value.isFinite) return Future.value();
    final level = value.clamp(0.0, 1.0);
    return _changeSetting(() async {
      await _player.setVolume(level);
      // Disk writes are serialized by preferences; keep slider input responsive.
      unawaited(preferences.setVolume(level));
    });
  }

  Future<void> toggleMute() => _changeSetting(() async {
    final level = preferences.volume == 0 ? preferences.audibleVolume : 0.0;
    await _player.setVolume(level);
    unawaited(preferences.setVolume(level));
  });

  Future<void> setMixWithOthers(bool value) => _changeSetting(() async {
    await _configureSession(sessionConfiguration(value));
    await preferences.setMixWithOthers(value);
  });

  // Serializing replacement and reset prevents an older selection from taking
  // over a newer one. Revisions let queued, superseded selections be skipped.
  Future<void> playAlbum(
    NavidromeClient client,
    List<Track> tracks,
    int index, {
    String? coverArtId,
  }) {
    if (tracks.isEmpty || index < 0 || index >= tracks.length) {
      return Future.value();
    }
    final revision = ++_revision;
    _loading = true;
    _playWhenReady = true;
    error.value = null;
    _publishState();
    _pending = _pending.then((_) async {
      if (revision != _revision) return;
      _loading = true;
      try {
        await _player.pause();
        if (revision != _revision) return;
        final items = tracks
            .map(
              (track) => MediaItem(
                id: track.id,
                title: track.title,
                artist: track.artist,
                album: track.album,
                duration: track.duration,
                extras: {'coverArtId': ?coverArtId},
              ),
            )
            .toList();
        queue.add(items);
        mediaItem.add(items[index]);
        await _player.setAudioSources(
          tracks.indexed
              .map(
                (entry) => AudioSource.uri(
                  client.streamUri(entry.$2.id),
                  tag: items[entry.$1],
                ),
              )
              .toList(),
          initialIndex: index,
          initialPosition: Duration.zero,
        );
        if (revision != _revision) return;
        _loading = false;
        _publishItem();
        _publishState();
        if (_playWhenReady) unawaited(play());
      } on Object {
        if (revision == _revision) {
          _loading = false;
          _reportFailure();
        }
      }
    });
    return _pending;
  }

  void _publishItem() {
    if (_loading) return;
    final index = _player.currentIndex;
    if (index != null && index >= 0 && index < queue.value.length) {
      final item = queue.value[index];
      mediaItem.add(item.copyWith(duration: _player.duration ?? item.duration));
    }
  }

  void _publishState() {
    final processing = error.value != null
        ? AudioProcessingState.error
        : _loading
        ? AudioProcessingState.loading
        : switch (_player.processingState) {
            ProcessingState.idle => AudioProcessingState.idle,
            ProcessingState.loading => AudioProcessingState.loading,
            ProcessingState.buffering => AudioProcessingState.buffering,
            ProcessingState.ready => AudioProcessingState.ready,
            ProcessingState.completed => AudioProcessingState.completed,
          };
    final playing =
        error.value == null &&
        (_loading ? _playWhenReady : _player.playing) &&
        processing != AudioProcessingState.completed;
    playbackState.add(
      PlaybackState(
        controls: [
          if (!_loading && _player.hasPrevious) MediaControl.skipToPrevious,
          playing ? MediaControl.pause : MediaControl.play,
          if (!_loading && _player.hasNext) MediaControl.skipToNext,
          MediaControl.stop,
        ],
        systemActions: const {MediaAction.seek},
        processingState: processing,
        playing: playing,
        updatePosition: _loading ? Duration.zero : _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: _player.currentIndex,
        errorCode: error.value == null ? null : 1,
        errorMessage: error.value,
      ),
    );
  }

  void _reportFailure() {
    _playWhenReady = false;
    error.value =
        'Playback failed. Check your connection and select a track again.';
    _publishState();
  }

  Future<void> _command(Future<void> Function() command) async {
    try {
      await command();
    } on Object {
      _reportFailure();
    }
  }

  @override
  Future<void> play() async {
    _playWhenReady = true;
    if (_loading) {
      _publishState();
      return;
    }
    if (mediaItem.value == null || error.value != null) return;
    await _command(() async {
      if (_player.processingState == ProcessingState.completed) {
        await _player.seek(Duration.zero, index: 0);
      }
      // The play future completes only when playback ends or pauses.
      unawaited(_command(_player.play));
    });
  }

  @override
  Future<void> pause() async {
    _playWhenReady = false;
    await _command(_player.pause);
    _publishState();
  }

  @override
  Future<void> seek(Duration position) async {
    if (!_loading) await _command(() => _player.seek(position));
  }

  @override
  Future<void> skipToNext() async {
    if (!_loading && _player.hasNext) await _command(_player.seekToNext);
  }

  @override
  Future<void> skipToPrevious() async {
    if (!_loading && _player.hasPrevious) {
      await _command(_player.seekToPrevious);
    }
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (!_loading && index >= 0 && index < queue.value.length) {
      await _command(() => _player.seek(Duration.zero, index: index));
    }
  }

  @override
  Future<void> stop() => reset();

  Future<void> reset() {
    ++_revision;
    _playWhenReady = false;
    _pending = _pending.then((_) async {
      await _command(() async {
        await _player.stop();
        await _player.clearAudioSources();
      });
      _loading = false;
      queue.add([]);
      mediaItem.add(null);
      error.value = null;
      _publishState();
    });
    return _pending;
  }

  Future<void> dispose() async {
    await _settingsPending;
    await preferences.flush();
    await reset();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _player.dispose();
    error.dispose();
    settingsError.dispose();
    preferences.dispose();
  }
}
