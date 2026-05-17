class Track {
  final String id;
  final String cid;
  final String title;
  final String? albumId;
  final int? trackNumber;
  final int durationSeconds;
  final int fileSizeBytes;
  final String mimeType;
  final bool pinned;
  final String? matchedCentralId;
  final String? source;
  final int? discNumber;
  final String? side;

  const Track({
    required this.id,
    required this.cid,
    required this.title,
    this.albumId,
    this.trackNumber,
    required this.durationSeconds,
    required this.fileSizeBytes,
    required this.mimeType,
    required this.pinned,
    this.matchedCentralId,
    this.source,
    this.discNumber,
    this.side,
  });

  factory Track.fromJson(Map<String, dynamic> json) => Track(
        id: json['id'] as String,
        cid: json['cid'] as String,
        title: json['title'] as String,
        albumId: json['album_id'] as String?,
        trackNumber: json['track_number'] as int?,
        durationSeconds: json['duration_seconds'] as int,
        fileSizeBytes: json['file_size_bytes'] as int,
        mimeType: json['mime_type'] as String,
        pinned: json['pinned'] as bool,
        matchedCentralId: json['matched_central_id'] as String?,
        source: json['source'] as String?,
        discNumber: json['disc_number'] as int?,
        side: json['side'] as String?,
      );

  String get durationFormatted {
    final m = durationSeconds ~/ 60;
    final s = durationSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
