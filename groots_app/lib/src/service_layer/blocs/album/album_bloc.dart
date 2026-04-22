import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/models/album.dart';
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
    on<AlbumUpdateRequested>(_onUpdate);
    on<AlbumDeleteRequested>(_onDelete);
    on<AlbumTrackAssignRequested>(_onAssign);
    on<AlbumTrackUnassignRequested>(_onUnassign);
  }

  Future<void> _onLoad(AlbumLoadRequested event, Emitter<AlbumState> emit) async {
    emit(state.copyWith(status: AlbumStatus.loading));
    try {
      final results = await Future.wait([
        _bus.handle<List<Album>>(LoadAlbumsCommand()),
        _bus.handle<List<String>>(LoadGenresCommand()),
      ]);
      emit(state.copyWith(
        status: AlbumStatus.loaded,
        albums: results[0] as List<Album>,
        genres: results[1] as List<String>,
      ));
    } catch (e) {
      emit(state.copyWith(status: AlbumStatus.error, error: e.toString()));
    }
  }

  Future<void> _onCreate(AlbumCreateRequested event, Emitter<AlbumState> emit) async {
    try {
      final albumId = await _bus.handle<String>(CreateAlbumCommand(
        title: event.title,
        artist: event.artist,
        year: event.year,
        genre: event.genre,
        description: event.description,
        recordingFormat: event.recordingFormat,
      ));
      // Optimistically insert so empty albums appear immediately without
      // a reload that the backend might filter out.
      final newAlbum = Album(
        id: albumId,
        title: event.title,
        artist: event.artist,
        year: event.year,
        genre: event.genre,
        recordingFormat: event.recordingFormat,
      );
      emit(state.copyWith(
        status: AlbumStatus.loaded,
        albums: [...state.albums, newAlbum],
      ));
    } catch (e) {
      emit(state.copyWith(status: AlbumStatus.error, error: e.toString()));
    }
  }

  Future<void> _onUpdate(AlbumUpdateRequested event, Emitter<AlbumState> emit) async {
    try {
      await _bus.handle(UpdateAlbumCommand(
        albumId: event.albumId,
        title: event.title,
        artist: event.artist,
        year: event.year,
        genre: event.genre,
        recordingFormat: event.recordingFormat,
      ));
      final updated = state.albums.map((a) {
        if (a.id != event.albumId) return a;
        return Album(
          id: a.id,
          title: event.title,
          artist: event.artist,
          year: event.year,
          genre: event.genre,
          description: a.description,
          coverCid: a.coverCid,
          recordingFormat: event.recordingFormat,
          createdBy: a.createdBy,
        );
      }).toList();
      emit(state.copyWith(albums: updated));
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
