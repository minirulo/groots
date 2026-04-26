import '../../../domain/models/album.dart';

enum AlbumStatus { initial, loading, loaded, error }

class AlbumState {
  final AlbumStatus status;
  final List<Album> albums;
  final String? error;

  const AlbumState({
    this.status = AlbumStatus.initial,
    this.albums = const [],
    this.error,
  });

  AlbumState copyWith({AlbumStatus? status, List<Album>? albums, String? error}) =>
      AlbumState(
        status: status ?? this.status,
        albums: albums ?? this.albums,
        error: error ?? this.error,
      );
}
