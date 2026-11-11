/// A playback instance counts once, using elapsed listening time, never position.
/// The owner supplies a monotonic clock and samples while audio is ready/playing.
class ListenTracker {
  ListenTracker({
    required this.elapsed,
    required this.now,
    required this.onListen,
  });

  final Duration Function() elapsed;
  final DateTime Function() now;
  final void Function(String trackId, DateTime startedAt) onListen;
  String? _trackId;
  DateTime? _startedAt;
  Duration? _sample;
  Duration _listened = Duration.zero;
  Duration _duration = Duration.zero;
  bool _active = false;
  bool _submitted = false;
  bool get pending => _trackId != null && !_submitted;

  void begin(String trackId, Duration duration) {
    clear();
    _trackId = trackId;
    _duration = duration;
    _sample = elapsed();
  }

  void update({required bool active, required Duration duration}) {
    final current = elapsed();
    final delta = current - (_sample ?? current);
    // A stalled/suspended Dart runtime cannot establish what native audio did.
    // Drop long unobserved gaps rather than invent listening credit.
    if (_active &&
        delta >= Duration.zero &&
        delta <= const Duration(seconds: 5)) {
      _listened += delta;
    }
    _sample = current;
    _active = active;
    _duration = duration;
    if (active) _startedAt ??= now().toUtc();
    final threshold = Duration(microseconds: _duration.inMicroseconds ~/ 2);
    final requiredTime = threshold < const Duration(minutes: 4)
        ? threshold
        : const Duration(minutes: 4);
    if (pending &&
        _startedAt != null &&
        _duration > const Duration(seconds: 30) &&
        _listened >= requiredTime) {
      _submitted = true;
      onListen(_trackId!, _startedAt!);
    }
  }

  void clear() {
    _trackId = null;
    _startedAt = null;
    _sample = null;
    _listened = Duration.zero;
    _duration = Duration.zero;
    _active = false;
    _submitted = false;
  }
}
