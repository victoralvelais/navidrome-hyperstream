import 'dart:convert';

import '../models/source_reference.dart';

enum PlaybackStage {
  player,
  match,
  resolve,
  download,
  provider,
  transport,
  mediaProbe,
}

enum PlaybackOutcome { started, ready, failed, cancelled }

/// Extract facts from private errors, never their text. The report is deliberately
/// built from fixed labels and numbers, not a redacted copy of a provider log.
class PlaybackFailureFacts {
  PlaybackFailureFacts._(this.reasons, this.httpStatuses);
  final List<String> reasons;
  final List<int> httpStatuses;

  factory PlaybackFailureFacts.read(String detail) {
    final text = detail.toLowerCase();
    final statuses =
        RegExp(r'\b(?:http(?: status)?|status(?:code)?)\s*[:=]?\s*([45]\d\d)\b')
            .allMatches(text)
            .map((match) => int.parse(match[1]!))
            .toSet()
            .toList()
          ..sort();
    final reasons = <String>[
      if (text.contains('all qobuz download providers failed'))
        'all-audio-providers-failed',
      if (text.contains('verify_required') ||
          text.contains('verification_required') ||
          text.contains('needs verification'))
        'verification-required',
      if (statuses.contains(429) ||
          text.contains('rate limit') ||
          text.contains('rate_limit') ||
          text.contains('too many requests'))
        'rate-limited',
      if (text.contains('timeout') ||
          text.contains('timed out') ||
          text.contains('deadline exceeded'))
        'timeout',
      if (statuses.any((code) => code >= 500)) 'upstream-service-error',
      if (text.contains('provider_unavailable')) 'provider-unavailable',
      if (text.contains('request_auth_invalid')) 'request-auth-invalid',
      if (text.contains('session_invalid')) 'session-invalid',
      if (text.contains('ticket resource mismatch') ||
          text.contains('ticket expired') ||
          text.contains('ticket already consumed'))
        'ticket-rejected',
      if (text.contains('no active accounts') ||
          text.contains('no available accounts'))
        'provider-account-unavailable',
      if (statuses.contains(401) || statuses.contains(403)) 'access-rejected',
      if (statuses.contains(404) ||
          text.contains('track_unavailable') ||
          text.contains('track unavailable') ||
          text.contains('track not found') ||
          text.contains('not available for streaming'))
        'recording-unavailable',
      if (text.contains('cloudflare challenge')) 'upstream-challenge',
      if (text.contains('unexpected html') ||
          text.contains('non-json response'))
        'unexpected-response-format',
      if (text.contains('no download url') ||
          text.contains('missing expected payload'))
        'incomplete-provider-response',
      if (text.contains('missing ticket_id') ||
          text.contains('signed session runtime is not available'))
        'session-error',
      if (text.contains('preview-length') || text.contains('preview url'))
        'preview-only',
      if (text.contains('cancelled') ||
          text.contains('canceled') ||
          text.contains('superseded'))
        'cancelled',
      if (text.contains('socketexception') ||
          text.contains('failed host lookup') ||
          text.contains('connection refused') ||
          text.contains('connection reset'))
        'connection-error',
      if (text.contains('handshakeexception') || text.contains('certificate'))
        'tls-error',
      if (text.contains('out of memory')) 'runtime-memory-limit',
      if (text.contains('runtime is busy') || text.contains('runtime busy'))
        'runtime-busy',
    ];
    return PlaybackFailureFacts._(
      List.unmodifiable(reasons.isEmpty ? ['unclassified-error'] : reasons),
      List.unmodifiable(statuses),
    );
  }

  Map<String, Object> toJson() => {
    'reasons': reasons,
    if (httpStatuses.isNotEmpty) 'http_status': httpStatuses,
  };

  /// These failures already exhausted extension retries or need user action.
  /// Retrying from the native player would repeat the whole provider chain.
  bool get retryable => !reasons.any(
    const {
      'all-audio-providers-failed',
      'recording-unavailable',
      'preview-only',
      'rate-limited',
      'access-rejected',
      'request-auth-invalid',
      'session-invalid',
      'ticket-rejected',
      'provider-account-unavailable',
      'provider-unavailable',
      'verification-required',
      'cancelled',
    }.contains,
  );
}

