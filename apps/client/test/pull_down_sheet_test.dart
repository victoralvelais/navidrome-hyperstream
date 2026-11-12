import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperstream_client/widgets/glass_overlays.dart';

const _header = ValueKey('sheet-header');
const _list = ValueKey('sheet-list');

class _Queue extends StatefulWidget {
  const _Queue(this.count);
  final int count;
  @override
  State<_Queue> createState() => _QueueState();
}

class _QueueState extends State<_Queue> {
  late final songs = List.generate(widget.count, (i) => i);
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 520,
    child: Column(
      children: [
        const SizedBox(
          height: 48,
          child: Center(child: Text('Up next', key: _header)),
        ),
        Expanded(
          child: CustomScrollView(
            key: _list,
            controller: PrimaryScrollController.of(context),
            slivers: [
              if (songs.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: Text('Empty queue')),
                ),
              SliverReorderableList(
                itemCount: songs.length,
                onReorderItem: (from, to) =>
                    setState(() => songs.insert(to, songs.removeAt(from))),
                itemBuilder: (context, i) => SizedBox(
                  key: ValueKey(songs[i]),
                  height: 60,
                  child: Row(
                    children: [
                      Expanded(child: Text('Song ${songs[i]}')),
                      ReorderableDragStartListener(
                        index: i,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Icon(
                            Icons.drag_handle,
                            key: ValueKey('reorder-${songs[i]}'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(
          height: 48,
          child: Center(child: Text('Playback controls')),
        ),
      ],
    ),
  );
}

Future<void> _open(WidgetTester tester, {int count = 30}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showGlassSheet<void>(
                context: context,
                pullFromList: true,
                builder: (_) => _Queue(count),
              ),
              child: const Text('Open queue'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open queue'));
  await tester.pumpAndSettle();
}

Offset _grab(WidgetTester tester) =>
    tester.getTopLeft(find.byKey(_list)) + const Offset(100, 100);

void main() {
  final platforms = TargetPlatformVariant({
    TargetPlatform.iOS,
    TargetPlatform.windows,
  });
  testWidgets(
    'list stretch tapers into panel motion and a cancelled pull settles back',
    (tester) async {
      await _open(tester);
      final top = tester.getTopLeft(find.byKey(_header)).dy;
      final first = tester.getTopLeft(find.text('Song 0')).dy;
      final gesture = await tester.startGesture(_grab(tester));
      await gesture.moveBy(const Offset(0, 20));
      await gesture.moveBy(const Offset(0, 35));
      await tester.pump();
      expect(tester.getTopLeft(find.byKey(_header)).dy, closeTo(top, .01));
      expect(tester.getTopLeft(find.text('Song 0')).dy, greaterThan(first));
      await gesture.moveBy(const Offset(0, 110));
      await tester.pump();
      final panelTravel = tester.getTopLeft(find.byKey(_header)).dy - top;
      expect(panelTravel, greaterThan(30));
      final listTravel =
          tester.getTopLeft(find.text('Song 0')).dy - first - panelTravel;
      expect(listTravel, inExclusiveRange(15, 30));
      // Even beyond the release threshold, an OS-cancelled gesture must not pop.
      await gesture.moveBy(const Offset(0, 120));
      await tester.pump();
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(find.byKey(_header), findsOneWidget);
      expect(tester.getTopLeft(find.byKey(_header)).dy, closeTo(top, .01));
      expect(tester.getTopLeft(find.text('Song 0')).dy, closeTo(first, .01));
      final shortPull = await tester.startGesture(_grab(tester));
      await shortPull.moveBy(const Offset(0, 20));
      await shortPull.moveBy(const Offset(0, 50));
      await tester.pump(const Duration(milliseconds: 300));
      await shortPull.up();
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byKey(_header)).dy, closeTo(top, .01));
    },
    variant: platforms,
  );

  for (final count in [0, 3, 30]) {
    testWidgets(
      'a long pull from a $count-track list dismisses the entire sheet',
      (tester) async {
        await _open(tester, count: count);
        final gesture = await tester.startGesture(_grab(tester));
        await gesture.moveBy(const Offset(0, 20));
        await gesture.moveBy(const Offset(0, 250));
        await tester.pump(const Duration(milliseconds: 400));
        await gesture.up();
        await tester.pumpAndSettle();
        expect(find.byKey(_header), findsNothing);
        expect(find.text('Open queue').hitTestable(), findsOneWidget);
      },
      variant: platforms,
    );
  }

  testWidgets(
    'scrolling reaches the top before handing the same drag to the panel',
    (tester) async {
      await _open(tester);
      final view = tester.widget<CustomScrollView>(find.byKey(_list));
      view.controller!.jumpTo(160);
      await tester.pump();
      final top = tester.getTopLeft(find.byKey(_header)).dy;
      final gesture = await tester.startGesture(_grab(tester));
      await gesture.moveBy(const Offset(0, 20));
      await gesture.moveBy(const Offset(0, 70));
      await tester.pump();
      expect(view.controller!.offset, greaterThan(0));
      expect(view.controller!.offset, lessThan(160));
      expect(tester.getTopLeft(find.byKey(_header)).dy, closeTo(top, .01));
      await gesture.moveBy(const Offset(0, 200));
      await tester.pump();
      expect(tester.getTopLeft(find.byKey(_header)).dy, greaterThan(top));
      // Reversing the finger restores the sheet and resumes normal list scrolling.
      await gesture.moveBy(const Offset(0, -230));
      await tester.pump();
      expect(tester.getTopLeft(find.byKey(_header)).dy, closeTo(top, .01));
      expect(view.controller!.offset, greaterThan(0));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.byKey(_header), findsOneWidget);
    },
    variant: platforms,
  );

  testWidgets(
    'wheel scrolling and track reordering do not pull the sheet down',
    (tester) async {
      await _open(tester);
      final top = tester.getTopLeft(find.byKey(_header)).dy;
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: _grab(tester),
          scrollDelta: const Offset(0, -200),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byKey(_header)).dy, closeTo(top, .01));
      final handle = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('reorder-0'))),
      );
      await handle.moveBy(const Offset(0, 150));
      await tester.pump(const Duration(milliseconds: 500));
      await handle.up();
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('Song 0')).dy,
        greaterThan(tester.getTopLeft(find.text('Song 1')).dy),
      );
      expect(tester.getTopLeft(find.byKey(_header)).dy, closeTo(top, .01));
    },
    variant: platforms,
  );
}
