class DiscogsTrack {
  final String position;
  final String title;
  final String duration;
  final int? durationSeconds;
  final String? side;

  const DiscogsTrack({
    required this.position,
    required this.title,
    required this.duration,
    this.durationSeconds,
    this.side,
  });

  factory DiscogsTrack.fromJson(Map<String, dynamic> json) => DiscogsTrack(
        position: json['position'] as String? ?? '',
        title: json['title'] as String? ?? '',
        duration: json['duration'] as String? ?? '',
        durationSeconds: json['duration_seconds'] as int?,
        side: json['side'] as String?,
      );
}

class DiscogsReleaseSummary {
  final int id;
  final String title;
  final String artist;
  final int? year;
  final String? label;
  final String? catalogNumber;
  final String? format;
  final String? thumbUrl;

  const DiscogsReleaseSummary({
    required this.id,
    required this.title,
    required this.artist,
    this.year,
    this.label,
    this.catalogNumber,
    this.format,
    this.thumbUrl,
  });

  factory DiscogsReleaseSummary.fromJson(Map<String, dynamic> json) =>
      DiscogsReleaseSummary(
        id: json['id'] as int,
        title: json['title'] as String? ?? '',
        artist: json['artist'] as String? ?? '',
        year: json['year'] as int?,
        label: json['label'] as String?,
        catalogNumber: json['catalog_number'] as String?,
        format: json['format'] as String?,
        thumbUrl: json['thumb_url'] as String?,
      );
}

class DiscogsRelease {
  final int id;
  final String title;
  final String artist;
  final int? year;
  final String? label;
  final String? catalogNumber;
  final String? format;
  final String? coverUrl;
  final List<String> genres;
  final List<String> styles;
  final List<DiscogsTrack> tracklist;
  final Map<String, List<DiscogsTrack>> sides;

  const DiscogsRelease({
    required this.id,
    required this.title,
    required this.artist,
    this.year,
    this.label,
    this.catalogNumber,
    this.format,
    this.coverUrl,
    required this.genres,
    required this.styles,
    required this.tracklist,
    required this.sides,
  });

  factory DiscogsRelease.fromJson(Map<String, dynamic> json) {
    final rawSides = json['sides'] as Map<String, dynamic>? ?? {};
    return DiscogsRelease(
      id: json['id'] as int,
      title: json['title'] as String? ?? '',
      artist: json['artist'] as String? ?? '',
      year: json['year'] as int?,
      label: json['label'] as String?,
      catalogNumber: json['catalog_number'] as String?,
      format: json['format'] as String?,
      coverUrl: json['cover_url'] as String?,
      genres: (json['genres'] as List?)?.cast<String>() ?? [],
      styles: (json['styles'] as List?)?.cast<String>() ?? [],
      tracklist: (json['tracklist'] as List?)
              ?.map((t) => DiscogsTrack.fromJson(t as Map<String, dynamic>))
              .toList() ??
          [],
      sides: rawSides.map(
        (k, v) => MapEntry(
          k,
          (v as List)
              .map((t) => DiscogsTrack.fromJson(t as Map<String, dynamic>))
              .toList(),
        ),
      ),
    );
  }

  List<String> get availableSides => sides.keys.toList()..sort();
}
