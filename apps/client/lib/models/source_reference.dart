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
