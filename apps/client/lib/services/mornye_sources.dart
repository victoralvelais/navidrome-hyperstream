import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new_audio/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;
import 'package:mornye_host/mornye_host.dart';
import 'package:path_provider/path_provider.dart';

import 'account_store.dart';
import 'music_provider.dart';
import 'remote_transfer_background.dart';
import 'source_verification.dart';
import '../models/source_reference.dart';

class MornyeExtension {
  MornyeExtension(Map<String, dynamic> value)
    : id = value['id'] as String,
      name = value['display_name'] as String,
      version = value['version'] as String,
      url = Uri.parse(value['download_url'] as String),
      checksum = value['sha256'] as String,
      audio = value['audio'] == true,
      configurable = value['configurable'] != false,
      installed = value['installed'] == true,
      enabled = value['installed'] == true && value['enabled'] == true;
  final String id, name, version, checksum;
  final Uri url;
  final bool audio, configurable, installed, enabled;
  bool get requiresVerification => ['qobuz-web', 'tidal-web'].contains(id);
}

class ProviderVerificationRequired extends SourceException {
  ProviderVerificationRequired(this.providerId, {String? name})
    : super('${name ?? 'This source'} needs verification to continue.');
  final String providerId;
}

/// Owns device-only settings, encrypted extension state, and the native host.
/// Neither Navidrome nor remote-folder credentials cross this boundary.
class MornyeSources extends ChangeNotifier {
  MornyeSources({
    Future<dynamic> Function(Map<String, dynamic>)? native,
    Future<Directory> Function()? directory,
    Future<String?> Function(String)? read,
    Future<void> Function(String, String)? write,
    Future<String> Function(Uri, String)? authenticate,
  }) : _native = native ?? callMornye,
       _directory = directory ?? getApplicationSupportDirectory,
       _authenticate =
           authenticate ??
           ((url, scheme) => FlutterWebAuth2.authenticate(
             url: url.toString(),
             callbackUrlScheme: scheme,
             options: const FlutterWebAuth2Options(httpsHost: 'session-grant'),
           )),
       _read =
           read ?? ((key) => SecureAccountStore.defaultStorage.read(key: key)),
       _write =
           write ??
           ((key, value) =>
               SecureAccountStore.defaultStorage.write(key: key, value: value));
  static final instance = MornyeSources();
  final Future<dynamic> Function(Map<String, dynamic>) _native;
  final Future<Directory> Function() _directory;
  final Future<String?> Function(String) _read;
  final Future<void> Function(String, String) _write;
  final Future<String> Function(Uri, String) _authenticate;
  static const _masterKey = 'hyperstream.mornye.master.v1';
  static const _choicesKey = 'hyperstream.mornye.choices.v1';
  List<MornyeExtension> extensions = [];
  String? selected;
  String? audioProvider;
  String? error;
  String? busy;
  final issue = ValueNotifier<String?>(null);
  final verification = ValueNotifier<String?>(null);
  Future<bool> Function(String)? presentVerification;
  ({String id, Future<bool> result})? _verificationRequest;
  Directory? root;
  Future<void>? _initializing;
  bool _ready = false;
  Timer? _pump;
  bool _pumping = false;
  int _operations = 0;
  int revision = 0;

  Iterable<MornyeExtension> get enabled => extensions.where((e) => e.enabled);
  bool has(String id) => enabled.any((e) => e.id == id);
  String name(String id) =>
      extensions.where((e) => e.id == id).firstOrNull?.name ??
      musicSourceName('mornye:$id');
  static String nonce() => base64UrlEncode(
    List<int>.generate(24, (_) => Random.secure().nextInt(256)),
  ).replaceAll('=', '');

