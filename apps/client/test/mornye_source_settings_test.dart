import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperstream_client/features/settings/mornye_source_settings.dart';
import 'package:hyperstream_client/services/mornye_sources.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'extension settings fit a narrow phone with large text in $brightness',
      (tester) async {
        tester.view.physicalSize = const Size(320, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final sources = MornyeSources();
        sources.extensions = [
          for (final entry in [
            ('spotify-web', 'Spotify Web', false),
            ('tidal-web', 'Tidal', true),
            ('qobuz-web', 'Qobuz', true),
          ])
            MornyeExtension({
              'id': entry.$1,
              'display_name': entry.$2,
              'audio': entry.$3,
              'version': '1.0.0',
              'download_url': 'https://example.test/package',
              'sha256': 'test',
              'installed': true,
              'enabled': true,
            }),
        ];
        sources.audioProvider = 'tidal-web';
        sources.verification.value = 'qobuz-web';
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 700),
                textScaler: TextScaler.linear(1.6),
              ),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: MornyeSourceSettings(sources: sources),
                  ),
                ),
              ),
            ),
          ),
        );
        expect(find.text('Spotify Web'), findsOneWidget);
        expect(find.text('Verify'), findsNWidgets(2));
        await tester.ensureVisible(find.text('Audio source for Spotify'));
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        sources.dispose();
      },
    );
  }
}
