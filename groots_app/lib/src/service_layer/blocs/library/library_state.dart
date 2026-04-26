import '../../../domain/models/track.dart';

enum LibraryStatus { initial, loading, loaded, error }

class LibraryState {
  final LibraryStatus status;
  final List<Track> tracks;
  final String? error;

  const LibraryState({
    this.status = LibraryStatus.initial,
    this.tracks = const [],
    this.error,
  });

  LibraryState copyWith({LibraryStatus? status, List<Track>? tracks, String? error}) =>
      LibraryState(
        status: status ?? this.status,
        tracks: tracks ?? this.tracks,
        error: error ?? this.error,
      );
}
