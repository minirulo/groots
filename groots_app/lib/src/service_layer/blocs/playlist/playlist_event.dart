abstract class PlaylistEvent {}

class PlaylistLoadRequested extends PlaylistEvent {}

class PlaylistCreateRequested extends PlaylistEvent {
  final String name;
  PlaylistCreateRequested(this.name);
}

class PlaylistRenameRequested extends PlaylistEvent {
  final String playlistId;
  final String name;
  PlaylistRenameRequested({required this.playlistId, required this.name});
}

class PlaylistDeleteRequested extends PlaylistEvent {
  final String playlistId;
  PlaylistDeleteRequested(this.playlistId);
}

class PlaylistAddTrackRequested extends PlaylistEvent {
  final String playlistId;
  final String trackId;
  PlaylistAddTrackRequested({required this.playlistId, required this.trackId});
}

class PlaylistRemoveTrackRequested extends PlaylistEvent {
  final String playlistId;
  final String trackId;
  PlaylistRemoveTrackRequested({required this.playlistId, required this.trackId});
}
