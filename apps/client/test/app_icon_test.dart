import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:hyperstream_client/models/icon_style.dart';
import 'package:hyperstream_client/services/app_preferences.dart';
import 'package:hyperstream_client/widgets/app_icon.dart';
import 'package:hyperstream_client/widgets/icon_style_picker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'every bundled action and family parses with the actual SVG renderer',
    () async {
      final assets = <String>{};
      for (final style in IconStyle.values) {
        for (final symbol in AppIcon.supportedIcons) {
          final asset = AppIcon.assetFor(symbol, style);
          if (asset != null) assets.add(asset);
        }
      }
      expect(assets.length, greaterThan(700));
      for (final asset in assets) {
        final bytes = await SvgAssetLoader(asset).loadBytes(null);
        expect(bytes.lengthInBytes, greaterThan(0), reason: asset);
      }
    },
  );

  testWidgets(
    'family switches preserve content state and update an open route',
    (tester) async {
      final style = ValueNotifier(IconStyle.iconoir);
      final text = TextEditingController(text: 'keep my search');
      addTearDown(style.dispose);
      addTearDown(text.dispose);
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        ValueListenableBuilder(
          valueListenable: style,
          builder: (context, value, _) => MaterialApp(
            navigatorKey: navigator,
            builder: (context, child) =>
                AppIconTheme(style: value, child: child!),
            home: Scaffold(
              body: Column(
                children: [
                  TextField(controller: text),
                  const AppIcon(Icons.home_outlined),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: AppIcon(Icons.search_rounded)),
        ),
      );
      await tester.pumpAndSettle();
      style.value = IconStyle.solarBroken;
      await tester.pumpAndSettle();
      final svg = tester.widget<SvgPicture>(find.byType(SvgPicture));
      expect(
        (svg.bytesLoader as SvgAssetLoader).assetName,
        'assets/icons/solarBroken/search.svg',
      );
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('keep my search'), findsOneWidget);
      expect(
        (tester.widget<SvgPicture>(find.byType(SvgPicture)).bytesLoader
                as SvgAssetLoader)
            .assetName,
        'assets/icons/solarBroken/home.svg',
      );
      style.value = IconStyle.cupertino;
      await tester.pumpAndSettle();
      expect(find.byIcon(CupertinoIcons.house), findsOneWidget);
    },
  );

  testWidgets(
    'SVG icons retain theme opacity, text scaling, RTL and semantics',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(1.5)),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: IconTheme(
                data: IconThemeData(
                  size: 20,
                  color: Colors.purple,
                  opacity: .4,
                  applyTextScaling: true,
                ),
                child: AppIcon(
                  Icons.arrow_back_rounded,
                  semanticLabel: 'Go back',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final svg = tester.widget<SvgPicture>(find.byType(SvgPicture));
      expect(svg.width, 30);
      expect(svg.height, 30);
      expect(svg.matchTextDirection, isTrue);
      expect(
        svg.colorFilter,
        ColorFilter.mode(Colors.purple.withValues(alpha: .4), BlendMode.srcIn),
      );
      expect(find.bySemanticsLabel('Go back'), findsOneWidget);
      semantics.dispose();
    },
  );

  testWidgets(
    'all picker styles apply immediately and previews keep their own family',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final preferences = AppPreferences();
      addTearDown(preferences.dispose);
      await tester.pumpWidget(
        ListenableBuilder(
          listenable: preferences,
          builder: (context, _) => MaterialApp(
            builder: (context, child) =>
                AppIconTheme(style: preferences.iconStyle, child: child!),
            home: Scaffold(
              body: SingleChildScrollView(
                child: IconStylePicker(
                  value: preferences.iconStyle,
                  onChanged: preferences.setIconStyle,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final style in IconStyle.values) {
        final row = find.byKey(ValueKey('icon-style-${style.name}'));
        await tester.ensureVisible(row);
        await tester.tap(row);
        await tester.pumpAndSettle();
        expect(preferences.iconStyle, style);
        final preview = find.descendant(
          of: row,
          matching: find.byWidgetPredicate(
            (widget) => widget is AppIcon && widget.style == style,
          ),
        );
        expect(preview, findsNWidgets(6));
        expect(tester.takeException(), isNull);
      }
    },
  );
}
