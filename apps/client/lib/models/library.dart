class Artist {
  const Artist({
    required this.id,
    required this.name,
    this.coverArt,
    this.albumCount = 0,
  });
  factory Artist.fromJson(Map<String, dynamic> json) => Artist(
    id: json['id'] as String,
    name: json['name'] as String? ?? 'Unknown artist',
    coverArt: json['coverArt'] as String?,
    albumCount: (json['albumCount'] as num?)?.toInt() ?? 0,
  );
  final String id;
  final String name;
  final String? coverArt;
  final int albumCount;
}

class Album {
  const Album({
    required this.id,
    required this.name,
    required this.artist,
    this.coverArt,
    this.songCount = 0,
    this.starred = false,
  });

  factory Album.fromJson(Map<String, dynamic> json) => Album(
    id: json['id'] as String,
    name: json['name'] as String? ?? 'Untitled album',
    artist: json['artist'] as String? ?? 'Unknown artist',
    coverArt: json['coverArt'] as String?,
    songCount: (json['songCount'] as num?)?.toInt() ?? 0,
    starred: json['starred'] != null,
  );

  final String id;
  final String name;
  final String artist;
  final String? coverArt;
  final int songCount;
  final bool starred;
}

class Track {
  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    this.number,
    this.coverArt,
    this.starred = false,
    this.addedAt,
    this.lastPlayedAt,
    this.playCount = 0,
    this.invalidActivityDates = false,
  });

  factory Track.fromJson(Map<String, dynamic> json) => Track(
    id: json['id'] as String,
    title: json['title'] as String? ?? 'Untitled track',
    artist: json['artist'] as String? ?? 'Unknown artist',
    album: json['album'] as String? ?? 'Unknown album',
    duration: Duration(seconds: (json['duration'] as num?)?.toInt() ?? 0),
    number: (json['track'] as num?)?.toInt(),
    coverArt: json['coverArt'] as String?,
    starred: json['starred'] != null,
    addedAt: activityDate(json['created']),
    lastPlayedAt: activityDate(json['played']),
    playCount: (json['playCount'] as num?)?.toInt() ?? 0,
    invalidActivityDates: [
      'created',
      'played',
    ].any((key) => json[key] != null && activityDate(json[key]) == null),
  );

  final String id;
  final String title;
  final String artist;
  final String album;
  final Duration duration;
  final int? number;
  final String? coverArt;
  final bool starred;
  final DateTime? addedAt;
  final DateTime? lastPlayedAt;
  final int playCount;
  final bool invalidActivityDates;
}

/// Activity dates must specify a timezone; never interpret server time as local.
DateTime? activityDate(Object? value) {
  if (value is! String) return null;
  final parts = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d+)?(?:Z|[+-](\d{2}):(\d{2}))$',
  ).firstMatch(value);
  if (parts == null) return null;
  final year = int.parse(parts[1]!);
  final month = int.parse(parts[2]!);
  final day = int.parse(parts[3]!);
  if (month < 1 ||
      month > 12 ||
      day < 1 ||
      day > DateTime.utc(year, month + 1, 0).day ||
      int.parse(parts[4]!) > 23 ||
      int.parse(parts[5]!) > 59 ||
      int.parse(parts[6]!) > 59 ||
      (parts[7] != null && int.parse(parts[7]!) > 23) ||
      (parts[8] != null && int.parse(parts[8]!) > 59)) {
    return null;
  }
  return DateTime.tryParse(value)?.toUtc();
}

class MusicPlaylist {
  const MusicPlaylist({
    required this.id,
    required this.name,
    required this.owner,
    this.songCount = 0,
    this.coverArt,
    this.tracks = const [],
  });

  factory MusicPlaylist.fromJson(Map<String, dynamic> json) => MusicPlaylist(
    id: json['id'] as String,
    name: json['name'] as String? ?? 'Untitled playlist',
    owner: json['owner'] as String? ?? '',
    songCount: (json['songCount'] as num?)?.toInt() ?? 0,
    coverArt: json['coverArt'] as String?,
    tracks: (json['entry'] as List<dynamic>? ?? [])
        .map((entry) => Track.fromJson(entry as Map<String, dynamic>))
        .toList(),
  );

  final String id;
  final String name;
  final String owner;
  final int songCount;
  final String? coverArt;
  final List<Track> tracks;
}

class LibrarySearchResults {
  const LibrarySearchResults({
    this.albums = const [],
    this.tracks = const [],
    this.artists = const [],
  });

  final List<Album> albums;
  final List<Track> tracks;
  final List<Artist> artists;
}
