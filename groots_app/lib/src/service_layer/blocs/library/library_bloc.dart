import 'package:flutter_bloc/flutter_bloc.dart';

import '../../commands.dart';
import '../../messagebus.dart';
import 'library_event.dart';
import 'library_state.dart';

class LibraryBloc extends Bloc<LibraryEvent, LibraryState> {
  final Messagebus _bus;

  LibraryBloc({required Messagebus bus})
      : _bus = bus,
        super(const LibraryState()) {
    on<LibraryLoadRequested>(_onLoad);
    on<LibraryTrackRemoveRequested>(_onRemove);
    on<LibraryTrackPinRequested>(_onPin);
  }

  Future<void> _onLoad(LibraryLoadRequested event, Emitter<LibraryState> emit) async {
    emit(state.copyWith(status: LibraryStatus.loading));
    try {
      final tracks = await _bus.handle(LoadLibraryCommand());
      emit(state.copyWith(status: LibraryStatus.loaded, tracks: tracks));
    } catch (e) {
      emit(state.copyWith(status: LibraryStatus.error, error: e.toString()));
    }
  }

  Future<void> _onRemove(LibraryTrackRemoveRequested event, Emitter<LibraryState> emit) async {
    try {
      await _bus.handle(RemoveTrackCommand(event.trackId));
      final updated = state.tracks.where((t) => t.id != event.trackId).toList();
      emit(state.copyWith(tracks: updated));
    } catch (e) {
      emit(state.copyWith(status: LibraryStatus.error, error: e.toString()));
    }
  }

  Future<void> _onPin(LibraryTrackPinRequested event, Emitter<LibraryState> emit) async {
    try {
      await _bus.handle(PinTrackCommand(event.trackId));
      add(LibraryLoadRequested());
    } catch (e) {
      emit(state.copyWith(status: LibraryStatus.error, error: e.toString()));
    }
  }
}
