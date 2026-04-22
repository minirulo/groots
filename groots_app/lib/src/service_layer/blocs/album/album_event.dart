abstract class AlbumEvent {}

class AlbumLoadRequested extends AlbumEvent {}

class AlbumCreateRequested extends AlbumEvent {
  final String title;
  final String artist;
  final int? year;
  final String? genre;
  final String? description;
  final String? recordingFormat;
  AlbumCreateRequested({
    required this.title,
    required this.artist,
    this.year,
    this.genre,
    this.description,
    this.recordingFormat,
  });
}

class AlbumUpdateRequested extends AlbumEvent {
  final String albumId;
  final String title;
  final String artist;
  final int? year;
  final String? genre;
  final String? recordingFormat;
  AlbumUpdateRequested({
    required this.albumId,
    required this.title,
    required this.artist,
    this.year,
    this.genre,
    this.recordingFormat,
  });
}

class AlbumDeleteRequested extends AlbumEvent {
  final String albumId;
  AlbumDeleteRequested(this.albumId);
}

class AlbumTrackAssignRequested extends AlbumEvent {
  final String albumId;
  final String trackId;
  final int? trackNumber;
  AlbumTrackAssignRequested({
    required this.albumId,
    required this.trackId,
    this.trackNumber,
  });
}

class AlbumTrackUnassignRequested extends AlbumEvent {
  final String albumId;
  final String trackId;
  AlbumTrackUnassignRequested({required this.albumId, required this.trackId});
}
