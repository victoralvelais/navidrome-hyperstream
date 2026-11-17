import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperstream_client/features/sources/source_verification_flow.dart';
import 'package:hyperstream_client/services/mornye_sources.dart';

class _Sources extends MornyeSources {
  int browsers = 0;
  bool verified = false;
  bool automatic = false;
  @override
  Future<bool> verify(String id) async {
    browsers++;
    return automatic;
  }

  @override
  Future<void> pasteVerification(String id, String text) async {
    expect(id, 'tidal-web');
    expect(text, 'grant=gr_synthetic');
    verified = true;
  }
}

void main() {
  late _Sources sources;
  late GlobalKey<NavigatorState> navigation;
  setUp(() {
    sources = _Sources();
    navigation = GlobalKey<NavigatorState>();
  });
  tearDown(() => sources.dispose());
  Future<void> mount(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigation,
        builder: (_, child) => SourceVerificationHost(
          sources: sources,
          navigatorKey: navigation,
          child: child!,
        ),
        home: const Scaffold(body: Text('Current music page')),
      ),
    );
  }

  testWidgets(
    'verification opens over the current page and resumes the original action after paste',
    (tester) async {
      await mount(tester);
      var attempts = 0;
      final action = sources.withVerification(() async {
        attempts++;
        if (!sources.verified) throw ProviderVerificationRequired('tidal-web');
        return 'Playing';
      });
      final duplicate = sources.requestVerification('tidal-web');
      await tester.pumpAndSettle();
      expect(sources.browsers, 1);
      expect(find.byType(SourceVerificationDialog), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'grant=gr_synthetic');
      await tester.tap(find.text('Complete verification'));
      await tester.pumpAndSettle();
      expect(await action, 'Playing');
      expect(await duplicate, true);
      expect(attempts, 2);
      expect(find.text('Current music page'), findsOneWidget);
      expect(navigation.currentState!.canPop(), false);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'a background request waits for foreground and disposal cancels a queued presentation',
    (tester) async {
      await mount(tester);
      sources.automatic = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      final first = sources.requestVerification('tidal-web');
      await tester.pump();
      expect(sources.browsers, 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(await first, true);
      expect(sources.browsers, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      final second = sources.requestVerification('tidal-web');
      await tester.pump();
      // Inactive still permits a widget frame while keeping the browser deferred.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pumpWidget(const SizedBox());
      expect(await second, false);
      expect(sources.browsers, 1);
      expect(sources.presentVerification, isNull);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    },
  );
}