/// A small, session-only diagnostic timeline. Nothing is uploaded or persisted.
/// Track titles/IDs, account/server details, URLs, paths and raw errors are absent.
class PlaybackDiagnostics {
  static final instance = PlaybackDiagnostics();
  final _events = <Map<String, Object>>[];
  final _recordings = <String, int>{};
  int _sequence = 0;
  int _nextRecording = 0;
  int _operation = 0;

  int beginOperation() => ++_operation;

  /// Session-local numbers allow comparing resolutions without exporting IDs.
  int recording(String sourceId, String privateTrackId) {
    final key = jsonEncode([sourceId, privateTrackId]);
    final existing = _recordings[key];
    if (existing != null) return existing;
    if (_recordings.length >= 512) _recordings.remove(_recordings.keys.first);
    return _recordings[key] = ++_nextRecording;
  }

  void record({
    required PlaybackStage stage,
    required PlaybackOutcome outcome,
    String? sourceId,
    String? extensionVersion,
    int? elapsedMs,
    int? nativeCode,
    int? httpStatus,
    String? privateError,
    PlaybackFailureFacts? facts,
    int? operation,
    int? recording,
    int? matchedRecording,
    String? method,
    Object? privateProviderFailures,
  }) {
    final source = sourceId == null || sourceId == 'navidrome'
        ? 'Navidrome'
        : musicSourceName(sourceId);
    _events.add({
      'event': ++_sequence,
      'time_utc': DateTime.now().toUtc().toIso8601String(),
      'source': source,
      'stage': stage.name,
      'outcome': outcome.name,
      if (operation != null && operation > 0) 'operation': operation,
      if (recording != null && recording > 0) 'recording': recording,
      if (matchedRecording != null && matchedRecording > 0)
        'matched_recording': matchedRecording,
      if (const {
        'customSearch',
        'getTrack',
        'getAlbum',
        'getPlaylist',
        'handleUrl',
        'checkAvailability',
        'hyperstreamResolve',
        'hyperstreamDownload',
      }.contains(method))
        'method': method!,
      if (extensionVersion != null &&
          RegExp(r'^\d{1,4}\.\d{1,4}\.\d{1,4}$').hasMatch(extensionVersion))
        'extension_version': extensionVersion,
      if (elapsedMs != null && elapsedMs >= 0) 'elapsed_ms': elapsedMs,
      'native_code': ?nativeCode,
      if (httpStatus != null && httpStatus >= 100 && httpStatus <= 599)
        'http_status': [httpStatus],
      if (facts != null)
        ...facts.toJson()
      else if (privateError != null)
        ...PlaybackFailureFacts.read(privateError).toJson(),
      if (privateProviderFailures is List && privateProviderFailures.isNotEmpty)
        'provider_failures': [
          for (final entry in privateProviderFailures.take(12).whereType<Map>())
            _providerFacts(entry),
        ],
    });
    if (_events.length > 80) _events.removeAt(0);
  }

  static Map<String, Object> _providerFacts(Map entry) {
    final code = entry['code'] is String
        ? (entry['code'] as String).toUpperCase()
        : '';
    return {
      if (entry['candidate'] is int &&
          entry['candidate'] >= 1 &&
          entry['candidate'] <= 12)
        'candidate': entry['candidate'] as int,
      if (const ['6', '7', '27'].contains(entry['quality']))
        'quality': entry['quality'] as String,
      if (const {
        'PROVIDER_UNAVAILABLE',
        'REQUEST_AUTH_INVALID',
        'SESSION_INVALID',
        'VERIFY_REQUIRED',
      }.contains(code))
        'code': code
      else if (code.isNotEmpty)
        'code': 'UNRECOGNIZED',
      if (const {
        'none',
        'same_operation',
        'new_ticket',
        'poll_existing',
      }.contains(entry['retry_mode']))
        'retry_mode': entry['retry_mode'] as String,
      ...PlaybackFailureFacts.read(
        [
          if (entry['message'] is String) entry['message'] as String,
          code,
        ].join(' '),
      ).toJson(),
    };
  }

  String report({String? appVersion, String? platform}) =>
      const JsonEncoder.withIndent('  ').convert({
        'report': 'Hyperstream playback diagnostics',
        'schema': 1,
        if (appVersion != null &&
            RegExp(r'^\d+\.\d+\.\d+$').hasMatch(appVersion))
          'app_version': appVersion,
        if (['ios', 'android', 'windows', 'macos', 'linux'].contains(platform))
          'platform': platform,
        'events': _events,
      });
}
