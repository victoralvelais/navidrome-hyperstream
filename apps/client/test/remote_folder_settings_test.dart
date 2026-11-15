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
  await tester.enterText(field('Username'), 'COMPUTER/Listener');
  await tester.enterText(field('Password'), 'synthetic-password');
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
    'login saves independently, then a folder can be tested on a small phone',
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
        checkLogin: (connection) async {
          loginChecks++;
          expect(connection.domain, 'COMPUTER');
          expect(connection.user, 'Listener');
        },
      );
      await mount(tester, remote);
      expect(
        tester.widget<TextFormField>(field('Share name')).enabled,
        isFalse,
      );
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
      expect(store.value?.connection.password, 'synthetic-password');
      expect(store.value?.destination, isNull);
      expect(fs.closed, isFalse);
      expect(find.text('Login verified'), findsOneWidget);
      if (const bool.fromEnvironment('CAPTURE_PREVIEWS')) {
        await tester.ensureVisible(find.text('Login verified'));
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('../build/previews/remote-login-verified.png'),
        );
      }
      await tester.enterText(field('Share name'), 'Music');
      await tester.enterText(field('Subfolder (optional)'), 'Test');
      await tap(tester, 'Test and save folder');
      expect(remote.destination?.address, 'smb://server/Music/Test');
      expect(fs.files, isEmpty);
      expect(find.textContaining('Folder verified and saved'), findsOneWidget);
      if (const bool.fromEnvironment('CAPTURE_PREVIEWS')) {
        await tester.ensureVisible(
          find.textContaining('Folder verified and saved'),
        );
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('../build/previews/remote-folder-verified.png'),
        );
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      remote.dispose();
    },
  );

  testWidgets(
    'failed share leaves the login verified and permits a corrected share',
    (tester) async {
      final fs = MemoryRemoteFs();
      var loginChecks = 0;
      final remote = RemoteFolders(
        store: MemoryRemoteStore(),
        checkLogin: (_) async {
          loginChecks++;
        },
        connect: (destination) async {
          if (destination.share != 'Music') {
            throw const Smb2Exception(
              'private server response',
              type: Smb2ErrorType.notFound,
            );
          }
          return fs;
        },
      );
      await mount(tester, remote);
      await enterLogin(tester);
      await tap(tester, 'Check connection');
      await tester.enterText(field('Share name'), 'Wrong');
      await tap(tester, 'Test and save folder');
      expect(find.textContaining('Share check failed.'), findsOneWidget);
      expect(find.text('Login verified'), findsOneWidget);
      expect(remote.connection, isNotNull);
      expect(remote.destination, isNull);
      await tester.enterText(field('Share name'), 'Music');
      await tap(tester, 'Test and save folder');
      expect(remote.destination?.folder, isEmpty);
      expect(loginChecks, 1);
      await tap(tester, 'Edit or recheck connection');
      expect(find.text('Login verified'), findsNothing);
      expect(
        tester.widget<TextFormField>(field('Share name')).enabled,
        isFalse,
      );
      await tester.enterText(field('Server address'), 'another-server');
      await tap(tester, 'Check connection');
      expect(remote.destination, isNull);
      expect(
        tester.widget<TextFormField>(field('Share name')).controller!.text,
        isEmpty,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      remote.dispose();
    },
  );

  testWidgets(
    'saved login is prefilled but does not claim current verification',
    (tester) async {
      final store = MemoryRemoteStore()
        ..value = RemoteFolderConfig.forDestination(destination());
      final remote = RemoteFolders(store: store, checkLogin: (_) async {});
      await mount(tester, remote);
      expect(
        tester.widget<TextFormField>(field('Server address')).controller!.text,
        'smb://server',
      );
      expect(
        tester.widget<TextFormField>(field('Share name')).controller!.text,
        'share',
      );
      expect(find.text('Login verified'), findsNothing);
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

  testWidgets('login error and secure-save error are distinct and sanitized', (
    tester,
  ) async {
    for (final failSave in [false, true]) {
      final store = MemoryRemoteStore()..failWrite = failSave;
      final remote = RemoteFolders(
        store: store,
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
      expect(
        tester.widget<TextFormField>(field('Share name')).enabled,
        isFalse,
      );
      expect(store.value, isNull);
      await tester.pumpWidget(const SizedBox());
      remote.dispose();
    }
  });

  testWidgets(
    'leaving during login saves safely and restores without a folder',
    (tester) async {
      final pending = Completer<void>();
      final store = MemoryRemoteStore();
      final remote = RemoteFolders(
        store: store,
        checkLogin: (_) => pending.future,
      );
      await mount(tester, remote);
      await enterLogin(tester);
      await tester.ensureVisible(find.text('Check connection'));
      await tester.tap(find.text('Check connection'));
      await tester.pump();
      expect(remote.busy, isTrue);
      await tester.pumpWidget(const SizedBox());
      pending.complete();
      await tester.pumpAndSettle();
      expect(store.value?.connection.host, 'server');
      expect(store.value?.destination, isNull);
      expect(tester.takeException(), isNull);
      remote.dispose();
    },
  );
}
