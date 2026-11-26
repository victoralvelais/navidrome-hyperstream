import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/source_reference.dart';
import 'account_store.dart';
import 'music_provider.dart';
import 'mornye_sources.dart';
import 'mornye_provider.dart';
import 'source_stream_proxy.dart';

class OnlineSource {
  const OnlineSource(this.id, this.name);
  final String id, name;
}

class MusicSources extends ChangeNotifier {
  MusicSources({
    Future<String?> Function()? read,
    Future<void> Function(String)? write,
    this.httpClient,
    this.extensions,
  }) : _read =
           read ?? (() => SecureAccountStore.defaultStorage.read(key: _key)),
       _write =
           write ??
           ((value) => SecureAccountStore.defaultStorage.write(
             key: _key,
             value: value,
           )) {
    extensions?.addListener(notifyListeners);
    if (extensions != null) {
      _proxy = SourceStreamProxy(
        extensions!,
        onMedia: (track, info) {
          final updated = Map<String, SourcePlaybackInfo>.of(
            playbackInfo.value,
          );
          if (updated[track.identity]?.label == info.label) return;
          updated[track.identity] = info;
          if (updated.length > 512) updated.remove(updated.keys.first);
          playbackInfo.value = Map.unmodifiable(updated);
        },
      );
    }
  }

  static final instance = MusicSources(extensions: MornyeSources.instance);
  static const defaultEndpoint = 'https://tracks.monochrome.st';
  static const _key = 'hyperstream.music-sources.v1';
  final Future<String?> Function() _read;
  final Future<void> Function(String) _write;
  final http.Client Function()? httpClient;
  final MornyeSources? extensions;
  SourceStreamProxy? _proxy;
  final playbackInfo = ValueNotifier<Map<String, SourcePlaybackInfo>>({});
  bool _playbackInitialized = false;
  bool get hasProviders => enabled || extensions?.enabled.isNotEmpty == true;
  String? get selectedProvider =>
      extensions?.selected ??
      (enabled ? sourceId : extensions?.enabled.firstOrNull?.id);
  List<OnlineSource> get onlineSources => [
    for (final extension in extensions?.enabled ?? <MornyeExtension>[])
      OnlineSource('mornye:${extension.id}', extension.name),
    if (enabled) OnlineSource(sourceId, 'Monochrome'),
  ];
  String? _searchSource;

  /// Null means all enabled sources, including for existing installations.
  String? get searchSource =>
      onlineSources.any((e) => e.id == _searchSource) ? _searchSource : null;
  String get searchLabel =>
      onlineSources.where((e) => e.id == searchSource).firstOrNull?.name ??
      'All sources';
  String get searchSignature =>
      '${searchSource ?? '*'}|${onlineSources.map((e) => e.id).join('|')}';
  Future<void>? _restoring;
  bool _loaded = false;
  bool busy = false;
  bool enabled = false;
  String endpoint = defaultEndpoint;
  String? error;

  String get sourceId =>
      'monochrome-${sha256.convert(utf8.encode(endpoint)).toString().substring(0, 16)}';

  static Uri parseEndpoint(String input) {
    final uri = Uri.tryParse(input.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException(
        'Enter an HTTPS source URL without credentials, a query, or a fragment.',
      );
    }
    return uri.replace(path: uri.path.replaceFirst(RegExp(r'/+$'), ''));
  }

  Future<void> restore() {
    if (_loaded) return Future.value();
    return _restoring ??= _restore().whenComplete(() => _restoring = null);
  }

  Future<void> _restore() async {
    if (extensions != null) {
      await extensions!.restore();
      await _proxy!.start();
      _playbackInitialized = true;
    }
    try {
      final raw = await _read().timeout(const Duration(seconds: 10));
      if (raw != null) {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        if (data['schema'] != 1) throw const FormatException();
        endpoint = parseEndpoint(data['endpoint'] as String).toString();
        enabled = data['enabled'] as bool;
        _searchSource = data['searchSource'] as String?;
      }
      _loaded = true;
      error = null;
    } on Object {
      error = 'Could not read your music source settings. Unlock your device and try again.';
    }
    notifyListeners();
  }

  Future<void> save({required String endpoint, required bool enabled}) async {
    await _save(
      endpoint: endpoint,
      enabled: enabled,
      searchSource: _searchSource,
    );
  }

  Future<void> chooseSearchSource(String? id) async {
    if (id != null && !onlineSources.any((e) => e.id == id)) {
      throw const SourceException('Enable this source first.');
    }
    await _save(endpoint: endpoint, enabled: enabled, searchSource: id);
  }

  Future<void> _save({
    required String endpoint,
    required bool enabled,
    required String? searchSource,
  }) async {
    if (busy) {
      throw const SourceException('Music source settings are still saving.');
    }
    final uri = parseEndpoint(endpoint);
    busy = true;
    error = null;
    notifyListeners();
    try {
      await _restoring;
      final value = jsonEncode({
        'schema': 1,
        'endpoint': uri.toString(),
        'enabled': enabled,
        'searchSource': searchSource,
      });
      await _write(value);
      if (await _read() != value) throw const FormatException();
      this.endpoint = uri.toString();
      this.enabled = enabled;
      _searchSource = searchSource;
      _loaded = true;
    } on Object {
      error = 'Could not securely save the music source. Try again.';
      throw SourceException(error!);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  MusicProvider provider([SourceReference? track]) =>
      providerById(track?.sourceId);

  MusicProvider providerById([String? requested]) {
    final externalId = requested?.startsWith('mornye:') == true
        ? requested!.substring(7)
        : requested == null
        ? extensions?.selected ??
              (enabled ? null : extensions?.enabled.firstOrNull?.id)
        : null;
    if (externalId != null && extensions != null) {
      if (!extensions!.has(externalId)) {
        throw const SourceException(
          'Enable this provider in Home > Music sources.',
        );
      }
      return MornyeProvider(extensions!, externalId, _proxy!);
    }
    if (!enabled || (requested != null && requested != sourceId)) {
      throw const SourceException(
        'Enable this recording’s music source in Home > Music sources.',
      );
    }
    return MonochromeProvider(
      id: sourceId,
      baseUri: parseEndpoint(endpoint),
      client: httpClient?.call(),
    );
  }

  @override
  void dispose() {
    extensions?.removeListener(notifyListeners);
    _proxy?.close();
    playbackInfo.dispose();
    super.dispose();
  }

  Uri streamUri(SourceReference track) {
    final source = provider(track);
    try {
      return source.streamUri(track);
    } finally {
      source.close();
    }
  }

  Future<void> resetPlayback() async {
    extensions?.issue.value = null;
    if (_playbackInitialized) await _proxy!.restart();
  }

  SourceException? playbackFailure(SourceReference track) =>
      _proxy?.failureFor(track);

  bool needsPlaybackVerification(SourceReference track) {
    if (!track.sourceId.startsWith('mornye:') || extensions == null) {
      return false;
    }
    final catalog = track.sourceId.substring(7);
    final audio = catalog == 'spotify-web'
        ? extensions!.audioProvider
        : catalog;
    return audio != null && extensions!.verification.value == audio;
  }

  Future<bool> verifyPlayback(SourceReference track) async {
    if (!needsPlaybackVerification(track)) return false;
    return extensions!.requestVerification(extensions!.verification.value!);
  }
}
