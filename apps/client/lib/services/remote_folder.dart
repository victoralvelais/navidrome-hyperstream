import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dart_smb2/dart_smb2.dart';
import 'package:flutter/foundation.dart';

import 'account_store.dart';

/// The server login can be verified and saved before choosing a share.
class RemoteConnection {
  RemoteConnection({
    required String address,
    required String username,
    required this.password,
    String name = '',
  }) : username = username.trim().replaceAll('/', r'\'),
       name = name.trim() {
    final uri = _smbAddress(address);
    if (uri.pathSegments.any((part) => part.isNotEmpty)) {
      throw const FormatException(
        'Enter only the server name or IP here. Choose the share below after connecting.',
      );
    }
    if (this.username.isEmpty ||
        password.isEmpty ||
        this.username.contains(RegExp(r'[\x00-\x1f\x7f]')) ||
        this.username.split(r'\').any((part) => part.isEmpty) ||
        this.username.split(r'\').length > 2) {
      throw const FormatException(
        'Enter the username and password that work for file sharing.',
      );
    }
    host = uri.host;
    this.address = Uri(scheme: 'smb', host: host).toString();
  }

  late final String host;
  late final String address;
  final String username;
  final String password;
  final String name;
  String get displayName => name.isEmpty ? host : name;
  String get domain =>
      username.contains(r'\') ? username.split(r'\').first : '';
  String get user => username.split(r'\').last;

  RemoteDestination destination({required String share, String folder = ''}) {
    final parts = folder
        .trim()
        .replaceAll(r'\', '/')
        .split('/')
        .where((part) => part.isNotEmpty)
        .toList();
    if (share.trim().isEmpty ||
        !_validComponent(share.trim()) ||
        parts.any((part) => !_validComponent(part))) {
      throw const FormatException(
        'Enter the shared folder name and a valid path inside it.',
      );
    }
    return RemoteDestination(
      address: Uri(
        scheme: 'smb',
        host: host,
        pathSegments: [share.trim(), ...parts],
      ).toString(),
      username: username,
      password: password,
      name: name,
    );
  }

  bool sameAccount(RemoteConnection other) =>
      host == other.host && username == other.username;

  @override
  String toString() => 'RemoteConnection(redacted)';
}

Uri _smbAddress(String address) {
  var input = address.trim().replaceAll(r'\', '/');
  if (input.startsWith('//')) input = 'smb:$input';
  if (!input.contains('://')) input = 'smb://$input';
  // Reject dot segments before Uri normalizes them away.
  final pathStart = input.indexOf('/', input.indexOf('://') + 3);
  try {
    if (pathStart >= 0 &&
        input.substring(pathStart).split('/').any((part) {
          final decoded = Uri.decodeComponent(part);
          return decoded == '.' || decoded == '..';
        })) {
      throw const FormatException();
    }
    final uri = Uri.parse(input);
    if (uri.scheme == 'smb' &&
        uri.host.isNotEmpty &&
        !Uri.decodeComponent(uri.host).contains(RegExp(r'[\s\x00-\x1f\x7f]')) &&
        uri.userInfo.isEmpty &&
        !uri.hasQuery &&
        !uri.hasFragment &&
        (!uri.hasPort || uri.port == 445)) {
      return uri;
    }
  } on FormatException {
    // Keep user input and credentials out of parser errors.
  } on ArgumentError {
    // Malformed percent escapes can also throw ArgumentError.
  }
  throw const FormatException('Enter a valid SMB server name or IP address.');
}

/// A device-level destination, independent of the active Navidrome account.
/// Credentials and address are saved together in protected storage only.
class RemoteDestination {
  RemoteDestination({
    required String address,
    required String username,
    required this.password,
    String name = '',
  }) : username = username.trim().replaceAll('/', r'\'),
       name = name.trim() {
    final uri = _smbAddress(address);
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
  RemoteConnection get connection => RemoteConnection(
    address: Uri(scheme: 'smb', host: host).toString(),
    username: username,
    password: password,
    name: name,
  );
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

/// One atomic secure-storage record for the login and optional destination.
class RemoteFolderConfig {
  const RemoteFolderConfig(this.connection, {this.share, this.folder = ''});
  factory RemoteFolderConfig.forDestination(RemoteDestination destination) =>
      RemoteFolderConfig(
        destination.connection,
        share: destination.share,
        folder: destination.folder,
      );

  final RemoteConnection connection;
  final String? share;
  final String folder;
  RemoteDestination? get destination => share == null
      ? null
      : connection.destination(share: share!, folder: folder);

  String encode() => jsonEncode({
    'schema': 2,
    'server': connection.address,
    'username': connection.username,
    'password': connection.password,
    'name': connection.name,
    'share': share,
    'folder': folder,
  });

  factory RemoteFolderConfig.decode(String value) {
    final record = jsonDecode(value) as Map<String, dynamic>;
    if (record['schema'] == 1) {
      return RemoteFolderConfig.forDestination(RemoteDestination.decode(value));
    }
    if (record['schema'] != 2) {
      throw const FormatException('Unknown remote connection.');
    }
    final config = RemoteFolderConfig(
      RemoteConnection(
        address: record['server'] as String,
        username: record['username'] as String,
        password: record['password'] as String,
        name: record['name'] as String? ?? '',
      ),
      share: record['share'] as String?,
      folder: record['folder'] as String? ?? '',
    );
    // Validate a saved destination before exposing it to transfer callers.
    config.destination;
    return config;
  }

  @override
  String toString() => 'RemoteFolderConfig(redacted)';
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

abstract interface class RemoteFolderStore {
  Future<RemoteFolderConfig?> read();
  Future<void> write(RemoteFolderConfig? config);
}

class SecureRemoteFolderStore implements RemoteFolderStore {
  const SecureRemoteFolderStore();
  static const _key = 'hyperstream.remote-folder.v1';
  @override
  Future<RemoteFolderConfig?> read() async {
    try {
      final value = await SecureAccountStore.defaultStorage
          .read(key: _key)
          .timeout(const Duration(seconds: 10));
      return value == null ? null : RemoteFolderConfig.decode(value);
    } on Object {
      throw const RemoteFolderException(
        'Could not read your saved remote folder. Unlock your device and try again.',
      );
    }
  }

  @override
  Future<void> write(RemoteFolderConfig? config) async {
    try {
      final value = config?.encode();
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
        'Could not securely save the remote connection. Unlock your device and try again.',
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

class RemotePublicationUncertain extends RemoteFolderException {
  const RemotePublicationUncertain()
    : super(
        'Could not confirm the final file. Check the destination before sending again; it may already have arrived.',
      );
}

/// Narrow filesystem boundary: no recursive deletion or replacement operations.
abstract interface class RemoteFileSystem {
  Future<({bool directory, int size})> stat(String path);
  Future<List<String>> listFolders(String path);
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
typedef RemoteLoginCheck = Future<void> Function(RemoteConnection);
typedef RemoteShareListing = Future<List<Smb2ShareInfo>> Function(
  RemoteConnection,
);

Future<List<Smb2ShareInfo>> listRemoteShares(RemoteConnection connection) =>
    Smb2Pool.listSharesOn(
      host: connection.host,
      user: connection.user,
      domain: connection.domain,
      password: connection.password,
      timeout: const Duration(seconds: 15),
      version: Smb2Version.any3,
      seal: true,
      signing: true,
    );

List<String> _folderNames(Iterable<String> names) =>
    names
        .where((name) => name.isNotEmpty && _validComponent(name))
        .toSet()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

/// IPC$ authenticates a server session independently of a disk share or folder.
Future<void> checkRemoteLogin(RemoteConnection connection) async {
  final fs = await connectRemoteFolder(connection.destination(share: r'IPC$'));
  try {
    await fs.close();
  } on Object {
    // Authentication already succeeded. A disconnect failure does not undo it.
  }
}

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
  Future<List<String>> listFolders(String path) async =>
      (await pool.listDirectory(path))
          .where((entry) => entry.isDirectory)
          .map((entry) => entry.name)
          .toList();
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

enum RemoteCheckStage { login, shares, share, folder, write, save }

class RemoteCheckException extends RemoteFolderException {
  const RemoteCheckException(this.stage, super.message);
  final RemoteCheckStage stage;
}

String _checkError(Object error, RemoteCheckStage stage) {
  if (error is RemoteFolderException || error is FormatException) {
    return remoteFolderError(error);
  }
  if (stage == RemoteCheckStage.save) {
    return 'Could not securely save these settings. Unlock your device and try again.';
  }
  if (error is Smb2Exception) {
    switch (error.type) {
      case Smb2ErrorType.auth:
        return 'The server rejected this login. Use your file-sharing account password. A Windows PIN cannot sign in to a share.';
      case Smb2ErrorType.accessDenied:
        return switch (stage) {
          RemoteCheckStage.login => 'The server denied the login check. Check the account’s network access and access to the server’s IPC\$ service.',
          RemoteCheckStage.shares => 'This server does not allow listing its shares with this account. You can enter a share name manually.',
          RemoteCheckStage.share => 'Login was verified, but this account cannot open that share. Check its sharing permissions.',
          RemoteCheckStage.folder => 'The share opened, but this account cannot read that folder. Check its folder permissions.',
          _ => 'The folder opened, but creating, renaming, or removing the test file was denied. Check its write permissions.',
        };
      case Smb2ErrorType.notFound:
      case Smb2ErrorType.notADirectory:
        return switch (stage) {
          RemoteCheckStage.login => 'The server’s login-check service (IPC\$) is unavailable. Check that SMB file sharing is enabled.',
          RemoteCheckStage.shares => 'The server’s share list is unavailable. You can enter a share name manually.',
          RemoteCheckStage.share => 'That share name was not found on the server. Use the name shown in the folder’s Windows Sharing properties.',
          _ => 'The share opened, but that folder was not found. Enter an existing path inside the share or leave it empty for the share root.',
        };
      case Smb2ErrorType.connection:
      case Smb2ErrorType.timeout:
        return 'Could not reach the SMB server. Check the address, Wi-Fi or Tailscale, file sharing, and Hyperstream’s local-network permission.';
      default:
        return remoteFolderError(error);
    }
  }
  return 'This check could not finish. Try again and check the server connection.';
}

class RemoteFolders extends ChangeNotifier {
  RemoteFolders({
    this.store = const SecureRemoteFolderStore(),
    this.connect = connectRemoteFolder,
    this.checkLogin = checkRemoteLogin,
    this.listShares = listRemoteShares,
  });
  static final instance = RemoteFolders();
  final RemoteFolderStore store;
  final RemoteConnector connect;
  final RemoteLoginCheck checkLogin;
  final RemoteShareListing listShares;
  RemoteFolderConfig? _config;
  RemoteConnection? get connection => _config?.connection;
  RemoteDestination? get destination => _config?.destination;
  RemoteCheckStage? checking;
  String? error;
  bool loaded = false;
  bool busy = false;
  Future<void>? _restoring;

  Future<void> restore() => _restoring ??= _restore();
  Future<void> _restore() async {
    try {
      _config = await store.read();
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
    checking = null;
    notifyListeners();
  }

  void _checking(RemoteCheckStage stage) {
    checking = stage;
    notifyListeners();
  }

  Future<List<String>> browseShares(RemoteConnection connection) async {
    if (!begin()) {
      throw const RemoteFolderException(
        'Wait for the current transfer or check to finish.',
      );
    }
    try {
      _checking(RemoteCheckStage.shares);
      final shares = await listShares(connection);
      final candidates = _folderNames(
        shares
            .where((share) => share.isDisk && !share.isHidden)
            .map((share) => share.name),
      );
      final accessible = <String>[];
      // Bound native sessions while checking each share's directory permissions.
      for (var offset = 0; offset < candidates.length; offset += 3) {
        final checked = await Future.wait(
          candidates
              .skip(offset)
              .take(3)
              .map(
                (name) => _accessibleShare(connection.destination(share: name)),
              ),
        );
        accessible.addAll(checked.whereType<String>());
      }
      return accessible;
    } on Object catch (e) {
      throw RemoteCheckException(
        RemoteCheckStage.shares,
        _checkError(e, RemoteCheckStage.shares),
      );
    } finally {
      end();
    }
  }

  Future<String?> _accessibleShare(RemoteDestination location) async {
    RemoteFileSystem? fs;
    try {
      fs = await connect(location);
      await fs.listFolders('');
      return location.share;
    } on Smb2Exception catch (e) {
      switch (e.type) {
        case Smb2ErrorType.accessDenied:
        case Smb2ErrorType.notFound:
        case Smb2ErrorType.notADirectory:
          return null;
        default:
          // Connection and login failures need a visible error and retry.
          rethrow;
      }
    } finally {
      try {
        await fs?.close();
      } on Object {
        // Preserve the access-check result.
      }
    }
  }

  Future<List<String>> browseFolders(RemoteDestination location) async {
    if (!begin()) {
      throw const RemoteFolderException(
        'Wait for the current transfer or check to finish.',
      );
    }
    RemoteFileSystem? fs;
    var stage = RemoteCheckStage.share;
    try {
      _checking(stage);
      fs = await connect(location);
      stage = RemoteCheckStage.folder;
      _checking(stage);
      return _folderNames(await fs.listFolders(location.folder));
    } on Object catch (e) {
      throw RemoteCheckException(stage, _checkError(e, stage));
    } finally {
      try {
        await fs?.close();
      } on Object {
        // Preserve the listing result.
      }
      end();
    }
  }

  Future<void> checkAndSaveConnection(RemoteConnection next) async {
    if (!begin()) {
      throw const RemoteFolderException(
        'Wait for the current transfer or check to finish.',
      );
    }
    var stage = RemoteCheckStage.login;
    try {
      _checking(stage);
      await checkLogin(next);
      // Keep the selected folder when reconnecting to the same account.
      final previous = _config;
      final keepFolder = previous?.connection.sameAccount(next) ?? false;
      final config = RemoteFolderConfig(
        next,
        share: keepFolder ? previous?.share : null,
        folder: keepFolder ? previous!.folder : '',
      );
      stage = RemoteCheckStage.save;
      _checking(stage);
      await store.write(config);
      _config = config;
      error = null;
    } on Object catch (e) {
      throw RemoteCheckException(stage, _checkError(e, stage));
    } finally {
      end();
    }
  }

  /// Test the actual write/rename/delete permissions with tiny unique files.
  /// Never reads or modifies existing files in the destination.
  Future<void> testAndSave(RemoteDestination next) async {
    if (!begin()) {
      throw const RemoteFolderException(
        'Wait for the current transfer or check to finish.',
      );
    }
    RemoteFileSystem? fs;
    var stage = RemoteCheckStage.share;
    final probe = next.path('.hyperstream-test-${_token()}.part');
    final renamed = '$probe.checked';
    String? cleanup;
    try {
      _checking(stage);
      fs = await connect(next);
      stage = RemoteCheckStage.folder;
      _checking(stage);
      if (!(await fs.stat(next.folder)).directory) {
        throw const RemoteFolderException('Choose an existing folder.');
      }
      stage = RemoteCheckStage.write;
      _checking(stage);
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
      stage = RemoteCheckStage.save;
      _checking(stage);
      final config = RemoteFolderConfig.forDestination(next);
      await store.write(config);
      _config = config;
      error = null;
    } on Object catch (e) {
      throw RemoteCheckException(stage, _checkError(e, stage));
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
      _config = null;
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
      throw const RemotePublicationUncertain();
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
