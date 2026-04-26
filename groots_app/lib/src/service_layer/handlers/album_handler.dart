import '../../adapters/providers/album_provider.dart';
import '../../domain/models/album.dart';
import '../commands.dart';

class AlbumHandler {
  final AlbumProvider _provider;

  AlbumHandler({required AlbumProvider provider}) : _provider = provider;

  Future<List<Album>> loadAlbums() => _provider.getAlbums();

  Future<String> createAlbum(CreateAlbumCommand cmd) => _provider.createAlbum({
        'title': cmd.title,
        'artist': cmd.artist,
        if (cmd.year != null) 'year': cmd.year,
        if (cmd.genre != null) 'genre': cmd.genre,
        if (cmd.description != null) 'description': cmd.description,
        if (cmd.recordingFormat != null) 'recording_format': cmd.recordingFormat,
      });

  Future<void> updateAlbum(UpdateAlbumCommand cmd) => _provider.updateAlbum(
        cmd.albumId,
        {
          if (cmd.title != null) 'title': cmd.title,
          if (cmd.artist != null) 'artist': cmd.artist,
          if (cmd.year != null) 'year': cmd.year,
          if (cmd.genre != null) 'genre': cmd.genre,
          if (cmd.description != null) 'description': cmd.description,
        },
      );

  Future<void> deleteAlbum(DeleteAlbumCommand cmd) =>
      _provider.deleteAlbum(cmd.albumId);

  Future<void> assignTrack(AssignTrackToAlbumCommand cmd) =>
      _provider.assignTrack(cmd.albumId, cmd.trackId, trackNumber: cmd.trackNumber);

  Future<void> unassignTrack(UnassignTrackFromAlbumCommand cmd) =>
      _provider.unassignTrack(cmd.albumId, cmd.trackId);
}
