import '../../adapters/providers/admin_provider.dart';
import '../../adapters/providers/album_provider.dart';
import '../../domain/models/album.dart';
import '../../domain/models/track.dart';
import '../commands.dart';

class AdminHandler {
  final AdminProvider _adminProvider;
  final AlbumProvider _albumProvider;

  AdminHandler({
    required AdminProvider adminProvider,
    required AlbumProvider albumProvider,
  })  : _adminProvider = adminProvider,
        _albumProvider = albumProvider;

  Future<List<Track>> loadCentralLibrary() => _adminProvider.getCentralLibrary();

  Future<Map<String, dynamic>> ingestTrack(IngestCentralTrackCommand cmd) =>
      _adminProvider.ingestTrack(
        filename: cmd.filename,
        content: cmd.content,
        mimeType: cmd.mimeType,
      );

  Future<List<Album>> searchAlbums(SearchAlbumsCommand cmd) =>
      _adminProvider.searchAlbums(cmd.query);

  Future<String> createAlbum(CreateAlbumCommand cmd) =>
      _albumProvider.createAlbum({
        'title': cmd.title,
        'artist': cmd.artist,
        if (cmd.year != null) 'year': cmd.year,
        if (cmd.genre != null) 'genre': cmd.genre,
        if (cmd.description != null) 'description': cmd.description,
      });

  Future<void> deleteAlbum(DeleteAlbumCommand cmd) =>
      _albumProvider.deleteAlbum(cmd.albumId);
}
