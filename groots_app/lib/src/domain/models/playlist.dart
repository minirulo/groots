class Playlist {
  final String id;
  final String name;
  final List<String> trackIds;

  const Playlist({
    required this.id,
    required this.name,
    required this.trackIds,
  });

  factory Playlist.fromJson(Map<String, dynamic> json) => Playlist(
        id: json['id'] as String,
        name: json['name'] as String,
        trackIds: (json['track_ids'] as List).cast<String>(),
      );
}
