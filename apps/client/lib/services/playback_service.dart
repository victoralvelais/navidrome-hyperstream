import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../models/library.dart';
import '../models/source_reference.dart';
import 'music_sources.dart';
import 'music_provider.dart';
import 'app_preferences.dart';
import 'navidrome_client.dart';
import 'listen_tracker.dart';
import 'startup_stage.dart';
import 'system_artwork.dart';
import 'playback_store.dart';
import 'song_playback_store.dart';

class SleepTimerState {
  const SleepTimerState({this.deadline, this.endOfTrack = false});
  final DateTime? deadline;
  final bool endOfTrack;
}

/// One instance for the application, independent of navigation and widgets.
/// just_audio owns the native queue, including transitions while backgrounded.
class PlaybackService extends BaseAudioHandler {
  PlaybackService({
    AudioPlayer? player,
    AppPreferences? preferences,
    SongPlaybackStore? songPlaybackStore,
    Future<void> Function(AudioSessionConfiguration)? configureSession,
    Duration Function()? listeningClock,
    DateTime Function()? listeningTime,
    Future<Uri?> Function(NavidromeClient, String)? artworkLoader,
    DateTime Function()? timerClock,
    Random? random,
    PlaybackStore Function(NavidromeClient)? playbackStore,
    Uri Function(SourceReference)? sourceStreamUri,
    Future<bool> Function(SourceReference)? verifySource,
    Future<void> Function()? resetSourcePlayback,
    ValueListenable<Map<String, SourcePlaybackInfo>>? sourcePlaybackInfo,
  }) : _player = player ?? AudioPlayer(),
       preferences = preferences ?? AppPreferences(),
       songPlaybackStore = songPlaybackStore ?? SongPlaybackStore(),
       _configureSession = configureSession ?? _configureNativeSession,
       _artworkLoader = artworkLoader ?? SystemArtwork().load,
       _timerClock = timerClock ?? DateTime.now,
       _random = random ?? Random() {
    _sourceStreamUri = sourceStreamUri ?? MusicSources.instance.streamUri;
    _verifySource = verifySource ?? MusicSources.instance.verifyPlayback;
    _resetSourcePlayback =
        resetSourcePlayback ?? MusicSources.instance.resetPlayback;
    _sourcePlaybackInfo =
        sourcePlaybackInfo ?? MusicSources.instance.playbackInfo;
    _sourcePlaybackInfo.addListener(_publishSourceInfo);
    _storeFactory = playbackStore;
    _listenTracker = ListenTracker(
      elapsed: listeningClock ?? () => _listeningClock.elapsed,
      now: listeningTime ?? DateTime.now,
      onListen: _submitListen,
    );
    this.preferences.addListener(_syncListening);
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
    ValueChanged<StartupStage>? onStage,
    PlaybackStore Function(NavidromeClient)? playbackStore,
    SongPlaybackStore? songPlaybackStore,
  }) async {
    onStage?.call(StartupStage.player);
    final songSettings = songPlaybackStore ?? await SongPlaybackStore.load();
    PlaybackService build() => PlaybackService(
      preferences: preferences,
      songPlaybackStore: songSettings,
      playbackStore: playbackStore ?? FilePlaybackStore.new,
    );
    final handler = Platform.isIOS
        ? await AudioService.init<PlaybackService>(builder: build)
        : build();
    try {
      // Configure before the first play on every platform. just_audio also
      // consults this shared session on Windows; lazy first-play setup can race
      // with WinRT's initial paused-state notification and cancel playback.
      onStage?.call(StartupStage.audioSession);
      await handler._configureSession(
        sessionConfiguration(handler.preferences.mixWithOthers),
      );
      onStage?.call(StartupStage.volume);
      await handler._player.setVolume(handler.preferences.volume);
    } on Object {
      await handler.dispose();
      rethrow;
    }
    return handler;
  }

  final AudioPlayer _player;
  late final Uri Function(SourceReference) _sourceStreamUri;
  late final Future<bool> Function(SourceReference) _verifySource;
  late final Future<void> Function() _resetSourcePlayback;
  late final ValueListenable<Map<String, SourcePlaybackInfo>>
  _sourcePlaybackInfo;

  String _audioDetails(Track track) {
    final source = track.source;
    if (source == null) return track.audioDetails;
    return _sourcePlaybackInfo.value[source.identity]?.label ??
        [
          musicSourceName(source.sourceId),
          if (track.audioDetails.isNotEmpty) track.audioDetails,
        ].join(' · ');
  }

  void _publishSourceInfo() {
    if (_disposed || queue.value.isEmpty) return;
    final items = queue.value.indexed.map((entry) {
      final track = trackAt(entry.$1);
      if (track?.source == null) return entry.$2;
      return entry.$2.copyWith(
        extras: {...?entry.$2.extras, 'audioDetails': _audioDetails(track!)},
      );
    }).toList();
    queue.add(items);
    _publishItem();
  }

  bool _needsPlaybackReset = false;
  bool _resettingPlayback = false;
  Completer<Duration?>? _loadFailure;
  int? _sourceVerificationEpoch;
  int? _verificationRecoveryRevision;
  final _sourceArtwork = SystemArtwork();
  final AppPreferences preferences;
  final SongPlaybackStore songPlaybackStore;
  final songPlaybackSettings = ValueNotifier(const SongPlaybackSettings());
  String? _activeSongKey;
  int _songSettingsEpoch = 0;
  Future<void> _songSettingsPending = Future.value();
  final Future<void> Function(AudioSessionConfiguration) _configureSession;
  final ValueNotifier<String?> settingsError = ValueNotifier(null);
  final ValueNotifier<String?> listeningNotice = ValueNotifier(null);
  final _listeningClock = Stopwatch()..start();
  late final ListenTracker _listenTracker;
  Timer? _listenTimer;
  NavidromeClient? _listeningClient;
  List<Track> _listeningTracks = const [];
  int? _listeningIndex;
  int _listeningGeneration = 0;
  bool _seeking = false;
  bool _disposed = false;
  Future<void> _settingsPending = Future.value();
  bool get supportsMixing => Platform.isIOS;
  bool get supportsPitchControl => _player.supportsPitchControl;
  bool get canEditSongSettings =>
      !_disposed && !_loading && error.value == null && _activeSongKey != null;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final ValueNotifier<String?> error = ValueNotifier(null);
  Future<void> _pending = Future.value();
  int _revision = 0;
  bool _loading = false;
  bool _playWhenReady = false;
  final Future<Uri?> Function(NavidromeClient, String) _artworkLoader;
  final DateTime Function() _timerClock;
  final Random _random;
  final Set<int> _requestedArtwork = {};
  final ValueNotifier<SleepTimerState?> sleepTimer = ValueNotifier(null);
  Timer? _sleepTick;
  int? _sleepIndex;
  Duration _sleepPosition = Duration.zero;
  PlaybackStore Function(NavidromeClient)? _storeFactory;
  PlaybackStore? _continuityStore;
  NavidromeClient? _continuityClient;
  int _accountEpoch = 0;
  Timer? _checkpointTimer;
  Future<void> _saving = Future.value();
  bool _checkpointQueued = false;
  String? _checkpointState;
  List<String?> _queueCovers = const [];
  _RestoredShuffleOrder? _restoredOrder;
  NavidromeClient? _queueClient;
  PlaybackSnapshot? _retrySnapshot;
  Timer? _reconnectTimer;
  int _reconnectEpoch = 0;
  int? _probeEpoch;
  int _reconnectAttempt = 0;
  int _healthyReloads = 0;
  DateTime? _lastPlaybackFailure;
  bool _reconnectWanted = false;
  bool get reconnecting => _reconnectWanted;
  bool get canRetryPlayback =>
      _retrySnapshot != null && _queueClient?.isClosed == false;
  final ValueNotifier<String?> continuityNotice = ValueNotifier(null);

  /// Called only after AccountSession has successfully verified this account.
  /// Temporary sign-ins never read or write a saved queue.
  Future<void> attachAccount(
    NavidromeClient client, {
    required bool remember,
  }) async {
    if (_disposed || identical(client, _continuityClient)) return;
    final epoch = ++_accountEpoch;
    final revision = _revision;
    _continuityClient = client;
    _continuityStore = null;
    _checkpointTimer?.cancel();
    continuityNotice.value = null;
    if (!remember || _storeFactory == null) return;
    final store = _storeFactory!(client);
    try {
      final saved = await store.read().timeout(const Duration(seconds: 3));
      if (_disposed || epoch != _accountEpoch || client.isClosed) return;
      _continuityStore = store;
      _checkpointTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (_player.playing) unawaited(savePlayback());
      });
      if (revision != _revision) {
        // A user selection/clear made while disk was loading takes precedence.
        if (_listeningTracks.isEmpty) {
          await store.clear();
        } else {
          await savePlayback();
        }
        return;
      }
      if (saved != null) {
        saved.validate();
        await _loadQueue(
          client,
          saved.tracks,
          saved.index,
          restored: saved,
          autoplay: false,
        );
      }
    } on Object {
      if (!_disposed && epoch == _accountEpoch) {
        _continuityStore = null; // Preserve unread or newer saved data.
        continuityNotice.value = 'Your saved queue could not be restored. You can still select music; reopen the app to try again.';
      }
    }
  }

  PlaybackSnapshot? _snapshot() {
    final index = _player.currentIndex;
    if (_loading ||
        _listeningTracks.isEmpty ||
        index == null ||
        index < 0 ||
        index >= _listeningTracks.length) {
      return null;
    }
    return PlaybackSnapshot(
      tracks: _listeningTracks,
      coverArtIds: _queueCovers,
      index: index,
      position: _player.position,
      shuffleOrder: _player.shuffleModeEnabled
          ? List.unmodifiable(_player.shuffleIndices)
          : const [],
      repeat: _player.loopMode.name,
      speed: _player.speed,
    );
  }

  Future<void> savePlayback() {
    final store = _continuityStore;
    final snapshot = _snapshot();
    if (_disposed ||
        store == null ||
        snapshot == null ||
        error.value != null ||
        !identical(_continuityClient, _listeningClient)) {
      return _saving;
    }
    final epoch = _accountEpoch;
    _saving = _saving.then((_) async {
      try {
        await store.write(snapshot);
        if (!_disposed && epoch == _accountEpoch) continuityNotice.value = null;
      } on Object {
        if (!_disposed && epoch == _accountEpoch) {
          continuityNotice.value = 'Playback continues, but your queue or position could not be saved.';
        }
      }
    });
    return _saving;
  }

  void _scheduleCheckpoint() {
    if (_checkpointQueued ||
        _disposed ||
        _loading ||
        _continuityStore == null) {
      return;
    }
    _checkpointQueued = true;
    scheduleMicrotask(() {
      _checkpointQueued = false;
      if (!_disposed) unawaited(savePlayback());
    });
  }

  Future<void> suspendForAccountSwitch() async {
    final saving = savePlayback();
    ++_accountEpoch;
    _continuityClient = null;
    _continuityStore = null;
    _checkpointTimer?.cancel();
    await reset(clearSaved: false);
    await saving;
  }

  Track? trackAt(int index) => index >= 0 && index < _listeningTracks.length
      ? _listeningTracks[index]
      : null;

  /// Entries before/after the selected occurrence in playback order, including
  /// duplicate songs. Earlier entries are not necessarily listening history.
  List<int> get earlierIndices => _queueIndices(beforeCurrent: true);
  List<int> get upcomingIndices => _queueIndices(beforeCurrent: false);

  List<int> _queueIndices({required bool beforeCurrent}) {
    final current = _player.currentIndex;
    if (current == null) return const [];
    final order = _player.shuffleModeEnabled
        ? _player.shuffleIndices
        : List.generate(queue.value.length, (i) => i);
    final at = order.indexOf(current);
    if (at < 0) return const [];
    return (beforeCurrent ? order.take(at) : order.skip(at + 1)).toList();
  }

  void setSleepTimer({Duration? duration, bool endOfTrack = false}) {
    cancelSleepTimer();
    if (mediaItem.value == null || (duration == null && !endOfTrack)) return;
    if (duration != null && duration <= Duration.zero) return;
    _sleepIndex = _player.currentIndex;
    _sleepPosition = _player.position;
    sleepTimer.value = SleepTimerState(
      deadline: duration == null ? null : _timerClock().add(duration),
      endOfTrack: endOfTrack,
    );
    _sleepTick = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => _checkSleepTimer(),
    );
  }

  void cancelSleepTimer() {
    _sleepTick?.cancel();
    _sleepTick = null;
    sleepTimer.value = null;
    _sleepIndex = null;
  }

  void _checkSleepTimer() {
    final timer = sleepTimer.value;
    if (timer == null || _disposed || _loading) return;
    final expired =
        timer.deadline != null && !_timerClock().isBefore(timer.deadline!);
    final ended =
        timer.endOfTrack &&
        (_player.processingState == ProcessingState.completed ||
            _player.currentIndex != _sleepIndex ||
            (!_seeking &&
                _sleepPosition > const Duration(seconds: 2) &&
                _player.position < const Duration(seconds: 1)));
    _sleepPosition = _player.position;
    if (expired || ended) {
      cancelSleepTimer();
      final revision = _revision;
      // Native events may be synchronous. Defer commands until the stream
      // callback returns so a nested event cannot put playback into error.
      scheduleMicrotask(() {
        if (!_disposed && revision == _revision) unawaited(pause());
      });
    }
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) =>
      _changeSetting(() async {
        await _player.setLoopMode(switch (repeatMode) {
          AudioServiceRepeatMode.one => LoopMode.one,
          AudioServiceRepeatMode.all ||
          AudioServiceRepeatMode.group => LoopMode.all,
          _ => LoopMode.off,
        });
        _publishState();
      });

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) =>
      _changeSetting(() async {
        final enabled = shuffleMode != AudioServiceShuffleMode.none;
        if (enabled) {
          _restoredOrder?.reshuffle = true;
          try {
            await _player.shuffle();
          } finally {
            _restoredOrder?.reshuffle = false;
          }
        }
        await _player.setShuffleModeEnabled(enabled);
        _publishState();
      });

  @override
  Future<void> setSpeed(double speed) {
    if (!speed.isFinite || speed < .5 || speed > 2 || !canEditSongSettings) {
      return Future.value();
    }
    return _queueSongSettings(
      (value) => SongPlaybackSettings(speed: speed, keepPitch: value.keepPitch),
    );
  }

  Future<void> adjustSpeed(double delta) {
    if (!delta.isFinite || !canEditSongSettings) return Future.value();
    return _queueSongSettings(
      (value) => SongPlaybackSettings(
        speed: (((value.speed + delta).clamp(.5, 2)) * 100).round() / 100,
        keepPitch: value.keepPitch,
      ),
    );
  }

  Future<void> setKeepPitch(bool enabled) {
    if (!canEditSongSettings) return Future.value();
    if (!supportsPitchControl) {
      settingsError.value = 'Pitch control is unavailable on this device.';
      return Future.value();
    }
    return _queueSongSettings(
      (value) => SongPlaybackSettings(speed: value.speed, keepPitch: enabled),
    );
  }

  void _selectSongSettings(String? key) {
    _activeSongKey = key;
    ++_songSettingsEpoch;
    // A stalled command for an abandoned song must not hold up another song.
    _songSettingsPending = Future.value();
    songPlaybackSettings.value = key == null
        ? const SongPlaybackSettings()
        : songPlaybackStore.get(key);
  }

  bool _songIsCurrent(String key, int epoch) =>
      !_disposed && _activeSongKey == key && _songSettingsEpoch == epoch;

  Future<bool> _applySongSettings(
    SongPlaybackSettings value,
    bool Function() current,
  ) async {
    if (!current()) return false;
    if (supportsPitchControl && _player.preservesPitch != value.keepPitch) {
      await _player.setPreservesPitch(value.keepPitch);
    }
    if (!current()) return false;
    if (_player.speed != value.speed) await _player.setSpeed(value.speed);
    return current();
  }

  Future<void> _queueSongSettings([
    SongPlaybackSettings Function(SongPlaybackSettings)? change,
  ]) {
    final key = _activeSongKey;
    final epoch = _songSettingsEpoch;
    if (key == null) return Future.value();
    bool current() => _songIsCurrent(key, epoch) && !_loading;
    _songSettingsPending = _songSettingsPending.then((_) async {
      if (!current()) return;
      final saved = songPlaybackStore.get(key);
      final value = change == null ? saved : change(saved);
      try {
        if (!await _applySongSettings(value, current)) {
          _repairCurrentSongSettings();
          return;
        }
        if (change != null) unawaited(songPlaybackStore.set(key, value));
        songPlaybackSettings.value = value;
        settingsError.value = null;
        _publishState();
        _scheduleCheckpoint();
      } on Object {
        if (current()) {
          settingsError.value =
              'Could not change this song\'s audio settings. Try again.';
        } else {
          _repairCurrentSongSettings();
        }
      }
    });
    return _songSettingsPending;
  }

  Future<bool> _restoreSongSettings(
    SongPlaybackSettings value,
    bool Function() current,
  ) async {
    try {
      final applied = await _applySongSettings(value, current);
      if (applied) settingsError.value = null;
      return applied;
    } on Object {
      if (!current()) return false;
      // A rejected setting is not a failed stream. Keep the saved choice for
      // another attempt, and let the song play with the available settings.
      settingsError.value = 'Could not apply this song\'s saved audio settings. Adjust the tempo or pitch to try again.';
      return true;
    }
  }

  void _repairCurrentSongSettings() {
    // Native events can be synchronous; don't issue nested commands from them.
    scheduleMicrotask(() {
      if (canEditSongSettings) unawaited(_queueSongSettings());
    });
  }

  void _syncSongSettings() {
    if (_disposed || _loading || error.value != null) return;
    final client = _listeningClient;
    final track = trackAt(_player.currentIndex ?? -1);
    if (client == null || track == null) return;
    final key = SongPlaybackStore.keyFor(client, track);
    if (key == _activeSongKey) return;
    _selectSongSettings(key);
    _repairCurrentSongSettings();
  }

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
        _scheduleCheckpoint();
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
    bool shuffle = false,
  }) => _loadQueue(
    client,
    tracks,
    index,
    coverArtId: coverArtId,
    shuffle: shuffle,
  );

  Future<void> _loadQueue(
    NavidromeClient client,
    List<Track> tracks,
    int index, {
    String? coverArtId,
    bool shuffle = false,
    PlaybackSnapshot? restored,
    bool autoplay = true,
    bool preserveSleepTimer = false,
    bool automaticRecovery = false,
    bool verificationRecovery = false,
  }) {
    if (tracks.isEmpty || index < 0 || index >= tracks.length) {
      return Future.value();
    }
    if (shuffle) index = _random.nextInt(tracks.length);
    _cancelReconnect(resetBudget: !automaticRecovery);
    final revision = ++_revision;
    _verificationRecoveryRevision = verificationRecovery ? revision : null;
    _queueClient = client;
    _retrySnapshot =
        restored ??
        PlaybackSnapshot(
          tracks: List.unmodifiable(tracks),
          coverArtIds: List.unmodifiable(
            tracks.map((track) => track.coverArt ?? coverArtId),
          ),
          index: index,
          position: Duration.zero,
          repeat: _player.loopMode.name,
          speed: _player.speed,
        );
    if (!preserveSleepTimer) cancelSleepTimer();
    _requestedArtwork.clear();
    _clearListening();
    _loading = true;
    _selectSongSettings(SongPlaybackStore.keyFor(client, tracks[index]));
    _playWhenReady = autoplay;
    _checkpointState = null;
    error.value = null;
    _publishState();
    _pending = _pending.then((_) async {
      if (revision != _revision) return;
      _loading = true;
      try {
        if (_needsPlaybackReset) {
          // Reloading items can retain a failed AVPlayer/decoder. Stop releases
          // the native instance; the next load reactivates it with our saved
          // queue, position, rate, repeat, shuffle and volume.
          _resettingPlayback = true;
          try {
            await _player.stop();
            await _resetSourcePlayback();
            _needsPlaybackReset = false;
          } finally {
            _resettingPlayback = false;
          }
        } else {
          await _player.pause();
        }
        if (revision != _revision) return;
        // Read the selected song's choice before loading/playing, independently
        // of older controls that may be waiting on a failed native load.
        final value = songPlaybackStore.get(
          SongPlaybackStore.keyFor(client, tracks[index]),
        );
        if (!await _restoreSongSettings(
          value,
          () => !_disposed && revision == _revision,
        )) {
          return;
        }
        if (revision != _revision) return;
        await _player.setShuffleModeEnabled(false);
        if (revision != _revision) return;
        _queueCovers =
            restored?.coverArtIds ??
            List.unmodifiable(
              tracks.map((track) => track.coverArt ?? coverArtId),
            );
        _restoredOrder = restored != null && restored.shuffleOrder.isNotEmpty
            ? _RestoredShuffleOrder(restored.shuffleOrder)
            : null;
        final items = tracks.indexed
            .map(
              (entry) => MediaItem(
                id: entry.$2.id,
                title: entry.$2.title,
                artist: entry.$2.artist,
                album: entry.$2.album,
                duration: entry.$2.duration,
                extras: {
                  'coverArtId': ?_queueCovers[entry.$1],
                  'starred': entry.$2.starred,
                  'audioDetails': _audioDetails(entry.$2),
                  'sourceArtwork': ?entry.$2.source?.artwork?.toString(),
                  'external': entry.$2.source != null,
                },
              ),
            )
            .toList();
        queue.add(items);
        mediaItem.add(items[index]);
        final loadFailure = Completer<Duration?>();
        _loadFailure = loadFailure;
        try {
          await Future.any<Duration?>([
            loadFailure.future,
            Future<Duration?>.sync(
              () => _player.setAudioSources(
                tracks.indexed
                    .map(
                      (entry) => AudioSource.uri(
                        entry.$2.source == null
                            ? client.streamUri(entry.$2.id)
                            : _sourceStreamUri(entry.$2.source!),
                        tag: items[entry.$1],
                      ),
                    )
                    .toList(),
                initialIndex: index,
                initialPosition: restored?.safePosition ?? Duration.zero,
                // Show a restored queue immediately without fetching audio until Play.
                preload: restored == null || autoplay,
                shuffleOrder: _restoredOrder,
              ),
            ),
          ]);
        } finally {
          if (identical(_loadFailure, loadFailure)) _loadFailure = null;
        }
        if (revision != _revision) return;
        if (restored != null) {
          // With preload:false, just_audio defers initial seek values until
          // activation. Seek its idle player too so the paused UI and next
          // checkpoint use the saved song/position before the user presses Play.
          if (!autoplay) {
            await _player.seek(restored.safePosition, index: index);
            if (revision != _revision) return;
          }
          await _player.setLoopMode(LoopMode.values.byName(restored.repeat));
          if (revision != _revision) return;
          await _player.setShuffleModeEnabled(restored.shuffleOrder.isNotEmpty);
          if (revision != _revision) return;
        }
        if (shuffle) {
          // just_audio puts the selected random starting track first in its
          // shuffle traversal, while retaining the collection's original order.
          await _player.shuffle();
          if (revision != _revision) return;
          await _player.setShuffleModeEnabled(true);
          if (revision != _revision) return;
        }
        // A late command from the previous song can settle during this load.
        // Reconcile once more before allowing audio to start.
        if (!await _restoreSongSettings(
          value,
          () => !_disposed && revision == _revision,
        )) {
          return;
        }
        _loading = false;
        _listeningClient = client;
        _listeningTracks = List.unmodifiable(tracks);
        _retrySnapshot = null;
        _publishItem();
        _publishState();
        _scheduleCheckpoint();
        if (_playWhenReady) {
          unawaited(_play(automaticRecovery: automaticRecovery));
        }
      } on Object catch (failure) {
        if (revision == _revision) {
          _loading = false;
          _reportFailure();
          if (failure is SourceException) {
            _cancelReconnect();
            error.value = failure.message;
            _publishState();
          }
        }
      }
    });
    return _pending;
  }

  void _publishItem() {
    if (_loading) return;
    _syncSongSettings();
    final index = _player.currentIndex;
    if (index != null && index >= 0 && index < queue.value.length) {
      final item = queue.value[index];
      mediaItem.add(item.copyWith(duration: _player.duration ?? item.duration));
      _loadArtwork(index);
    }
    _syncListening();
  }

  void _publishState() {
    _checkSleepTimer();
    _publishItem();
    _syncListening();
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
          if (!_loading && mediaItem.value != null) MediaControl.skipToPrevious,
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
        shuffleMode: _player.shuffleModeEnabled
            ? AudioServiceShuffleMode.all
            : AudioServiceShuffleMode.none,
        repeatMode: switch (_player.loopMode) {
          LoopMode.off => AudioServiceRepeatMode.none,
          LoopMode.one => AudioServiceRepeatMode.one,
          LoopMode.all => AudioServiceRepeatMode.all,
        },
        errorCode: error.value == null ? null : 1,
        errorMessage: error.value,
      ),
    );
    final checkpointState =
        '${_player.currentIndex}:${_player.playing}:${_player.loopMode}:${_player.shuffleModeEnabled}:${_player.speed}';
    if (!_loading && checkpointState != _checkpointState) {
      _checkpointState = checkpointState;
      _scheduleCheckpoint();
    }
  }

  void _loadArtwork(int index) {
    final client = _listeningClient;
    final item = queue.value[index];
    final id = item.extras?['coverArtId'] as String?;
    final external = publicArtwork(item.extras?['sourceArtwork']);
    if (client == null ||
        (id == null && external == null) ||
        item.artUri != null ||
        !_requestedArtwork.add(index)) {
      return;
    }
    final revision = _revision;
    unawaited(() async {
      Uri? uri;
      try {
        uri = external == null
            ? await _artworkLoader(client, id!)
            : await _sourceArtwork.loadExternal(external);
      } on Object {
        return;
      }
      if (_disposed ||
          revision != _revision ||
          uri == null ||
          uri.scheme != 'file') {
        return;
      }
      final items = List<MediaItem>.of(queue.value);
      items[index] = items[index].copyWith(artUri: uri);
      queue.add(items);
      if (_player.currentIndex == index) _publishItem();
    }());
  }

  void _clearListening() {
    _listeningGeneration++;
    _listenTimer?.cancel();
    _listenTimer = null;
    _listenTracker.clear();
    _listeningClient = null;
    _listeningTracks = const [];
    _listeningIndex = null;
    if (!_disposed) listeningNotice.value = null;
  }

  void _syncListening() {
    if (_disposed) return;
    final index = _player.currentIndex;
    if (!preferences.reportListens) {
      _listenTracker.clear();
      _listeningIndex = null;
    }
    if (_loading ||
        _listeningClient == null ||
        !preferences.reportListens ||
        index == null ||
        index < 0 ||
        index >= _listeningTracks.length) {
      _listenTimer?.cancel();
      _listenTimer = null;
      return;
    }
    if (_listeningIndex != index) {
      if (_listeningIndex case final int previous) {
        _listenTracker.update(
          active: false,
          duration: _listeningTracks[previous].duration,
        );
      }
      _listeningIndex = index;
      _listenTracker.begin(
        _listeningTracks[index].id,
        _player.duration ?? _listeningTracks[index].duration,
      );
    }
    final active =
        !_seeking &&
        _listeningTracks[index].source == null &&
        error.value == null &&
        _player.playing &&
        _player.processingState == ProcessingState.ready;
    _listenTracker.update(
      active: active,
      duration: _player.duration ?? _listeningTracks[index].duration,
    );
    if (active && _listenTracker.pending) {
      _listenTimer ??= Timer.periodic(
        const Duration(seconds: 1),
        (_) => _syncListening(),
      );
    } else {
      _listenTimer?.cancel();
      _listenTimer = null;
    }
  }

  void _submitListen(String trackId, DateTime startedAt) {
    final client = _listeningClient;
    final generation = _listeningGeneration;
    if (client == null || _disposed || !preferences.reportListens) return;
    // The tracker can finish the previous item during a native transition.
    // Look up its ID instead of using the player's already advanced index.
    final track = _listeningTracks.firstWhere((track) => track.id == trackId);
    if (track.source != null) return;
    client.recordLocalListen(track, startedAt);
    unawaited(() async {
      try {
        await client.scrobble(trackId, startedAt);
      } on Object {
        if (!_disposed && generation == _listeningGeneration) {
          listeningNotice.value = 'A listen could not be confirmed. It was not retried to avoid counting it twice.';
        }
      }
    }());
  }

  Future<void> _seekCommand(Future<void> Function() command) async {
    final previousSongKey = _activeSongKey;
    _seeking = true;
    _syncListening();
    try {
      await _command(command);
    } finally {
      _seeking = false;
      _publishItem();
      if (canEditSongSettings && _activeSongKey != previousSongKey) {
        await _queueSongSettings();
      }
      _publishState();
      _scheduleCheckpoint();
    }
  }

  void _reportFailure() {
    if (_disposed || _resettingPlayback) return;
    _needsPlaybackReset = true;
    // Some native failures arrive on the error stream before (or without)
    // completing the load call. Free the serialized queue so a retry can reach
    // stop/reset; a late native result is observed but cannot resume this load.
    final loadFailure = _loadFailure;
    if (loadFailure != null && !loadFailure.isCompleted) {
      loadFailure.completeError(StateError('Playback load failed'));
    }
    _retrySnapshot ??= _snapshot();
    // A failed initial load has no listening tracks or native current index.
    // The intended queue still identifies the source whose resolver failed.
    final snapshot = _retrySnapshot;
    final failedTrack = snapshot == null
        ? trackAt(_player.currentIndex ?? -1)
        : snapshot.tracks[snapshot.index];
    final sourceIssue = failedTrack?.source != null
        ? MusicSources.instance.extensions?.issue.value
        : null;
    final needsVerification =
        sourceIssue != null &&
        failedTrack?.source != null &&
        MusicSources.instance.needsPlaybackVerification(failedTrack!.source!);
    final wantedPlayback = _playWhenReady || _reconnectWanted;
    final now = _timerClock();
    if (_lastPlaybackFailure == null ||
        now.difference(_lastPlaybackFailure!) > const Duration(minutes: 1)) {
      _healthyReloads = 0;
    }
    _lastPlaybackFailure = now;
    _reconnectWanted =
        (_reconnectWanted || _playWhenReady) &&
        canRetryPlayback &&
        !needsVerification;
    _playWhenReady = false;
    error.value =
        sourceIssue ??
        (_reconnectWanted
            ? 'Playback interrupted. Reconnecting automatically. Press Play to retry now.'
            : canRetryPlayback
            ? 'Playback failed. Press Play to retry or select another track.'
            : 'Playback failed. Select a track to start a new queue.');
    _scheduleReconnect();
    _publishState();
    if (needsVerification &&
        wantedPlayback &&
        snapshot != null &&
        _verificationRecoveryRevision != _revision) {
      unawaited(_verifyAndResume(snapshot, _reconnectEpoch));
    }
  }

  Future<void> _verifyAndResume(PlaybackSnapshot snapshot, int epoch) async {
    if (_sourceVerificationEpoch == epoch) return;
    _sourceVerificationEpoch = epoch;
    try {
      final verified = await _verifySource(
        snapshot.tracks[snapshot.index].source!,
      );
      // Pause, a different queue, an account change and disposal win over a
      // browser callback. Verification must never restart abandoned playback.
      if (_disposed || epoch != _reconnectEpoch) return;
      if (!verified) {
        error.value =
            'Verification was not completed. Press Play to try again.';
        _publishState();
        return;
      }
      final client = _queueClient;
      if (client == null || client.isClosed) return;
      await _loadQueue(
        client,
        snapshot.tracks,
        snapshot.index,
        restored: snapshot,
        preserveSleepTimer: true,
        verificationRecovery: true,
      );
    } on Object catch (failure) {
      if (!_disposed && epoch == _reconnectEpoch) {
        error.value = failure is SourceException
            ? failure.message
            : 'Verification could not finish. Press Play to try again.';
        _publishState();
      }
    } finally {
      if (_sourceVerificationEpoch == epoch) _sourceVerificationEpoch = null;
    }
  }

  void _cancelReconnect({bool resetBudget = true}) {
    _reconnectEpoch++;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _probeEpoch = null;
    _reconnectWanted = false;
    if (resetBudget) {
      _reconnectAttempt = 0;
      _healthyReloads = 0;
      _lastPlaybackFailure = null;
    }
  }

  void _scheduleReconnect() {
    if (_disposed ||
        !_reconnectWanted ||
        _reconnectTimer != null ||
        _probeEpoch != null) {
      return;
    }
    final seconds = [2, 5, 10, 20, 30][_reconnectAttempt.clamp(0, 4)];
    _reconnectAttempt++;
    _reconnectTimer = Timer(Duration(seconds: seconds), retryConnectionNow);
  }

  /// A foreground return can retry immediately rather than waiting for a timer
  /// that iOS suspended. Play always remains available as a manual retry.
  void retryConnectionNow() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    if (_disposed || !_reconnectWanted || _probeEpoch != null) return;
    unawaited(_tryReconnect(_reconnectEpoch));
  }

  Future<void> _tryReconnect(int epoch) async {
    final client = _queueClient;
    final snapshot = _retrySnapshot;
    if (client == null || client.isClosed || snapshot == null) {
      _cancelReconnect();
      return;
    }
    _probeEpoch = epoch;
    var reachable = false;
    var rejected = false;
    String? sourceError;
    try {
      final external = snapshot.tracks[snapshot.index].source;
      if (external == null) {
        await client.ping();
      } else {
        _sourceStreamUri(external);
      }
      reachable = true;
    } on NavidromeException catch (failure) {
      rejected = failure.authenticationRejected;
    } on SourceException catch (failure) {
      sourceError = failure.message;
    } on Object {
      // Native/request details can contain authenticated URLs. Never expose them.
    } finally {
      if (_probeEpoch == epoch) _probeEpoch = null;
    }
    if (_disposed || epoch != _reconnectEpoch || !_reconnectWanted) return;
    if (sourceError != null) {
      _cancelReconnect();
      error.value = sourceError;
      _publishState();
      return;
    }
    if (rejected) {
      _cancelReconnect();
      error.value = 'Your server sign-in was rejected. Check your account in Home > Servers, then press Play to retry.';
      _publishState();
      return;
    }
    if (!reachable) {
      _healthyReloads = 0;
      _scheduleReconnect();
      return;
    }
    // A healthy server plus a repeatedly failing stream can mean a removed or
    // unsupported file. Do not endlessly reload the queue in that case.
    if (_healthyReloads >= 2) {
      _cancelReconnect();
      error.value = snapshot.tracks[snapshot.index].source != null
          ? 'This music source could not play the song. Press Play to retry or select another audio source.'
          : 'The server is reachable, but this song could not play. Press Play to retry or select another track.';
      _publishState();
      return;
    }
    _healthyReloads++;
    await _loadQueue(
      client,
      snapshot.tracks,
      snapshot.index,
      restored: snapshot,
      preserveSleepTimer: true,
      automaticRecovery: true,
    );
  }

  Future<void> _command(Future<void> Function() command) async {
    final revision = _revision;
    try {
      await command();
    } on Object {
      if (!_disposed && revision == _revision) _reportFailure();
    }
  }

  @override
  Future<void> play() => _play();

  Future<void> _play({bool automaticRecovery = false}) async {
    if (_disposed) return;
    if (!automaticRecovery) _cancelReconnect();
    _playWhenReady = true;
    if (_loading) {
      _publishState();
      return;
    }
    if (mediaItem.value == null && !canRetryPlayback) return;
    if (error.value != null ||
        _player.processingState == ProcessingState.idle) {
      // Seeking the idle just_audio player updates its visible state but clears
      // its deferred initial seek. Native activation would then load index 0.
      // Capture the live paused state (including edits) and preload explicitly
      // before Play. Use the same serialization/revision guards as queue loads.
      final retrying = error.value != null;
      final snapshot = retrying ? _retrySnapshot ?? _snapshot() : _snapshot();
      final client = _queueClient;
      if (snapshot != null && client != null && !client.isClosed) {
        await _loadQueue(
          client,
          snapshot.tracks,
          snapshot.index,
          restored: snapshot,
          preserveSleepTimer: true,
          automaticRecovery: automaticRecovery,
        );
      }
      return;
    }
    await _command(() async {
      if (_player.processingState == ProcessingState.completed) {
        _listenTracker.clear();
        _listeningIndex = null;
        await _seekCommand(() => _player.seek(Duration.zero, index: 0));
      }
      // The play future completes only when playback ends or pauses.
      unawaited(_command(_player.play));
    });
  }

  @override
  Future<void> pause() async {
    _cancelReconnect();
    _playWhenReady = false;
    if (error.value != null) {
      error.value = 'Playback paused. Press Play to retry.';
    }
    await _command(_player.pause);
    _publishState();
  }

  @override
  Future<void> seek(Duration position) async {
    if (!_loading) await _seekCommand(() => _player.seek(position));
  }

  @override
  Future<void> skipToNext() async {
    if (!_loading && _player.hasNext) await _seekCommand(_player.seekToNext);
  }

  @override
  Future<void> skipToPrevious() async {
    if (_loading || mediaItem.value == null || error.value != null) return;
    await _seekCommand(() async {
      final index = _player.currentIndex ?? 0;
      final previous =
          _player.position < const Duration(seconds: 3) && _player.hasPrevious;
      if (previous) {
        await _player.seekToPrevious();
      } else {
        await _player.seek(Duration.zero, index: index);
      }
      _publishItem();
      _publishState();
    });
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (!_loading &&
        error.value != null &&
        _retrySnapshot != null &&
        _queueClient != null) {
      final saved = _retrySnapshot!;
      if (index < 0 || index >= saved.tracks.length) return;
      await _loadQueue(
        _queueClient!,
        saved.tracks,
        index,
        restored: PlaybackSnapshot(
          tracks: saved.tracks,
          coverArtIds: saved.coverArtIds,
          index: index,
          position: Duration.zero,
          shuffleOrder: saved.shuffleOrder,
          repeat: saved.repeat,
          speed: saved.speed,
        ),
      );
      return;
    }
    if (!_loading && index >= 0 && index < queue.value.length) {
      await _seekCommand(() => _player.seek(Duration.zero, index: index));
    }
  }

  Future<void> moveUpcoming(int from, int to) => _editQueue(from, to);
  Future<void> removeUpcoming(int index) => _editQueue(index, null);

  Future<void> _editQueue(int from, int? to) {
    final upcoming = upcomingIndices;
    if (_loading ||
        !upcoming.contains(from) ||
        (to != null &&
            (!upcoming.contains(to) ||
                from == to ||
                _player.shuffleModeEnabled))) {
      return Future.value();
    }
    final revision = ++_revision;
    _requestedArtwork.clear();
    _syncListening();
    _playWhenReady = _player.playing;
    _loading = true;
    _publishState();
    _pending = _pending.then((_) async {
      if (revision != _revision) return;
      final items = List<MediaItem>.of(queue.value);
      final tracks = List<Track>.of(_listeningTracks);
      final covers = List<String?>.of(_queueCovers);
      try {
        if (to == null) {
          await _player.removeAudioSourceAt(from);
          items.removeAt(from);
          tracks.removeAt(from);
          covers.removeAt(from);
        } else {
          await _player.moveAudioSource(from, to);
          items.insert(to, items.removeAt(from));
          tracks.insert(to, tracks.removeAt(from));
          covers.insert(to, covers.removeAt(from));
        }
        if (revision != _revision) return;
        _listeningTracks = tracks;
        _queueCovers = covers;
        // The current song has not changed; preserve its listen progress.
        _listeningIndex = _player.currentIndex;
        if (sleepTimer.value?.endOfTrack == true) {
          _sleepIndex = _player.currentIndex;
        }
        queue.add(items);
      } on Object {
        // A native edit may have partially applied. Clear rather than play a
        // queue whose native indexes no longer match our metadata.
        if (revision == _revision) {
          await _command(_player.stop);
          await _command(_player.clearAudioSources);
          if (revision != _revision) return;
          cancelSleepTimer();
          _clearListening();
          queue.add([]);
          mediaItem.add(null);
          _reportFailure();
        }
      } finally {
        if (revision == _revision) {
          _loading = false;
          _publishItem();
          _publishState();
          _scheduleCheckpoint();
        }
      }
    });
    return _pending;
  }

  @override
  Future<void> stop() => reset();

  Future<void> reset({bool clearSaved = true}) {
    _selectSongSettings(null);
    _cancelReconnect();
    _retrySnapshot = null;
    _queueClient = null;
    final store = clearSaved ? _continuityStore : null;
    final epoch = _accountEpoch;
    if (store != null) {
      _saving = _saving.then((_) async {
        try {
          await store.clear();
          if (!_disposed && epoch == _accountEpoch) {
            continuityNotice.value = null;
          }
        } on Object {
          if (!_disposed && epoch == _accountEpoch) {
            continuityNotice.value = 'The queue was cleared here, but its saved copy could not be removed.';
          }
        }
      });
    }
    ++_revision;
    cancelSleepTimer();
    _requestedArtwork.clear();
    _clearListening();
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
    return Future.wait([_pending, _saving]);
  }

  Future<void> dispose() async {
    _cancelReconnect();
    final saving = savePlayback();
    _checkpointTimer?.cancel();
    _disposed = true;
    _sourcePlaybackInfo.removeListener(_publishSourceInfo);
    ++_revision; // A late native load must not autoplay while storage drains.
    await saving;
    _clearListening();
    preferences.removeListener(_syncListening);
    await _settingsPending;
    await preferences.flush();
    await reset(clearSaved: false);
    await songPlaybackStore.flush();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _player.dispose();
    error.dispose();
    settingsError.dispose();
    listeningNotice.dispose();
    sleepTimer.dispose();
    continuityNotice.dispose();
    songPlaybackSettings.dispose();
    songPlaybackStore.dispose();
    preferences.dispose();
  }
}

/// just_audio reshuffles during native loads. Keep the saved traversal through
/// those loads; only an explicit user shuffle generates a fresh order.
class _RestoredShuffleOrder extends DefaultShuffleOrder {
  _RestoredShuffleOrder(this.saved);
  final List<int> saved;
  bool _inserted = false;
  bool reshuffle = false;

  @override
  void insert(int index, int count) {
    if (!_inserted && index == 0 && count == saved.length) {
      indices.addAll(saved);
      _inserted = true;
    } else {
      super.insert(index, count);
    }
  }

  @override
  void shuffle({int? initialIndex}) {
    if (reshuffle) super.shuffle(initialIndex: initialIndex);
  }
}
