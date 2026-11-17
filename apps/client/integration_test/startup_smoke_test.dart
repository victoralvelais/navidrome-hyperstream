import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperstream_client/features/connect/connection_screen.dart';
import 'package:hyperstream_client/main.dart';
import 'package:hyperstream_client/services/account_session.dart';
import 'package:hyperstream_client/services/account_store.dart';
import 'package:hyperstream_client/services/mornye_sources.dart';
import 'package:hyperstream_client/services/remote_transfer_background.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Establish the platform-owned semantics handle before testWidgets records
  // its baseline. Late iOS accessibility callbacks then reuse the same handle.
  binding.platformDispatcher.semanticsEnabledTestValue = true;
  tearDownAll(binding.platformDispatcher.clearSemanticsEnabledTestValue);

  testWidgets('real app startup reaches sign-in with native settings and audio', (
    tester,
  ) async {
    // Use an isolated empty account key, never the user's saved connection.
    // Read native settings, but do not connect to a server or start playback.
    await tester.pumpWidget(
      HyperstreamApp(
        accountSession: AccountSession(
          store: const SecureAccountStore(
            key: 'hyperstream.integration.startup.v1',
          ),
        ),
      ),
    );
    final deadline = DateTime.now().add(const Duration(seconds: 25));
    while (find.byType(ConnectionScreen).evaluate().isEmpty &&
        DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
      find.byType(ConnectionScreen),
      findsOneWidget,
      reason:
          'Startup did not reach sign-in. Visible text: ${tester.widgetList<Text>(find.byType(Text)).map((text) => text.data).join(' | ')}',
    );
    expect(find.text('Connect'), findsOneWidget);
    expect(tester.takeException(), isNull);
    // Normal startup initializes source storage before sign-in. Exercising that
    // entry point catches iOS directory protection errors hidden by FFI-only tests.
    final sources = MornyeSources.instance;
    expect(sources.error, isNull, reason: sources.error);
    expect(
      sources.extensions.map((source) => source.id),
      containsAll([
        'spotify-web',
        'tidal-web',
        'qobuz-web',
        'ytmusic-spotiflac',
      ]),
    );
    if (Platform.isIOS) {
      await tester.runAsync(() async {
        final background = RemoteTransferBackground();
        final download = await Directory('${sources.root!.path}/downloads')
            .createTemp('audio-integration-');
        final cache = await getTemporaryDirectory();
        final share = await Directory('${cache.path}/hyperstream-share')
            .create(recursive: true);
        final transfer = await share.createTemp('integration-');
        final support = await getApplicationSupportDirectory();
        final outside = await support.createTemp('music-extensions-other-');
        final link = Link('${download.path}/outside');
        try {
          await background.prepareDirectory(sources.root!);
          await background.prepareDirectory(download);
          await background.prepareDirectory(transfer);
          await expectLater(
            background.prepareDirectory(outside),
            throwsA(isA<PlatformException>()),
          );
          await link.create(outside.path);
          await expectLater(
            background.prepareDirectory(Directory(link.path)),
            throwsA(isA<PlatformException>()),
          );
        } finally {
          if (await link.exists()) await link.delete();
          await download.delete(recursive: true);
          await transfer.delete(recursive: true);
          await outside.delete(recursive: true);
        }
      });
    }
    // Leave sign-in visible for the host's screenshot. The host terminates the
    // simulator app; widget tests separately cover disposal during startup.
    binding.reportData = {
      'startupReachedSignIn': true,
      'musicSourcesAvailable': true,
    };
  });
}
