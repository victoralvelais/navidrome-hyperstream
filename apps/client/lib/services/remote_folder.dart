import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dart_smb2/dart_smb2.dart';
import 'package:flutter/foundation.dart';

import 'account_store.dart';

/// A device-level destination, independent of the active Navidrome account.
/// Credentials and address are saved together in protected storage only.
class RemoteDestination {
  RemoteDestination({
    required String address,
    required String username,
    required this.password,
    String name = '',
  }) : username = username.trim(),
       name = name.trim() {
    var input = address.trim().replaceAll('\\', '/');
    if (input.startsWith('//')) input = 'smb:$input';
    if (!input.contains('://')) input = 'smb://$input';
    // Uri normalizes encoded dot segments during parsing. Reject them before
    // normalization can silently select a different share or parent directory.
    final pathStart = input.indexOf('/', input.indexOf('://') + 3);
    if (pathStart >= 0 &&
        input.substring(pathStart).split('/').any((part) {
          final decoded = Uri.decodeComponent(part);
          return decoded == '.' || decoded == '..';
        })) {
      throw const FormatException(
        'Use the complete folder path without dot segments.',
      );
    }
    final uri = Uri.tryParse(input);
    if (uri == null ||
        uri.scheme != 'smb' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.hasPort && uri.port != 445)) {
      throw const FormatException(
        'Enter an SMB address such as smb://server/share/Test.',
      );
    }
    final parts = uri.pathSegments.where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty || parts.any((p) => !_validComponent(p))) {
      throw const FormatException(
        'Include a share name and a valid folder path.',
      );
    }
    if (this.username.isEmpty ||
        password.isEmpty ||
        this.username.contains(RegExp(r'[\x00-\x1f]'))) {
      throw const FormatException(
        'Enter the username and password for this share.',
      );
    }
    host = uri.host;
    share = parts.first;
    folder = parts.skip(1).join('/');
    this.address = Uri(
      scheme: 'smb',
      host: host,
      pathSegments: parts,
    ).toString();
  }

  late final String address;
  late final String host;
  late final String share;
  late final String folder;
  final String username;
  final String password;
  final String name;
  String get displayName => name.isEmpty ? host : name;
  String get domain =>
      username.contains('\\') ? username.split('\\').first : '';
  String get user => username.contains('\\')
      ? username.split('\\').skip(1).join('\\')
      : username;
  String path(String filename) =>
      folder.isEmpty ? filename : '$folder/$filename';

  String encode() => jsonEncode({
    'schema': 1,
    'address': address,
    'username': username,
    'password': password,
    'name': name,
  });
  factory RemoteDestination.decode(String value) {
    final record = jsonDecode(value) as Map<String, dynamic>;
    if (record['schema'] != 1) {
      throw const FormatException('Unknown remote folder.');
    }
    return RemoteDestination(
      address: record['address'] as String,
      username: record['username'] as String,
      password: record['password'] as String,
      name: record['name'] as String? ?? '',
    );
  }
  @override
  String toString() => 'RemoteDestination(redacted)';
}

bool _validComponent(String value) =>
    value != '.' &&
    value != '..' &&
    !RegExp(r'[\x00-\x1f\x7f/\\:*?"<>|]').hasMatch(value) &&
    !value.endsWith('.') &&
    !value.endsWith(' ') &&
    !RegExp(
      r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)',
      caseSensitive: false,
    ).hasMatch(value);

abstract interface class RemoteDestinationStore {
  Future<RemoteDestination?> read();
  Future<void> write(RemoteDestination? destination);
}

class SecureRemoteDestinationStore implements RemoteDestinationStore {
  const SecureRemoteDestinationStore();
  static const _key = 'hyperstream.remote-folder.v1';
  @override
  Future<RemoteDestination?> read() async {
    try {
      final value = await SecureAccountStore.defaultStorage
          .read(key: _key)
          .timeout(const Duration(seconds: 10));
      return value == null ? null : RemoteDestination.decode(value);
    } on Object {
      throw const RemoteFolderException(
        'Could not read your saved remote folder. Unlock your device and try again.',
      );
    }
  }

  @override
  Future<void> write(RemoteDestination? destination) async {
    try {
      final value = destination?.encode();
      if (value == null) {
        await SecureAccountStore.defaultStorage.delete(key: _key);
      } else {
        await SecureAccountStore.defaultStorage.write(key: _key, value: value);
      }
      if (await SecureAccountStore.defaultStorage.read(key: _key) != value) {
        throw StateError('Protected storage verification failed.');
      }
    } on Object {
      throw const RemoteFolderException(
        'Could not securely save the remote folder. Try again.',
      );
    }
  }
}

