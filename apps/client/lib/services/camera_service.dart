import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Owns the camera route's bridge subscription. Music remains in PlaybackService.
class CameraService extends ChangeNotifier {
  CameraService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('dev.hyperstream/camera');

  final MethodChannel _channel;
  static bool get supported => defaultTargetPlatform == TargetPlatform.iOS;
  int? texture;
  bool ready = false;
  bool front = false;
  bool captured = false;
  double aspect = 9 / 16;
  String phase = 'idle';
  String message = '';
  String report = '';
  int pending = 0;
  bool _disposed = false;
  bool _closed = false;
  bool get recording => phase == 'recording' || phase == 'starting';
  bool get saving => phase == 'saving';

  Future<void> open() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'state' && !_disposed) _read(call.arguments);
    });
    try {
      final state = await _channel.invokeMethod<Object?>('open');
      if (!_disposed) _read(state);
    } on PlatformException catch (error) {
      _error(error.message ?? 'The camera could not open. Try again.');
    } on MissingPluginException {
      _error('The camera is available in the iPhone and iPad app.');
    }
  }

  void _read(Object? value) {
    if (value is! Map) return;
    texture = (value['texture'] as num?)?.toInt();
    ready = value['ready'] == true;
    front = value['front'] == true;
    captured = value['captured'] == true;
    aspect = (value['aspect'] as num?)?.toDouble() ?? 9 / 16;
    phase = value['phase'] as String? ?? 'idle';
    message = value['message'] as String? ?? '';
    report = value['report'] as String? ?? '';
    pending = (value['pending'] as num?)?.toInt() ?? 0;
    notifyListeners();
  }

  void _error(String value) {
    if (_disposed) return;
    message = value;
    notifyListeners();
  }

  Future<void> _command(String command, [Object? arguments]) async {
    try {
      await _channel.invokeMethod<void>(command, arguments);
    } on PlatformException catch (error) {
      _error(error.message ?? 'The camera could not finish. Try again.');
    } on MissingPluginException {
      _error('The camera is available in the iPhone and iPad app.');
    }
  }

  Future<void> start({required bool originalTempo}) =>
      _command('start', {'originalTempo': originalTempo});
  Future<void> stop() => _command('stop');
  Future<void> switchCamera() => _command('switchCamera');
  Future<void> retry() => _command('retry');
  Future<void> recoverVideo() => _command('recoverVideo');
  Future<void> dismissMessage() => _command('dismissMessage');

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _command('close');
  }

  @override
  void dispose() {
    _disposed = true;
    _channel.setMethodCallHandler(null);
    super.dispose();
  }
}
