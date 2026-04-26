import 'package:flutter_bloc/flutter_bloc.dart';

import '../../commands.dart';
import '../../messagebus.dart';
import 'admin_event.dart';
import 'admin_state.dart';

class AdminBloc extends Bloc<AdminEvent, AdminState> {
  final Messagebus _bus;

  AdminBloc({required Messagebus bus})
      : _bus = bus,
        super(const AdminState()) {
    on<AdminCentralLibraryLoadRequested>(_onLoadLibrary);
    on<AdminTrackIngestRequested>(_onIngest);
    on<AdminAlbumSearchRequested>(_onSearchAlbums);
    on<AdminAlbumCreateRequested>(_onCreateAlbum);
    on<AdminAlbumDeleteRequested>(_onDeleteAlbum);
  }

  Future<void> _onLoadLibrary(
    AdminCentralLibraryLoadRequested event,
    Emitter<AdminState> emit,
  ) async {
    emit(state.copyWith(status: AdminStatus.loading));
    try {
      final tracks = await _bus.handle(LoadCentralLibraryCommand());
      emit(state.copyWith(status: AdminStatus.loaded, centralLibrary: tracks));
    } catch (e) {
      emit(state.copyWith(status: AdminStatus.error, error: e.toString()));
    }
  }

  Future<void> _onIngest(
    AdminTrackIngestRequested event,
    Emitter<AdminState> emit,
  ) async {
    emit(state.copyWith(status: AdminStatus.ingesting));
    try {
      final result = await _bus.handle(IngestCentralTrackCommand(
        filename: event.filename,
        content: event.content,
        fileSizeBytes: event.fileSizeBytes,
        mimeType: event.mimeType,
      ));
      final msg = 'Ingested track ${result['track_id']}';
      emit(state.copyWith(status: AdminStatus.ingested, ingestMessage: msg));
      add(AdminCentralLibraryLoadRequested());
    } catch (e) {
      emit(state.copyWith(status: AdminStatus.error, error: e.toString()));
    }
  }

  Future<void> _onSearchAlbums(
    AdminAlbumSearchRequested event,
    Emitter<AdminState> emit,
  ) async {
    try {
      final albums = await _bus.handle(SearchAlbumsCommand(event.query));
      emit(state.copyWith(searchResults: albums));
    } catch (e) {
      emit(state.copyWith(status: AdminStatus.error, error: e.toString()));
    }
  }

  Future<void> _onCreateAlbum(
    AdminAlbumCreateRequested event,
    Emitter<AdminState> emit,
  ) async {
    try {
      await _bus.handle(CreateAlbumCommand(
        title: event.title,
        artist: event.artist,
        year: event.year,
        genre: event.genre,
        description: event.description,
      ));
    } catch (e) {
      emit(state.copyWith(status: AdminStatus.error, error: e.toString()));
    }
  }

  Future<void> _onDeleteAlbum(
    AdminAlbumDeleteRequested event,
    Emitter<AdminState> emit,
  ) async {
    try {
      await _bus.handle(DeleteAlbumCommand(event.albumId));
      final updated =
          state.searchResults.where((a) => a.id != event.albumId).toList();
      emit(state.copyWith(searchResults: updated));
    } catch (e) {
      emit(state.copyWith(status: AdminStatus.error, error: e.toString()));
    }
  }
}
