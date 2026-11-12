import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperstream_client/features/player/output_button.dart';
import 'package:hyperstream_client/app_theme.dart';
import 'package:hyperstream_client/widgets/glass_surface.dart';

void main() {
  testWidgets(
    'native output picker is outside glass filters and receives both theme colors',
    (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform_views,
        (_) async => null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform_views,
          null,
        ),
      );
      var taps = 0;
      for (final brightness in [Brightness.light, Brightness.dark]) {
        final theme = hyperstreamTheme(brightness);
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: Center(
                child: GlassSurface(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const OutputButton(),
                      IconButton(
                        tooltip: 'Music volume',
                        onPressed: () => taps++,
                        icon: const Icon(Icons.volume_up),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final native = find.byType(UiKitView);
        expect(native, findsOneWidget);
        expect(
          find.ancestor(of: native, matching: find.byType(BackdropFilter)),
          findsNothing,
        );
        expect(
          find.ancestor(
            of: find.byTooltip('Music volume'),
            matching: find.byType(BackdropFilter),
          ),
          findsNothing,
        );
        final params = tester.widget<UiKitView>(native).creationParams as Map;
        expect(params['dark'], brightness == Brightness.dark);
        expect(params['tint'], theme.colorScheme.onSurface.toARGB32());
        expect(params['activeTint'], theme.colorScheme.primary.toARGB32());
        await tester.tap(find.byTooltip('Music volume'));
        expect(tester.takeException(), isNull);
      }
      expect(taps, 2);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
    variant: TargetPlatformVariant({TargetPlatform.iOS}),
  );

  testWidgets(
    'output selection waits for native success and reports disconnected devices',
    (tester) async {
      const channel = MethodChannel('dev.hyperstream/audio_outputs');
      var selected = '';
      var fail = false;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'getOutputs') {
          return [
            {'id': '', 'name': 'System default', 'selected': selected.isEmpty},
            {
              'id': 'headphones',
              'name': 'Headphones',
              'selected': selected == 'headphones',
            },
          ];
        }
        if (fail) {
          throw PlatformException(
            code: 'unavailable',
            message: 'private native details',
          );
        }
        selected = call.arguments as String;
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: AudioOutputsSheet())),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Headphones'));
      await tester.pumpAndSettle();
      expect(selected, 'headphones');
      expect(
        tester
            .widget<ListTile>(find.widgetWithText(ListTile, 'Headphones'))
            .selected,
        isTrue,
      );
      fail = true;
      await tester.tap(find.text('System default'));
      await tester.pumpAndSettle();
      expect(selected, 'headphones');
      expect(find.textContaining('may have disconnected'), findsOneWidget);
      expect(find.textContaining('private native details'), findsNothing);
    },
  );
}