class RemoteFolderException implements Exception {
  const RemoteFolderException(this.message);
  final String message;
  @override
  String toString() => message;
}

class RemoteSendCancelled implements Exception {
  const RemoteSendCancelled();
}

/// Narrow filesystem boundary: no recursive deletion or replacement operations.
abstract interface class RemoteFileSystem {
  Future<({bool directory, int size})> stat(String path);
  Future<void> write(
    String path,
    Stream<List<int>> chunks,
    int length,
    void Function(int) onProgress,
    bool Function() cancelled,
  );
  Future<void> rename(String from, String to);
  Future<void> delete(String path);
  Future<void> close();
}

typedef RemoteConnector = Future<RemoteFileSystem> Function(RemoteDestination);

Future<RemoteFileSystem> connectRemoteFolder(
  RemoteDestination destination,
) async => _SmbFileSystem(
  await Smb2Pool.connect(
    host: destination.host,
    share: destination.share,
    user: destination.user,
    domain: destination.domain,
    password: destination.password,
    workers: 1,
    timeout: const Duration(seconds: 15),
    // Windows 10 supports SMB3. No silent downgrade to an unencrypted session.
    version: Smb2Version.any3,
    seal: true,
    signing: true,
  ),
);

class _SmbFileSystem implements RemoteFileSystem {
  _SmbFileSystem(this.pool);
  final Smb2Pool pool;
  @override
  Future<({bool directory, int size})> stat(String path) async {
    final entry = await pool.stat(path);
    return (directory: entry.isDirectory, size: entry.size);
  }

  @override
  Future<void> write(
    String path,
    Stream<List<int>> chunks,
    int length,
    void Function(int) onProgress,
    bool Function() cancelled,
  ) async {
    final handle = await pool.openFileWrite(path, truncate: true);
    var offset = 0;
    try {
      await for (final chunk in chunks) {
        if (cancelled()) throw const RemoteSendCancelled();
        await pool.writeToHandle(
          handle,
          Uint8List.fromList(chunk),
          offset: offset,
        );
        offset += chunk.length;
        onProgress(offset);
      }
      if (cancelled()) throw const RemoteSendCancelled();
      if (offset != length) {
        throw const RemoteFolderException(
          'The local file changed during transfer. Try again.',
        );
      }
      await pool.fsyncHandle(handle);
    } finally {
      // Join writes before closing or cleaning up; cancellation must not race
      // a request still creating/writing the partial file on the server.
      await pool.closeHandle(handle);
    }
  }

  @override
  Future<void> rename(String from, String to) =>
      pool.rename(from, to, overwrite: false);
  @override
  Future<void> delete(String path) => pool.deleteFile(path);
  @override
  Future<void> close() => pool.disconnect();
}

String _token() => List.generate(
  16,
  (_) => Random.secure().nextInt(256),
).map((n) => n.toRadixString(16).padLeft(2, '0')).join();

String remoteFolderError(Object error) {
  if (error is RemoteFolderException) return error.message;
  if (error is FormatException) return error.message;
  if (error is Smb2Exception) {
    return switch (error.type) {
      Smb2ErrorType.auth => 'The server rejected this login. Check the Windows username and password, not your Navidrome login.',
      Smb2ErrorType.accessDenied => 'This account cannot write to that folder. Check the share and folder permissions.',
      Smb2ErrorType.notFound || Smb2ErrorType.notADirectory => 'The share or folder was not found. Check the address and create the test folder first.',
      Smb2ErrorType.connection || Smb2ErrorType.timeout => 'Could not reach the remote folder. Check Wi-Fi or Tailscale, the server address, and local-network permission.',
      Smb2ErrorType.diskFull =>
        'The remote folder is out of space or over its storage limit.',
      Smb2ErrorType.notSupported => 'This connection requires SMB3 encryption. Check that the server supports it.',
      _ => 'The remote file operation failed. Check the connection and folder permissions, then try again.',
    };
  }
  return 'Could not complete the remote transfer. Check the connection and try again.';
}

class RemoteFolders extends ChangeNotifier {
  RemoteFolders({
    this.store = const SecureRemoteDestinationStore(),
    this.connect = connectRemoteFolder,
  });
  static final instance = RemoteFolders();
  final RemoteDestinationStore store;
  final RemoteConnector connect;
  RemoteDestination? destination;
  String? error;
  bool loaded = false;
  bool busy = false;
  Future<void>? _restoring;

