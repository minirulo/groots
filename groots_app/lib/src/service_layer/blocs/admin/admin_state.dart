import '../../../domain/models/album.dart';
import '../../../domain/models/track.dart';

enum AdminStatus { initial, loading, loaded, error, ingesting, ingested }

class AdminState {
  final AdminStatus status;
  final List<Track> centralLibrary;
  final List<Album> searchResults;
  final String? error;
  final String? ingestMessage;

  const AdminState({
    this.status = AdminStatus.initial,
    this.centralLibrary = const [],
    this.searchResults = const [],
    this.error,
    this.ingestMessage,
  });

  AdminState copyWith({
    AdminStatus? status,
    List<Track>? centralLibrary,
    List<Album>? searchResults,
    String? error,
    String? ingestMessage,
  }) =>
      AdminState(
        status: status ?? this.status,
        centralLibrary: centralLibrary ?? this.centralLibrary,
        searchResults: searchResults ?? this.searchResults,
        error: error ?? this.error,
        ingestMessage: ingestMessage ?? this.ingestMessage,
      );
}
