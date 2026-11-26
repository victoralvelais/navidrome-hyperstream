import 'dart:convert';

import '../models/source_reference.dart';

enum PlaybackStage {
  player,
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
}

/// A small, session-only diagnostic timeline. Nothing is uploaded or persisted.
/// Track titles/IDs, account/server details, URLs, paths and raw errors are absent.
class PlaybackDiagnostics {
  static final instance = PlaybackDiagnostics();
  final _events = <Map<String, Object>>[];
  int _sequence = 0;

  void record({
    required PlaybackStage stage,
    required PlaybackOutcome outcome,
    String? sourceId,
    String? extensionVersion,
    int? elapsedMs,
    int? nativeCode,
    int? httpStatus,
    String? privateError,
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
      if (extensionVersion != null &&
          RegExp(r'^\d{1,4}\.\d{1,4}\.\d{1,4}$').hasMatch(extensionVersion))
        'extension_version': extensionVersion,
      if (elapsedMs != null && elapsedMs >= 0) 'elapsed_ms': elapsedMs,
      'native_code': ?nativeCode,
      if (httpStatus != null && httpStatus >= 100 && httpStatus <= 599)
        'http_status': [httpStatus],
      if (privateError != null)
        ...PlaybackFailureFacts.read(privateError).toJson(),
    });
    if (_events.length > 80) _events.removeAt(0);
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