  Future<void> restore() =>
      _initializing ??= _restore().whenComplete(() => _initializing = null);
  Future<void> _restore() async {
    if (_ready) return;
    var failure = 'Music source storage could not open. Try again.';
    try {
      final support = await _directory();
      root = Directory('${support.path}/music-extensions');
      await root!.create(recursive: true);
      failure = 'Music source storage could not be prepared for background playback. Try again.';
      await RemoteTransferBackground().prepareDirectory(root!);
      failure = 'Saved music source access could not be read. Unlock your device and try again.';
      var key = await _read(_masterKey);
      if (key == null) {
        final data = Directory('${root!.path}/data');
        if (await data.exists() && !await data.list().isEmpty) {
          throw const SourceException(
            'Unlock your device to access saved music source sessions.',
          );
        }
        key = base64Encode(
          List<int>.generate(32, (_) => Random.secure().nextInt(256)),
        );
        failure = 'Music source access could not be saved securely. Try again.';
        await _write(_masterKey, key);
        if (await _read(_masterKey) != key) {
          throw const FormatException();
        }
      }
      failure = 'The music extension engine could not start. Restart Hyperstream and try again.';
      await _native({'op': 'init', 'root': root!.path, 'key': key});
      failure = 'Saved music source preferences could not be read. Try again.';
      final choices = await _read(_choicesKey);
      if (choices != null) {
        final value = jsonDecode(choices) as Map<String, dynamic>;
        selected = value['catalog'] as String?;
        audioProvider = value['audio'] as String?;
      }
      _ready = true;
      failure = 'The music extension catalog could not load. Try again.';
      await refresh();
      error = null;
    } on SourceException catch (exception) {
      _ready = false;
      error = exception.message;
    } on Object {
      _ready = false;
      error = failure;
    }
    notifyListeners();
  }

  Future<void> refresh() async {
    extensions = ((await _native({'op': 'list'})) as List)
        .map((e) => MornyeExtension(Map<String, dynamic>.from(e as Map)))
        .toList();
    if (selected != null && !has(selected!)) selected = enabled.firstOrNull?.id;
    if (audioProvider == null ||
        !enabled.any((e) => e.id == audioProvider && e.audio)) {
      audioProvider = enabled.where((e) => e.audio).firstOrNull?.id;
    }
    revision++;
    notifyListeners();
  }

  Future<void> choose({
    String? catalog,
    String? audio,
    bool legacy = false,
  }) async {
    final nextCatalog = legacy ? null : catalog ?? selected;
    final nextAudio = audio ?? audioProvider;
    if (nextCatalog != null && !has(nextCatalog)) {
      throw const SourceException('Enable this provider first.');
    }
    if (nextAudio != null &&
        !enabled.any((e) => e.id == nextAudio && e.audio)) {
      throw const SourceException('Choose an enabled audio provider.');
    }
    final raw = jsonEncode({'catalog': nextCatalog, 'audio': nextAudio});
    await _write(_choicesKey, raw);
    if (await _read(_choicesKey) != raw) {
      throw const SourceException('Could not save your provider selection.');
    }
    selected = nextCatalog;
    audioProvider = nextAudio;
    revision++;
    notifyListeners();
  }

