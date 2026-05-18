const recordingFormats = ['CD', 'LP', 'EP', 'Single', 'Compilation', 'Digital', 'Cassette'];

class Album {
  final String id;
  final String title;
  final String artist;
  final int? year;
  final String? genre;
  final String? description;
  final String? coverCid;
  final String? recordingFormat;
  final String? userId;

  const Album({
    required this.id,
    required this.title,
    required this.artist,
    this.year,
    this.genre,
    this.description,
    this.coverCid,
    this.recordingFormat,
    this.userId,
  });

  factory Album.fromJson(Map<String, dynamic> json) => Album(
        id: json['id'] as String,
        title: json['title'] as String,
        artist: json['artist'] as String,
        year: json['year'] as int?,
        genre: json['genre'] as String?,
        description: json['description'] as String?,
        coverCid: json['cover_cid'] as String?,
        recordingFormat: json['recording_format'] as String?,
        userId: json['user_id'] as String?,
      );
}
