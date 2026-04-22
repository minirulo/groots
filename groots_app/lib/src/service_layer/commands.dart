abstract class Command {}

class LoginCommand extends Command {
  final String email;
  final String password;
  LoginCommand({required this.email, required this.password});
}

class RegisterCommand extends Command {
  final String username;
  final String email;
  final String password;
  RegisterCommand({required this.username, required this.email, required this.password});
}

class LogoutCommand extends Command {}

class LoadLibraryCommand extends Command {}

class AddTrackCommand extends Command {
  final Map<String, dynamic> payload;
  AddTrackCommand(this.payload);
}

class RemoveTrackCommand extends Command {
  final String trackId;
  RemoveTrackCommand(this.trackId);
}

class PinTrackCommand extends Command {
  final String trackId;
  PinTrackCommand(this.trackId);
}

// ── Album commands ─────────────────────────────────────────────────────────

class LoadAlbumsCommand extends Command {}

class LoadGenresCommand extends Command {}

class CreateAlbumCommand extends Command {
  final String title;
  final String artist;
  final int? year;
  final String? genre;
  final String? description;
  final String? recordingFormat;
  CreateAlbumCommand({
    required this.title,
    required this.artist,
    this.year,
    this.genre,
    this.description,
    this.recordingFormat,
  });
}

class UpdateAlbumCommand extends Command {
  final String albumId;
  final String? title;
  final String? artist;
  final int? year;
  final String? genre;
  final String? description;
  final String? recordingFormat;
  UpdateAlbumCommand({
    required this.albumId,
    this.title,
    this.artist,
    this.year,
    this.genre,
    this.description,
    this.recordingFormat,
  });
}

class DeleteAlbumCommand extends Command {
  final String albumId;
  DeleteAlbumCommand(this.albumId);
}

class AssignTrackToAlbumCommand extends Command {
  final String albumId;
  final String trackId;
  final int? trackNumber;
  AssignTrackToAlbumCommand({
    required this.albumId,
    required this.trackId,
    this.trackNumber,
  });
}

class UnassignTrackFromAlbumCommand extends Command {
  final String albumId;
  final String trackId;
  UnassignTrackFromAlbumCommand({required this.albumId, required this.trackId});
}

// ── Playlist commands ──────────────────────────────────────────────────────

class LoadPlaylistsCommand extends Command {}

class CreatePlaylistCommand extends Command {
  final String name;
  CreatePlaylistCommand(this.name);
}

class RenamePlaylistCommand extends Command {
  final String playlistId;
  final String name;
  RenamePlaylistCommand({required this.playlistId, required this.name});
}

class DeletePlaylistCommand extends Command {
  final String playlistId;
  DeletePlaylistCommand(this.playlistId);
}

class AddTrackToPlaylistCommand extends Command {
  final String playlistId;
  final String trackId;
  AddTrackToPlaylistCommand({required this.playlistId, required this.trackId});
}

class RemoveTrackFromPlaylistCommand extends Command {
  final String playlistId;
  final String trackId;
  RemoveTrackFromPlaylistCommand({required this.playlistId, required this.trackId});
}

// ── Admin commands ─────────────────────────────────────────────────────────

class LoadCentralLibraryCommand extends Command {}

class IngestCentralTrackCommand extends Command {
  final String filename;
  final List<int> content;
  final int fileSizeBytes;
  final String mimeType;
  IngestCentralTrackCommand({
    required this.filename,
    required this.content,
    required this.fileSizeBytes,
    required this.mimeType,
  });
}

class SearchAlbumsCommand extends Command {
  final String query;
  SearchAlbumsCommand(this.query);
}
