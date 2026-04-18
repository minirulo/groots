import '../../../domain/models/playlist.dart';

enum PlaylistStatus { initial, loading, loaded, error }

class PlaylistState {
  final PlaylistStatus status;
  final List<Playlist> playlists;
  final String? error;

  const PlaylistState({
    this.status = PlaylistStatus.initial,
    this.playlists = const [],
    this.error,
  });

  PlaylistState copyWith({
    PlaylistStatus? status,
    List<Playlist>? playlists,
    String? error,
  }) =>
      PlaylistState(
        status: status ?? this.status,
        playlists: playlists ?? this.playlists,
        error: error ?? this.error,
      );
}
