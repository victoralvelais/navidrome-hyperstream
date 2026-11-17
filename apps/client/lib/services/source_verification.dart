import 'music_provider.dart';

/// A callback is useful only alongside a still-pending native challenge.
/// Never persist or log these short-lived values.
class SourceVerification {
  SourceVerification(Map pending)
    : auth = Uri.parse(pending['auth_url'] as String),
      callback = Uri.parse(pending['callback_url'] as String) {
    if (auth.scheme != 'https' ||
        auth.host.isEmpty ||
        auth.userInfo.isNotEmpty ||
        !isCallback(callback) ||
        state.isEmpty) {
      throw const SourceException(
        'This provider returned an invalid verification page.',
      );
    }
  }

  final Uri auth, callback;
  String get state => callback.queryParameters['state'] ?? '';

  static bool isCallback(Uri uri) =>
      const ['mornye', 'hyperstream'].contains(uri.scheme) &&
      uri.host == 'session-grant' &&
      uri.userInfo.isEmpty &&
      !uri.hasPort &&
      (uri.path.isEmpty || uri.path == '/');

  String grant(String input, {required bool manual}) {
    const invalid = SourceException(
      'Paste the verification link or code copied from the verification page.',
    );
    final text = input.trim();
    if (text.isEmpty || text.length > 8192) throw invalid;
    try {
      final uri = Uri.parse(text);
      final Map<String, List<String>> fields;
      if (uri.hasScheme) {
        if (!isCallback(uri)) throw invalid;
        fields = uri.queryParametersAll;
      } else if (manual) {
        final query = text.startsWith('?') ? text.substring(1) : text;
        fields = Uri.parse('?$query').queryParametersAll;
      } else {
        throw invalid;
      }
      // Only the gateway's bare field fallback may omit state. A full callback
      // must identify its own attempt, including when pasted manually.
      return _grant(fields, manual: manual && !uri.hasScheme);
    } on FormatException {
      throw invalid;
    }
  }

  String _grant(Map<String, List<String>> fields, {required bool manual}) {
    if (fields.values.any((values) => values.length != 1) ||
        (fields.containsKey('grant') && fields.containsKey('code'))) {
      throw const SourceException(
        'This verification link is invalid. Copy it again.',
      );
    }
    final receivedState = fields['state']?.single;
    if ((!manual && receivedState == null) ||
        (receivedState != null && receivedState != state)) {
      throw const SourceException(
        'This code belongs to a different verification attempt. Open Verify again for this source.',
      );
    }
    final value = fields['grant']?.single ?? fields['code']?.single;
    if (value == null ||
        value.isEmpty ||
        RegExp(r'[\s\x00-\x1f\x7f]').hasMatch(value)) {
      throw const SourceException(
        'Paste the verification link or code copied from the verification page.',
      );
    }
    return value;
  }
}
