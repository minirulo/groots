import 'package:flutter_bloc/flutter_bloc.dart';

import '../../commands.dart';
import '../../messagebus.dart';
import 'playlist_event.dart';
import 'playlist_state.dart';

class PlaylistBloc extends Bloc<PlaylistEvent, PlaylistState> {
  final Messagebus _bus;

  PlaylistBloc({required Messagebus bus})
      : _bus = bus,
        super(const PlaylistState()) {
    on<PlaylistLoadRequested>(_onLoad);
    on<PlaylistCreateRequested>(_onCreate);
    on<PlaylistRenameRequested>(_onRename);
    on<PlaylistDeleteRequested>(_onDelete);
    on<PlaylistAddTrackRequested>(_onAddTrack);
    on<PlaylistRemoveTrackRequested>(_onRemoveTrack);
  }

  Future<void> _onLoad(PlaylistLoadRequested event, Emitter<PlaylistState> emit) async {
    emit(state.copyWith(status: PlaylistStatus.loading));
    try {
      final playlists = await _bus.handle(LoadPlaylistsCommand());
      emit(state.copyWith(status: PlaylistStatus.loaded, playlists: playlists));
    } catch (e) {
      emit(state.copyWith(status: PlaylistStatus.error, error: e.toString()));
    }
  }

  Future<void> _onCreate(PlaylistCreateRequested event, Emitter<PlaylistState> emit) async {
    try {
      await _bus.handle(CreatePlaylistCommand(event.name));
      add(PlaylistLoadRequested());
    } catch (e) {
      emit(state.copyWith(status: PlaylistStatus.error, error: e.toString()));
    }
  }

  Future<void> _onRename(PlaylistRenameRequested event, Emitter<PlaylistState> emit) async {
    try {
      await _bus.handle(RenamePlaylistCommand(playlistId: event.playlistId, name: event.name));
      add(PlaylistLoadRequested());
    } catch (e) {
      emit(state.copyWith(status: PlaylistStatus.error, error: e.toString()));
    }
  }

  Future<void> _onDelete(PlaylistDeleteRequested event, Emitter<PlaylistState> emit) async {
    try {
      await _bus.handle(DeletePlaylistCommand(event.playlistId));
      final updated = state.playlists.where((p) => p.id != event.playlistId).toList();
      emit(state.copyWith(playlists: updated));
    } catch (e) {
      emit(state.copyWith(status: PlaylistStatus.error, error: e.toString()));
    }
  }

  Future<void> _onAddTrack(PlaylistAddTrackRequested event, Emitter<PlaylistState> emit) async {
    try {
      await _bus.handle(AddTrackToPlaylistCommand(
        playlistId: event.playlistId,
        trackId: event.trackId,
      ));
      add(PlaylistLoadRequested());
    } catch (e) {
      emit(state.copyWith(status: PlaylistStatus.error, error: e.toString()));
    }
  }

  Future<void> _onRemoveTrack(PlaylistRemoveTrackRequested event, Emitter<PlaylistState> emit) async {
    try {
      await _bus.handle(RemoveTrackFromPlaylistCommand(
        playlistId: event.playlistId,
        trackId: event.trackId,
      ));
      add(PlaylistLoadRequested());
    } catch (e) {
      emit(state.copyWith(status: PlaylistStatus.error, error: e.toString()));
    }
  }
}
