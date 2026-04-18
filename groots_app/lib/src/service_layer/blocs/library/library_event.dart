abstract class LibraryEvent {}

class LibraryLoadRequested extends LibraryEvent {}

class LibraryTrackRemoveRequested extends LibraryEvent {
  final String trackId;
  LibraryTrackRemoveRequested(this.trackId);
}

class LibraryTrackPinRequested extends LibraryEvent {
  final String trackId;
  LibraryTrackPinRequested(this.trackId);
}