  Future<void> install(MornyeExtension extension) async {
    if (busy != null) return;
    busy = extension.id;
    error = null;
    notifyListeners();
    Directory? temp;
    final client = http.Client();
    try {
      temp = await Directory('${root!.path}/downloads').createTemp('install-');
      final request = http.Request('GET', extension.url)
        ..followRedirects = false;
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) throw const FormatException();
      final bytes = <int>[];
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 30),
      )) {
        bytes.addAll(chunk);
        if (bytes.length > 16 * 1024 * 1024) throw const FormatException();
      }
      if (sha256.convert(bytes).toString() != extension.checksum) {
        throw const FormatException();
      }
      final file = File('${temp.path}/provider.sflx');
      await file.writeAsBytes(bytes, flush: true);
      await execute({'op': 'install', 'id': extension.id, 'path': file.path});
      await refresh();
      await choose(catalog: extension.id);
    } on Object {
      error = 'Could not install the verified provider package. Check your connection and try again.';
    } finally {
      client.close();
      if (temp != null && await temp.exists()) {
        await temp.delete(recursive: true);
      }
      busy = null;
      notifyListeners();
    }
  }

  Future<void> setEnabled(String id, bool value) async {
    await execute({'op': 'enable', 'id': id, 'enabled': value});
    await refresh();
    if (value) await choose(catalog: id);
  }

  Future<dynamic> execute(
    Map<String, dynamic> request, {
    Future<void>? abort,
  }) async {
    if (!_ready) {
      await restore();
      if (!_ready) throw SourceException(error!);
    }
    final requestId = nonce();
    var finished = false;
    _operations++;
    _pump ??= Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => unawaited(_pumpCommands()),
    );
    if (abort != null) {
      unawaited(
        abort
            .then((_) async {
              if (!finished) {
                await _native({'op': 'cancel', 'request_id': requestId});
              }
            })
            .catchError((Object _) {}),
      );
    }
    try {
      final result = await _native({...request, 'request_id': requestId});
      if (result is Map &&
          (result['success'] == false ||
              result['needs_verification'] == true)) {
        await _checkVerification(request['id'] as String?);
        if (request['id'] == 'soundcloud' &&
            result['error_code'] == 'track_unavailable') {
          throw const SourceException(
            'This SoundCloud upload does not offer a full playable stream. Try another upload.',
          );
        }
        throw const SourceException(
          'This provider could not supply the requested music. Try another source.',
        );
      }
      if (request['op'] == 'save_settings') {
        revision++;
        notifyListeners();
      }
      return result;
    } on MornyeHostException catch (failure) {
      await _checkVerification(request['id'] as String?);
      throw SourceException(
        _providerFailure(request['id'] as String?, failure.detail),
      );
    } finally {
      finished = true;
      _operations--;
      if (_operations == 0) {
        _pump?.cancel();
        _pump = null;
      }
    }
  }

  String _providerFailure(String? id, String detail) {
    final provider = id == null ? 'This provider' : name(id);
    // Classify known extension/runtime errors, but never surface the original
    // text: it can contain signed URLs, headers, session grants or response data.
    final message = detail.toLowerCase();
    if (RegExp(r'\bhttp\s+429\b').hasMatch(message) ||
        message.contains('rate limit') ||
        message.contains('too many requests')) {
      return '$provider is limiting requests. Wait a little before retrying, or choose another source.';
    }
    if (message.contains('timeout') ||
        message.contains('timed out') ||
        message.contains('deadline exceeded')) {
      return '$provider took too long to return audio. Try again or choose another source.';
    }
    if (RegExp(r'\bhttp\s+5\d\d\b').hasMatch(message)) {
      return '$provider’s audio service is temporarily unavailable. Try again later or choose another source.';
    }
    if (RegExp(r'\bhttp\s+(401|403)\b').hasMatch(message)) {
      return '$provider rejected access to this request. Try again or choose another source.';
    }
    if (RegExp(r'\bhttp\s+404\b').hasMatch(message) ||
        message.contains('track unavailable') ||
        message.contains('track not found') ||
        message.contains('not available for streaming')) {
      return '$provider could not provide this recording. Choose another source.';
    }
    return '$provider could not complete this request. Try again or choose another source.';
  }

  Future<void> _checkVerification(String? id) async {
    if (id == null) return;
    final dynamic pending;
    try {
      pending = await _native({'op': 'pending', 'id': id})
          .timeout(const Duration(seconds: 5));
    } on Object {
      // Keep the original failure actionable even if the host cannot inspect
      // its pending challenge. The next explicit attempt can check again.
      return;
    }
    if (pending != null) {
      verification.value = id;
      throw ProviderVerificationRequired(id, name: name(id));
    }
  }

  /// Share one browser across playback, imports and catalog requests. A later
  /// user action can try again after cancellation; this request retries once.
  Future<bool> requestVerification(
    String id, {
    Future<bool> Function(String)? fallback,
  }) async {
    while (true) {
      final active = _verificationRequest;
      if (active == null) break;
      if (active.id == id) return active.result;
      try {
        await active.result;
      } on Object {
        // Another provider's failure does not cancel this provider's request.
      }
    }
    final present = presentVerification ?? fallback;
    if (present == null) return false;
    late final Future<bool> result;
    result = Future<bool>.microtask(() => present(id)).whenComplete(() {
      if (identical(_verificationRequest?.result, result)) {
        _verificationRequest = null;
      }
    });
    _verificationRequest = (id: id, result: result);
    return result;
  }

  Future<T> withVerification<T>(
    Future<T> Function() action, {
    bool Function()? isCurrent,
  }) async {
    try {
      return await action();
    } on ProviderVerificationRequired catch (needed) {
      if (isCurrent?.call() == false) rethrow;
      final complete = await requestVerification(needed.providerId);
      if (!complete || isCurrent?.call() == false) {
        throw const SourceException(
          'Verification was not completed. Try again to continue.',
        );
      }
      return action();
    }
  }

  Future<bool> verify(String id) async {
    try {
      await execute({'op': 'verify', 'id': id});
    } on ProviderVerificationRequired {
      /* Open the pending challenge below. */
    }
    final pending = await _native({'op': 'pending', 'id': id});
    if (pending == null) {
      _verificationCompleted(id);
      return true;
    }
    verification.value = id;
    final challenge = SourceVerification(pending as Map);
    final String response;
    try {
      response = await _authenticate(challenge.auth, challenge.callback.scheme);
    } on PlatformException catch (error) {
      if (error.code == 'CANCELED') return false;
      throw const SourceException(
        'The verification browser could not open. Try Verify again, or paste a code from your current verification page.',
      );
    }
    await _completeVerification(id, challenge, response, manual: false);
    return true;
  }

  Future<void> pasteVerification(String id, String response) async {
    // Do not bootstrap here: it could replace the challenge the user completed.
    await restore();
    if (!_ready) throw SourceException(error!);
    final pending = await _native({'op': 'pending', 'id': id});
    if (pending == null) {
      throw const SourceException(
        'This verification attempt has expired. Close this dialog and retry the action for a fresh code.',
      );
    }
    await _completeVerification(
      id,
      SourceVerification(pending as Map),
      response,
      manual: true,
    );
  }

  Future<void> _completeVerification(
    String id,
    SourceVerification challenge,
    String response, {
    required bool manual,
  }) async {
    final grant = challenge.grant(response, manual: manual);
    try {
      await execute({
        'op': 'grant',
        'id': id,
        'state': challenge.state,
        'grant': grant,
      });
      if (await _native({'op': 'pending', 'id': id}) != null) {
        throw ProviderVerificationRequired(id);
      }
    } on SourceException {
      throw const SourceException(
        'The source could not accept this verification. Check your connection and retry the action for fresh verification.',
      );
    }
    _verificationCompleted(id);
  }

  void _verificationCompleted(String id) {
    if (verification.value == id) verification.value = null;
    issue.value = null;
    revision++;
    notifyListeners();
  }

  Future<void> _pumpCommands() async {
    if (_pumping) return;
    _pumping = true;
    try {
      final commands = await _native({'op': 'ffmpeg_poll'}) as List;
      await Future.wait(
        commands.map((dynamic command) async {
          final done = Completer<FFmpegSession>();
          Timer? cancellation;
          int? sessionId;
          try {
            final running = await FFmpegKit.executeWithArgumentsAsync(
              List<String>.from(command['arguments'] as List),
              done.complete,
            );
            sessionId = running.getSessionId();
            cancellation = Timer.periodic(const Duration(seconds: 1), (
              _,
            ) async {
              try {
                final active = await _native({
                  'op': 'ffmpeg_active',
                  'command_id': command['command_id'],
                });
                if (active != true) await FFmpegKit.cancel(sessionId);
              } on Object {
                await FFmpegKit.cancel(sessionId);
              }
            });
            final session = await done.future.timeout(
              const Duration(minutes: 5),
            );
            await _native({
              'op': 'ffmpeg_complete',
              'command_id': command['command_id'],
              'success': ReturnCode.isSuccess(await session.getReturnCode()),
              'output': await session.getOutput() ?? '',
              'error': 'Media preparation failed.',
            });
          } on Object {
            if (sessionId != null) await FFmpegKit.cancel(sessionId);
            await _native({
              'op': 'ffmpeg_complete',
              'command_id': command['command_id'],
              'success': false,
              'error': 'Media preparation failed.',
            });
          } finally {
            cancellation?.cancel();
          }
        }),
      );
    } on Object {
      /* A stopped host has no commands to deliver. */
    } finally {
      _pumping = false;
    }
  }

  @override
  void dispose() {
    _pump?.cancel();
    issue.dispose();
    verification.dispose();
    super.dispose();
  }
}
