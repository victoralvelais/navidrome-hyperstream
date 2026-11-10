class Album {
  const Album({
    required this.id,
    required this.name,
    required this.artist,
    this.coverArt,
    this.songCount = 0,
  });

  factory Album.fromJson(Map<String, dynamic> json) => Album(
    id: json['id'] as String,
    name: json['name'] as String? ?? 'Untitled album',
    artist: json['artist'] as String? ?? 'Unknown artist',
    coverArt: json['coverArt'] as String?,
    songCount: (json['songCount'] as num?)?.toInt() ?? 0,
  );

  final String id;
  final String name;
  final String artist;
  final String? coverArt;
  final int songCount;
}

class Track {
  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    this.number,
  });

  factory Track.fromJson(Map<String, dynamic> json) => Track(
    id: json['id'] as String,
    title: json['title'] as String? ?? 'Untitled track',
    artist: json['artist'] as String? ?? 'Unknown artist',
    album: json['album'] as String? ?? 'Unknown album',
    duration: Duration(seconds: (json['duration'] as num?)?.toInt() ?? 0),
    number: (json['track'] as num?)?.toInt(),
  );

  final String id;
  final String title;
  final String artist;
  final String album;
  final Duration duration;
  final int? number;
}
