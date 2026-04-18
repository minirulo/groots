import '../../adapters/providers/library_provider.dart';
import '../../domain/models/track.dart';
import '../commands.dart';

class LibraryHandler {
  final LibraryProvider _provider;

  LibraryHandler({required LibraryProvider provider}) : _provider = provider;

  Future<List<Track>> loadLibrary() => _provider.getTracks();

  Future<String> addTrack(AddTrackCommand cmd) async {
    final result = await _provider.addTrack(cmd.payload);
    return result['track_id'] as String;
  }

  Future<void> removeTrack(RemoveTrackCommand cmd) async {
    await _provider.removeTrack(cmd.trackId);
  }

  Future<void> pinTrack(PinTrackCommand cmd) async {
    await _provider.pinTrack(cmd.trackId);
  }
}
