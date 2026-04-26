class Track {
  final String id;
  final String cid;
  final String title;
  final String artist;
  final String? album;
  final String? albumId;
  final int? trackNumber;
  final int? year;
  final String? genre;
  final int durationSeconds;
  final int fileSizeBytes;
  final String mimeType;
  final bool pinned;
  final String? matchedCentralId;

  const Track({
    required this.id,
    required this.cid,
    required this.title,
    required this.artist,
    this.album,
    this.albumId,
    this.trackNumber,
    this.year,
    this.genre,
    required this.durationSeconds,
    required this.fileSizeBytes,
    required this.mimeType,
    required this.pinned,
    this.matchedCentralId,
  });

  factory Track.fromJson(Map<String, dynamic> json) => Track(
        id: json['id'] as String,
        cid: json['cid'] as String,
        title: json['title'] as String,
        artist: json['artist'] as String,
        album: json['album'] as String?,
        albumId: json['album_id'] as String?,
        trackNumber: json['track_number'] as int?,
        year: json['year'] as int?,
        genre: json['genre'] as String?,
        durationSeconds: json['duration_seconds'] as int,
        fileSizeBytes: json['file_size_bytes'] as int,
        mimeType: json['mime_type'] as String,
        pinned: json['pinned'] as bool,
        matchedCentralId: json['matched_central_id'] as String?,
      );

  String get durationFormatted {
    final m = durationSeconds ~/ 60;
    final s = durationSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
