import 'package:flutter_test/flutter_test.dart';
import 'package:hyperstream_client/services/listen_tracker.dart';

void main() {
  late Duration clock;
  late ListenTracker tracker;
  late List<(String, DateTime)> listens;
  final start = DateTime.utc(2026, 11, 11, 18);
  setUp(() {
    clock = Duration.zero;
    listens = [];
    tracker = ListenTracker(
      elapsed: () => clock,
      now: () => start.add(clock),
      onListen: (id, time) => listens.add((id, time)),
    );
  });
  void advance(int seconds, {bool active = true, int duration = 180}) {
    for (var i = 0; i < seconds; i++) {
      clock += const Duration(seconds: 1);
      tracker.update(
        active: active,
        duration: Duration(seconds: duration),
      );
    }
  }

  test('half the track counts once, with the first audible start time', () {
    tracker.begin('one', const Duration(seconds: 180));
    advance(5, active: false);
    tracker.update(active: true, duration: const Duration(seconds: 180));
    advance(89);
    expect(listens, isEmpty);
    advance(1);
    expect(listens, [('one', start.add(const Duration(seconds: 5)))]);
    advance(200);
    expect(listens, hasLength(1));
  });
  test(
    'paused/buffering time earns no credit; wall clock gaps are conservative',
    () {
      tracker.begin('one', const Duration(seconds: 180));
      tracker.update(active: true, duration: const Duration(seconds: 180));
      advance(40);
      tracker.update(active: false, duration: const Duration(seconds: 180));
      advance(100, active: false);
      clock += const Duration(hours: 1);
      tracker.update(active: true, duration: const Duration(seconds: 180));
      advance(49);
      expect(listens, isEmpty);
      advance(1);
      expect(listens, hasLength(1));
    },
  );
  test(
    'long tracks cap at four minutes; short and unknown tracks do not count',
    () {
      for (final duration in [0, 30, 1800]) {
        tracker.begin('$duration', Duration(seconds: duration));
        tracker.update(active: true, duration: Duration(seconds: duration));
        advance(239, duration: duration);
        expect(listens, isEmpty);
        advance(1, duration: duration);
      }
      expect(listens.map((l) => l.$1), ['1800']);
    },
  );
  test('track replacement and reset discard partial old listens', () {
    tracker.begin('one', const Duration(seconds: 180));
    tracker.update(active: true, duration: const Duration(seconds: 180));
    advance(60);
    tracker.begin('two', const Duration(seconds: 180));
    tracker.update(active: true, duration: const Duration(seconds: 180));
    advance(89);
    expect(listens, isEmpty);
    advance(1);
    expect(listens.map((l) => l.$1), ['two']);
    tracker.clear();
    advance(100);
    expect(listens, hasLength(1));
  });
  test('an unobserved long gap while marked playing is not counted', () {
    tracker.begin('one', const Duration(seconds: 180));
    tracker.update(active: true, duration: const Duration(seconds: 180));
    clock += const Duration(hours: 1);
    tracker.update(active: true, duration: const Duration(seconds: 180));
    expect(listens, isEmpty);
    advance(90);
    expect(listens, hasLength(1));
  });
}
