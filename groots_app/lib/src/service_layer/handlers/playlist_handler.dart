import '../../adapters/providers/playlist_provider.dart';
import '../../domain/models/playlist.dart';
import '../commands.dart';

class PlaylistHandler {
  final PlaylistProvider _provider;

  PlaylistHandler({required PlaylistProvider provider}) : _provider = provider;

  Future<List<Playlist>> loadPlaylists() => _provider.getPlaylists();

  Future<String> createPlaylist(CreatePlaylistCommand cmd) =>
      _provider.createPlaylist(cmd.name);

  Future<void> renamePlaylist(RenamePlaylistCommand cmd) =>
      _provider.renamePlaylist(cmd.playlistId, cmd.name);

  Future<void> deletePlaylist(DeletePlaylistCommand cmd) =>
      _provider.deletePlaylist(cmd.playlistId);

  Future<void> addTrack(AddTrackToPlaylistCommand cmd) =>
      _provider.addTrack(cmd.playlistId, cmd.trackId);

  Future<void> removeTrack(RemoveTrackFromPlaylistCommand cmd) =>
      _provider.removeTrack(cmd.playlistId, cmd.trackId);
}
