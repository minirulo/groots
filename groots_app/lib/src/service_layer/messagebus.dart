import 'commands.dart';
import 'handlers/admin_handler.dart';
import 'handlers/album_handler.dart';
import 'handlers/auth_handler.dart';
import 'handlers/library_handler.dart';
import 'handlers/playlist_handler.dart';

class Messagebus {
  final AuthHandler _authHandler;
  final LibraryHandler _libraryHandler;
  final AlbumHandler _albumHandler;
  final PlaylistHandler _playlistHandler;
  final AdminHandler _adminHandler;

  Messagebus({
    required AuthHandler authHandler,
    required LibraryHandler libraryHandler,
    required AlbumHandler albumHandler,
    required PlaylistHandler playlistHandler,
    required AdminHandler adminHandler,
  })  : _authHandler = authHandler,
        _libraryHandler = libraryHandler,
        _albumHandler = albumHandler,
        _playlistHandler = playlistHandler,
        _adminHandler = adminHandler;

  Future<T> handle<T>(Command command) async {
    return switch (command) {
      LoginCommand() => await _authHandler.login(command) as T,
      RegisterCommand() => await _authHandler.register(command) as T,
      LogoutCommand() => await _authHandler.logout() as T,
      LoadLibraryCommand() => await _libraryHandler.loadLibrary() as T,
      AddTrackCommand() => await _libraryHandler.addTrack(command) as T,
      RemoveTrackCommand() => await _libraryHandler.removeTrack(command) as T,
      PinTrackCommand() => await _libraryHandler.pinTrack(command) as T,
      LoadAlbumsCommand() => await _albumHandler.loadAlbums() as T,
      LoadGenresCommand() => await _albumHandler.loadGenres() as T,
      CreateAlbumCommand() => await _albumHandler.createAlbum(command) as T,
      UpdateAlbumCommand() => await _albumHandler.updateAlbum(command) as T,
      DeleteAlbumCommand() => await _albumHandler.deleteAlbum(command) as T,
      AssignTrackToAlbumCommand() => await _albumHandler.assignTrack(command) as T,
      UnassignTrackFromAlbumCommand() => await _albumHandler.unassignTrack(command) as T,
      LoadPlaylistsCommand() => await _playlistHandler.loadPlaylists() as T,
      CreatePlaylistCommand() => await _playlistHandler.createPlaylist(command) as T,
      RenamePlaylistCommand() => await _playlistHandler.renamePlaylist(command) as T,
      DeletePlaylistCommand() => await _playlistHandler.deletePlaylist(command) as T,
      AddTrackToPlaylistCommand() => await _playlistHandler.addTrack(command) as T,
      RemoveTrackFromPlaylistCommand() => await _playlistHandler.removeTrack(command) as T,
      LoadCentralLibraryCommand() => await _adminHandler.loadCentralLibrary() as T,
      IngestCentralTrackCommand() => await _adminHandler.ingestTrack(command) as T,
      SearchAlbumsCommand() => await _adminHandler.searchAlbums(command) as T,
      _ => throw UnimplementedError('No handler for ${command.runtimeType}'),
    };
  }
}
