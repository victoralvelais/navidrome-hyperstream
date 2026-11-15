import 'dart:async';
import 'dart:io';

import 'package:dart_smb2/dart_smb2.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperstream_client/app_theme.dart';
import 'package:hyperstream_client/features/settings/remote_folder_settings.dart';
import 'package:hyperstream_client/services/remote_folder.dart';

import 'remote_folder_test.dart'
    show MemoryRemoteStore, MemoryRemoteFs, destination;

Finder field(String label) => find.widgetWithText(TextFormField, label);

Future<List<Smb2ShareInfo>> fakeShares(RemoteConnection connection) async =>
    const [
      Smb2ShareInfo(name: 'Music', type: 0),
      Smb2ShareInfo(name: 'Restricted', type: 0),
      Smb2ShareInfo(name: r'ADMIN$', type: Smb2ShareType.hidden),
      Smb2ShareInfo(name: r'C$', type: 0),
      Smb2ShareInfo(name: r'D$', type: Smb2ShareType.hidden),
      Smb2ShareInfo(name: r'E$', type: Smb2ShareType.hidden),
    ];

Future<void> mount(WidgetTester tester, RemoteFolders remote) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: hyperstreamTheme(Brightness.dark),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: RemoteFolderSettings(remote: remote),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

Future<void> enterLogin(WidgetTester tester) async {
  await tester.enterText(field('Name (optional)'), 'Test server');
  await tester.enterText(field('Server address'), 'smb://server/');
  await tester.enterText(field('Username'), 'Listener');
  await tester.enterText(field('Password'), 'synthetic-password');
}

