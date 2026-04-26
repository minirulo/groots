abstract class AdminEvent {}

class AdminCentralLibraryLoadRequested extends AdminEvent {}

class AdminTrackIngestRequested extends AdminEvent {
  final String filename;
  final List<int> content;
  final int fileSizeBytes;
  final String mimeType;
  AdminTrackIngestRequested({
    required this.filename,
    required this.content,
    required this.fileSizeBytes,
    required this.mimeType,
  });
}

class AdminAlbumSearchRequested extends AdminEvent {
  final String query;
  AdminAlbumSearchRequested(this.query);
}

class AdminAlbumCreateRequested extends AdminEvent {
  final String title;
  final String artist;
  final int? year;
  final String? genre;
  final String? description;
  AdminAlbumCreateRequested({
    required this.title,
    required this.artist,
    this.year,
    this.genre,
    this.description,
  });
}

class AdminAlbumDeleteRequested extends AdminEvent {
  final String albumId;
  AdminAlbumDeleteRequested(this.albumId);
}
