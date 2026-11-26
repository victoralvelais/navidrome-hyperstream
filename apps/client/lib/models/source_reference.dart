/// Stable catalog identity. Playback URLs and credentials are resolved at use.
class SourceReference {
  const SourceReference({
    required this.sourceId,
    required this.trackId,
    this.albumId,
    this.artwork,
    this.isrc,
    this.disc = 1,
    this.available = true,
  });

  final String sourceId;
  final String trackId;
  final String? albumId;
  final Uri? artwork;
  final String? isrc;
  final int disc;
  final bool available;

  String get identity => '$sourceId/$trackId';

  Map<String, Object?> toJson() => {
    'sourceId': sourceId,
    'trackId': trackId,
    'albumId': albumId,
    'artwork': artwork?.toString(),
    'isrc': isrc,
    'disc': disc,
    'available': available,
  };

  factory SourceReference.fromJson(Map<String, dynamic> data) {
    final source = data['sourceId'] as String;
    final track = data['trackId'] as String;
    if (source.isEmpty || track.isEmpty) throw const FormatException();
    return SourceReference(
      sourceId: source,
      trackId: track,
      albumId: data['albumId'] as String?,
      artwork: publicArtwork(data['artwork']),
      isrc: data['isrc'] as String?,
      disc: (data['disc'] as int?) ?? 1,
      available: data['available'] as bool? ?? true,
    );
  }
}

String musicSourceName(String id) => switch (id) {
  'navidrome' => 'Navidrome',
  'mornye:spotify-web' => 'Spotify',
  'mornye:ytmusic-spotiflac' => 'YouTube',
  'mornye:soundcloud' => 'SoundCloud',
  'mornye:qobuz-web' => 'Qobuz',
  'mornye:tidal-web' => 'Tidal',
  _ when id.startsWith('monochrome-') => 'Monochrome',
  _ => 'Online',
};

/// Public media facts only. Resolved URLs and authorization never reach the UI.
class SourcePlaybackInfo {
  const SourcePlaybackInfo({
    required this.sourceId,
    this.format,
    this.codec,
    this.bitRate,
    this.bitRateEstimated = false,
  });
  final String sourceId;
  final String? format;
  final String? codec;
  final int? bitRate;
  final bool bitRateEstimated;

  String get label => [
    musicSourceName(sourceId),
    if (format != null &&
        const [
          'flac',
          'mp3',
          'm4a',
          'mp4',
          'aac',
          'opus',
          'ogg',
          'wav',
          'caf',
        ].contains(format!.toLowerCase()))
      format!.toUpperCase(),
    if (codec != null &&
        ['aac', 'alac', 'opus', 'vorbis'].contains(codec) &&
        codec != format?.toLowerCase())
      codec!.toUpperCase(),
    if (bitRate != null && bitRate! > 0 && bitRate! <= 10000)
      '${bitRateEstimated ? '≈' : ''}$bitRate kbps',
  ].join(' · ');
}

Uri? publicArtwork(Object? value) {
  final uri = value is String ? Uri.tryParse(value) : null;
  return uri != null &&
          uri.scheme == 'https' &&
          uri.host.isNotEmpty &&
          uri.userInfo.isEmpty &&
          !uri.hasQuery &&
          !uri.hasFragment
      ? uri
      : null;
}
