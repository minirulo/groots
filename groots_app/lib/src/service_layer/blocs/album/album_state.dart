import '../../../domain/models/album.dart';

enum AlbumStatus { initial, loading, loaded, error }

class AlbumState {
  final AlbumStatus status;
  final List<Album> albums;
  final List<String> genres;
  final String? error;

  const AlbumState({
    this.status = AlbumStatus.initial,
    this.albums = const [],
    this.genres = const [],
    this.error,
  });

  AlbumState copyWith({
    AlbumStatus? status,
    List<Album>? albums,
    List<String>? genres,
    String? error,
  }) => AlbumState(
    status: status ?? this.status,
    albums: albums ?? this.albums,
    genres: genres ?? this.genres,
    error: error ?? this.error,
  );
}
