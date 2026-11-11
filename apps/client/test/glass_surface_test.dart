import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperstream_client/services/app_preferences.dart';
import 'package:hyperstream_client/widgets/glass_settings.dart';
import 'package:hyperstream_client/widgets/glass_surface.dart';

void main() {
  testWidgets(
    'saved glass preference and high contrast give usable opaque controls',
    (tester) async {
      final preferences = AppPreferences();
      var presses = 0;
      Widget app({bool highContrast = false}) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(highContrast: highContrast),
          child: GlassSettings(
            preferences: preferences,
            child: Center(
              child: GlassSurface(
                child: TextButton(
                  onPressed: () => presses++,
                  child: const Text('Play'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(app());
      expect(find.byType(BackdropFilter), findsOneWidget);
      await preferences.setGlassEffects(false);
      await tester.pump();
      expect(find.byType(BackdropFilter), findsNothing);
      await tester.tap(find.text('Play'));
      expect(presses, 1);
      await preferences.setGlassEffects(true);
      await tester.pumpWidget(app(highContrast: true));
      expect(find.byType(BackdropFilter), findsNothing);
      await tester.tap(find.text('Play'));
      expect(presses, 2);
      await tester.pumpWidget(const SizedBox.shrink());
      preferences.dispose();
    },
  );

  testWidgets(
    'iOS Reduce Transparency updates live and native failures stay opaque',
    (tester) async {
      const channel = MethodChannel('dev.hyperstream/appearance');
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (_) async => false);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      Widget app() => const MaterialApp(
        home: GlassSettings(
          child: Center(
            child: GlassSurface(child: SizedBox(width: 100, height: 60)),
          ),
        ),
      );
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsOneWidget);
      await messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('reduceTransparencyChanged', true),
        ),
        null,
      );
      await tester.pump();
      expect(find.byType(BackdropFilter), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(code: 'unavailable'),
      );
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: TargetPlatformVariant({TargetPlatform.iOS}),
  );
}
