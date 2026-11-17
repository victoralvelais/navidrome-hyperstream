import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new_audio/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;
import 'package:mornye_host/mornye_host.dart';
import 'package:path_provider/path_provider.dart';

import 'account_store.dart';
import 'music_provider.dart';
import 'remote_transfer_background.dart';

class MornyeExtension {
  MornyeExtension(Map<String, dynamic> value)
    : id = value['id'] as String,
      name = value['display_name'] as String,
      version = value['version'] as String,
      url = Uri.parse(value['download_url'] as String),
      checksum = value['sha256'] as String,
      audio = value['audio'] == true,
      installed = value['installed'] == true,
      enabled = value['installed'] == true && value['enabled'] == true;
  final String id, name, version, checksum;
  final Uri url;
  final bool audio, installed, enabled;
}

class ProviderVerificationRequired extends SourceException {
  ProviderVerificationRequired(this.providerId)
    : super(
        'This source needs verification. Open Music sources and choose Verify.',
      );
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
  }) : _native = native ?? callMornye,
       _directory = directory ?? getApplicationSupportDirectory,
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
  static const _masterKey = 'hyperstream.mornye.master.v1';
  static const _choicesKey = 'hyperstream.mornye.choices.v1';
  List<MornyeExtension> extensions = [];
  String? selected;
  String? audioProvider;
  String? error;
  String? busy;
  final issue = ValueNotifier<String?>(null);
  final verification = ValueNotifier<String?>(null);
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
      extensions.where((e) => e.id == id).firstOrNull?.name ?? id;
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
        throw const SourceException(
          'This provider could not supply the requested music. Try another source.',
        );
      }
      if (request['op'] == 'save_settings') {
        revision++;
        notifyListeners();
      }
      return result;
    } on MornyeHostException {
      await _checkVerification(request['id'] as String?);
      throw const SourceException(
        'The provider could not complete this request. Try again or choose another source.',
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

  Future<void> _checkVerification(String? id) async {
    if (id == null) return;
    final pending = await _native({'op': 'pending', 'id': id});
    if (pending != null) {
      verification.value = id;
      throw ProviderVerificationRequired(id);
    }
  }

  Future<void> verify(String id) async {
    try {
      await execute({'op': 'verify', 'id': id});
    } on ProviderVerificationRequired {
      /* Open the pending challenge below. */
    }
    final pending = await _native({'op': 'pending', 'id': id});
    if (pending == null) {
      verification.value = null;
      return;
    }
    final auth = Uri.parse(pending['auth_url'] as String);
    if (auth.scheme != 'https' || auth.userInfo.isNotEmpty) {
      throw const SourceException(
        'This provider returned an invalid verification page.',
      );
    }
    final callback = Uri.parse(
      await FlutterWebAuth2.authenticate(
        url: auth.toString(),
        callbackUrlScheme: 'hyperstream',
        options: const FlutterWebAuth2Options(httpsHost: 'session-grant'),
      ),
    );
    final grant =
        callback.queryParameters['grant'] ?? callback.queryParameters['code'];
    if (callback.scheme != 'hyperstream' ||
        callback.host != 'session-grant' ||
        callback.queryParameters['state']?.isNotEmpty != true ||
        grant?.isNotEmpty != true) {
      throw const SourceException(
        'Verification did not return a valid session. Please try again.',
      );
    }
    await execute({
      'op': 'grant',
      'id': id,
      'state': callback.queryParameters['state'],
      'grant': grant,
    });
    verification.value = null;
    issue.value = null;
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
