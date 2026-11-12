import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperstream_client/features/player/output_button.dart';
import 'package:hyperstream_client/app_theme.dart';
import 'package:hyperstream_client/widgets/glass_surface.dart';
import 'package:hyperstream_client/widgets/glass_overlays.dart';

void main() {
  testWidgets(
    'AirPlay unmounts under sheets and local overlays and returns after transitions',
    (tester) async {
      var created = 0;
      var disposed = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform_views,
        (call) async {
          if (call.method == 'create') created++;
          if (call.method == 'dispose') disposed++;
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform_views,
          null,
        ),
      );
      final obscured = ValueNotifier(false);
      addTearDown(obscured.dispose);
      late BuildContext playerContext;
      late BuildContext queueContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (context) {
                    playerContext = context;
                    return SizedBox(
                      height: 550,
                      child: Center(
                        child: ValueListenableBuilder<bool>(
                          valueListenable: obscured,
                          builder: (_, covered, _) =>
                              OutputButton(obscured: covered),
                        ),
                      ),
                    );
                  },
                ),
                child: const Text('Open player'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open player'));
      await tester.pumpAndSettle();
      final native = find.byType(UiKitView, skipOffstage: false);
      final placeholder = find.byKey(
        const ValueKey('covered-airplay-placeholder'),
      );
      expect(native, findsOneWidget);
      final slot = tester.getRect(native);
      expect(created, 1);

      unawaited(
        showGlassSheet<void>(
          context: playerContext,
          builder: (context) {
            queueContext = context;
            return const SizedBox(
              height: 400,
              child: Center(child: Text('Up next')),
            );
          },
        ),
      );
      await tester.pump();
      expect(native, findsNothing);
      await tester.pumpAndSettle();
      expect(
        disposed,
        1,
        reason: 'The native view must actually leave UIKit, not only become transparent.',
      );
      expect(
        tester.getRect(placeholder),
        slot,
        reason: 'Covered controls must not move the volume button.',
      );

      // Nested queue options must not cause the underlying AirPlay view to return.
      unawaited(
        showDialog<void>(
          context: queueContext,
          builder: (_) => const AlertDialog(content: Text('Queue options')),
        ),
      );
      await tester.pumpAndSettle();
      expect(native, findsNothing);
      Navigator.of(queueContext).pop();
      await tester.pumpAndSettle();
      expect(native, findsNothing);
      Navigator.of(queueContext).pop();
      await tester.pump(const Duration(milliseconds: 30));
      expect(
        native,
        findsNothing,
        reason: 'Wait for the translucent sheet to finish leaving.',
      );
      await tester.pumpAndSettle();
      expect(native, findsOneWidget);
      expect(created, 2);

      // The volume popover uses an OverlayEntry rather than another route.
      obscured.value = true;
      await tester.pumpAndSettle();
      expect(native, findsNothing);
      expect(disposed, 2);
      obscured.value = false;
      await tester.pumpAndSettle();
      expect(native, findsOneWidget);
      expect(created, 3);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({TargetPlatform.iOS}),
  );

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
