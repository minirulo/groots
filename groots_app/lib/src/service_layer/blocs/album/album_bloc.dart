import 'package:flutter_bloc/flutter_bloc.dart';

import '../../commands.dart';
import '../../messagebus.dart';
import 'album_event.dart';
import 'album_state.dart';

class AlbumBloc extends Bloc<AlbumEvent, AlbumState> {
  final Messagebus _bus;

  AlbumBloc({required Messagebus bus})
      : _bus = bus,
        super(const AlbumState()) {
    on<AlbumLoadRequested>(_onLoad);
    on<AlbumCreateRequested>(_onCreate);
    on<AlbumDeleteRequested>(_onDelete);
    on<AlbumTrackAssignRequested>(_onAssign);
    on<AlbumTrackUnassignRequested>(_onUnassign);
  }

  Future<void> _onLoad(AlbumLoadRequested event, Emitter<AlbumState> emit) async {
    emit(state.copyWith(status: AlbumStatus.loading));
    try {
      final albums = await _bus.handle(LoadAlbumsCommand());
      emit(state.copyWith(status: AlbumStatus.loaded, albums: albums));
    } catch (e) {
      emit(state.copyWith(status: AlbumStatus.error, error: e.toString()));
    }
  }

  Future<void> _onCreate(AlbumCreateRequested event, Emitter<AlbumState> emit) async {
    try {
      await _bus.handle(CreateAlbumCommand(
        title: event.title,
        artist: event.artist,
        year: event.year,
        genre: event.genre,
        description: event.description,
        recordingFormat: event.recordingFormat,
      ));
      add(AlbumLoadRequested());
    } catch (e) {
      emit(state.copyWith(status: AlbumStatus.error, error: e.toString()));
    }
  }

  Future<void> _onDelete(AlbumDeleteRequested event, Emitter<AlbumState> emit) async {
    try {
      await _bus.handle(DeleteAlbumCommand(event.albumId));
      final updated = state.albums.where((a) => a.id != event.albumId).toList();
      emit(state.copyWith(albums: updated));
    } catch (e) {
      emit(state.copyWith(status: AlbumStatus.error, error: e.toString()));
    }
  }

  Future<void> _onAssign(AlbumTrackAssignRequested event, Emitter<AlbumState> emit) async {
    try {
      await _bus.handle(AssignTrackToAlbumCommand(
        albumId: event.albumId,
        trackId: event.trackId,
        trackNumber: event.trackNumber,
      ));
    } catch (e) {
      emit(state.copyWith(status: AlbumStatus.error, error: e.toString()));
    }
  }

  Future<void> _onUnassign(AlbumTrackUnassignRequested event, Emitter<AlbumState> emit) async {
    try {
      await _bus.handle(UnassignTrackFromAlbumCommand(
        albumId: event.albumId,
        trackId: event.trackId,
      ));
    } catch (e) {
      emit(state.copyWith(status: AlbumStatus.error, error: e.toString()));
    }
  }
}