Future<void> capture(WidgetTester tester, String name) async {
  if (const bool.fromEnvironment('CAPTURE_PREVIEWS')) {
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../build/previews/$name.png'),
    );
  }
}

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  const fontPath = String.fromEnvironment('PREVIEW_FONT');
  if (fontPath.isNotEmpty) {
    await (FontLoader(
      'Roboto',
    )..addFont(File(fontPath).readAsBytes().then(ByteData.sublistView))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  }

  testWidgets(
    'save plain login, browse shares and nested folders, select on a small phone',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = MemoryRemoteStore();
      final fs = MemoryRemoteFs();
      var loginChecks = 0;
      final remote = RemoteFolders(
        store: store,
        connect: (_) async => fs,
        listShares: fakeShares,
        checkLogin: (connection) async {
          loginChecks++;
          expect(connection.domain, isEmpty);
          expect(connection.user, 'Listener');
        },
      );
      await mount(tester, remote);
      expect(field('Share name'), findsNothing);
      await enterLogin(tester);
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: field('Password'),
                matching: find.byType(TextField),
              ),
            )
            .obscureText,
        isTrue,
      );
      await tap(tester, 'Check connection');
      expect(loginChecks, 1);
      expect(store.value?.connection.username, 'Listener');
      expect(store.value?.connection.password, 'synthetic-password');
      expect(store.value?.destination, isNull);
      expect(fs.files, isEmpty);
      expect(find.text('Login verified'), findsOneWidget);
      expect(find.text('Music'), findsOneWidget);
      await capture(tester, 'remote-shares');
      await tap(tester, 'Music');
      await tap(tester, 'Test');
      await tap(tester, 'Deep');
      expect(find.text('This folder has no subfolders.'), findsOneWidget);
      await tap(tester, 'Up one folder');
      expect(find.text('Music / Test'), findsOneWidget);
      expect(fs.renames, isEmpty);
      await capture(tester, 'remote-browse');
      await tap(tester, 'Use this folder');
      expect(remote.destination?.address, 'smb://server/Music/Test');
      expect(fs.files, isEmpty);
      expect(find.textContaining('Folder verified and saved'), findsOneWidget);
      await capture(tester, 'remote-folder-selected');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      remote.dispose();
    },
  );

  testWidgets(
    'hidden and denied shares are omitted while an accessible share remains usable',
    (tester) async {
      final fs = MemoryRemoteFs();
      final remote = RemoteFolders(
        store: MemoryRemoteStore(),
        checkLogin: (_) async {},
        listShares: fakeShares,
        connect: (location) async {
          if (location.share == 'Restricted') {
            throw const Smb2Exception(
              'private response',
              type: Smb2ErrorType.accessDenied,
            );
          }
          return fs;
        },
      );
      await mount(tester, remote);
      await enterLogin(tester);
      await tap(tester, 'Check connection');
      for (final name in ['Restricted', r'ADMIN$', r'C$', r'D$', r'E$']) {
        expect(find.text(name), findsNothing);
      }
      expect(remote.connection, isNotNull);
      await tap(tester, 'Music');
      await tap(tester, 'Use this folder');
      expect(remote.destination?.folder, isEmpty);
      await tap(tester, 'Edit or recheck connection');
      expect(find.text('Shared folders'), findsNothing);
      await tester.enterText(field('Server address'), 'another-server');
      await tap(tester, 'Check connection');
      expect(remote.destination, isNull);
      expect(find.text('Music'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      remote.dispose();
    },
  );

  testWidgets(
    'saved login opens browser on relaunch without re-entering credentials',
    (tester) async {
      final store = MemoryRemoteStore()
        ..value = RemoteFolderConfig.forDestination(destination());
      var loginChecks = 0;
      var shareLists = 0;
      final remote = RemoteFolders(
        store: store,
        connect: (_) async => MemoryRemoteFs(),
        checkLogin: (_) async {
          loginChecks++;
        },
        listShares: (connection) async {
          shareLists++;
          expect(connection.password, 'secret');
          return fakeShares(connection);
        },
      );
      await mount(tester, remote);
      expect(field('Username'), findsNothing);
      expect(find.text('Music'), findsOneWidget);
      expect(shareLists, 1);
      expect(loginChecks, 0);
      await tap(tester, 'Open saved folder');
      expect(find.text('share / Test'), findsOneWidget);
      await tap(tester, 'Forget remote connection');
      await tap(tester, 'Forget');
      expect(store.value, isNull);
      expect(
        tester.widget<TextFormField>(field('Password')).controller!.text,
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox());
      remote.dispose();
    },
  );

  testWidgets(
    'share-list permission failure keeps saved login and manual fallback',
    (tester) async {
      final store = MemoryRemoteStore()
        ..value = RemoteFolderConfig(destination().connection);
      final remote = RemoteFolders(
        store: store,
        connect: (_) async => MemoryRemoteFs(),
        listShares: (_) async => throw const Smb2Exception(
          'private response',
          type: Smb2ErrorType.accessDenied,
        ),
      );
      await mount(tester, remote);
      expect(find.text('Saved connection'), findsOneWidget);
      expect(find.textContaining('does not allow listing'), findsOneWidget);
      expect(remote.connection, isNotNull);
      await tap(tester, 'Enter path manually');
      await tester.enterText(field('Share name'), r'Music$');
      await tester.enterText(field('Subfolder (optional)'), 'Test');
      await tap(tester, 'Use this folder');
      expect(remote.destination?.share, r'Music$');
      expect(remote.destination?.folder, 'Test');
      expect(find.text('Login verified'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      remote.dispose();
    },
  );

  testWidgets(
    'empty share list can retry and write failure does not save a destination',
    (tester) async {
      var empty = true;
      final fs = MemoryRemoteFs()
        ..writeError = const Smb2Exception(
          'private response',
          type: Smb2ErrorType.accessDenied,
        );
      final store = MemoryRemoteStore()
        ..value = RemoteFolderConfig(destination().connection);
      final remote = RemoteFolders(
        store: store,
        connect: (_) async => fs,
        listShares: (connection) async => empty ? [] : fakeShares(connection),
      );
      await mount(tester, remote);
      expect(
        find.textContaining('No accessible shared folders'),
        findsOneWidget,
      );
      await tap(tester, 'Enter path manually');
      empty = false;
      await tap(tester, 'Browse shared folders');
      await tap(tester, 'Music');
      await tap(tester, 'Use this folder');
      expect(find.textContaining('Write check failed.'), findsOneWidget);
      expect(remote.destination, isNull);
      expect(remote.connection, isNotNull);
      expect(fs.files, isEmpty);
      await tester.pumpWidget(const SizedBox());
      remote.dispose();
    },
  );

  testWidgets('login error and secure-save error stay distinct and sanitized', (
    tester,
  ) async {
    for (final failSave in [false, true]) {
      final store = MemoryRemoteStore()..failWrite = failSave;
      final remote = RemoteFolders(
        store: store,
        listShares: fakeShares,
        checkLogin: (_) async {
          if (!failSave) {
            throw const Smb2Exception(
              'synthetic-password',
              type: Smb2ErrorType.auth,
            );
          }
        },
      );
      await mount(tester, remote);
      await enterLogin(tester);
      await tap(tester, 'Check connection');
      expect(
        find.textContaining(
          failSave
              ? 'Login verified. Secure storage unavailable.'
              : 'The server rejected this login.',
        ),
        findsOneWidget,
      );
      expect(find.text('Login verified'), findsNothing);
      expect(find.text('Shared folders'), findsNothing);
      expect(store.value, isNull);
      await tester.pumpWidget(const SizedBox());
      remote.dispose();
    }
  });

  testWidgets(
    'leaving during share discovery ignores the late result and retains login',
    (tester) async {
      final pending = Completer<List<Smb2ShareInfo>>();
      final store = MemoryRemoteStore()
        ..value = RemoteFolderConfig(destination().connection);
      final remote = RemoteFolders(
        store: store,
        listShares: (_) => pending.future,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RemoteFolderSettings(remote: remote),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(remote.busy, isTrue);
      await tester.pumpWidget(const SizedBox());
      pending.complete([]);
      await tester.pumpAndSettle();
      expect(store.value?.connection.host, 'server');
      expect(store.value?.destination, isNull);
      expect(remote.busy, isFalse);
      expect(tester.takeException(), isNull);
      remote.dispose();
    },
  );
}
