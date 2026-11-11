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
  );

  final String id;
  final String title;
  final String artist;
  final String album;
  final Duration duration;
  final int? number;
  final String? coverArt;
  final bool starred;
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
  const LibrarySearchResults({this.albums = const [], this.tracks = const []});

  final List<Album> albums;
  final List<Track> tracks;
}