  Future<void> restore() => _restoring ??= _restore();
  Future<void> _restore() async {
    try {
      destination = await store.read();
      error = null;
    } on Object catch (e) {
      error = remoteFolderError(e);
    }
    loaded = true;
    notifyListeners();
  }

  Future<void> retryRestore() async {
    if (busy) return;
    _restoring = null;
    loaded = false;
    await restore();
  }

  bool begin() {
    if (busy) return false;
    busy = true;
    notifyListeners();
    return true;
  }

  void end() {
    busy = false;
    notifyListeners();
  }

  /// Test the actual write/rename/delete permissions with tiny unique files.
  /// Never reads or modifies existing files in the destination.
  Future<void> testAndSave(RemoteDestination next) async {
    if (!begin()) return;
    RemoteFileSystem? fs;
    final probe = next.path('.hyperstream-test-${_token()}.part');
    final renamed = '$probe.checked';
    String? cleanup;
    try {
      fs = await connect(next);
      if (!(await fs.stat(next.folder)).directory) {
        throw const RemoteFolderException('Choose a folder, not a file.');
      }
      final data = utf8.encode('Hyperstream connection test\n');
      cleanup = probe;
      await fs.write(
        probe,
        Stream.value(data),
        data.length,
        (_) {},
        () => false,
      );
      if ((await fs.stat(probe)).size != data.length) {
        throw const RemoteFolderException(
          'The server did not confirm the complete test file.',
        );
      }
      await fs.rename(probe, renamed);
      cleanup = renamed;
      await fs.delete(renamed);
      cleanup = null;
      await store.write(next);
      destination = next;
      error = null;
    } on Object catch (e) {
      throw RemoteFolderException(remoteFolderError(e));
    } finally {
      if (cleanup != null && fs != null) {
        try {
          await fs.delete(cleanup);
        } on Object {
          /* Only our unique probe. */
        }
      }
      try {
        await fs?.close();
      } on Object {
        /* Preserve the operation's result. */
      }
      end();
    }
  }

  Future<void> forget() async {
    if (!begin()) return;
    try {
      await store.write(null);
      destination = null;
      error = null;
    } finally {
      end();
    }
  }
}

/// Uploads a completed local export to a unique .part file, then publishes it
/// with a server-side rename that MUST fail if the final name already exists.
/// A lost rename acknowledgement is reported as uncertain, never retried.
Future<String> sendRemoteFile({
  required RemoteFileSystem fs,
  required RemoteDestination destination,
  required File file,
  required bool Function() cancelled,
  required void Function(int sent, int total) onProgress,
  required VoidCallback onFinishing,
}) async {
  final baseName = file.uri.pathSegments.last;
  if (!_validComponent(baseName)) {
    throw const RemoteFolderException(
      'The song filename is not supported by this folder.',
    );
  }
  final length = await file.length();
  final part = destination.path('.hyperstream-${_token()}.part');
  var published = false;
  var renameStarted = false;
  try {
    if (cancelled()) throw const RemoteSendCancelled();
    await fs.write(
      part,
      file.openRead(),
      length,
      (n) => onProgress(n, length),
      cancelled,
    );
    if ((await fs.stat(part)).size != length) {
      throw const RemoteFolderException(
        'The remote file is incomplete. It was not published.',
      );
    }
    if (cancelled()) throw const RemoteSendCancelled();
    onFinishing();
    final dot = baseName.lastIndexOf('.');
    final stem = dot > 0 ? baseName.substring(0, dot) : baseName;
    final suffix = dot > 0 ? baseName.substring(dot) : '';
    for (var attempt = 0; attempt < 100; attempt++) {
      final name = attempt == 0 ? baseName : '$stem ($attempt)$suffix';
      final target = destination.path(name);
      try {
        renameStarted = true;
        await fs.rename(part, target);
        published = true;
        return name;
      } on Smb2Exception catch (e) {
        if (e.type != Smb2ErrorType.alreadyExists) rethrow;
        renameStarted = false;
      }
    }
    throw const RemoteFolderException(
      'Too many copies of this filename already exist. Choose another folder.',
    );
  } on Object {
    if (renameStarted) {
      throw const RemoteFolderException(
        'Could not confirm the final file. Check the destination before sending again; it may already have arrived.',
      );
    }
    rethrow;
  } finally {
    if (!published) {
      try {
        await fs.delete(part);
      } on Object {
        /* A network outage may leave this .part file. */
      }
    }
  }
}
