import 'package:get/get.dart';

import '../domain/models/track.dart';
import 'audio_handler.dart';

class PlayerService extends GetxService {
  final SoundNetAudioHandler _handler;

  final Rx<Track?> currentTrack = Rx(null);
  final RxBool isPlaying = false.obs;
  final Rx<Duration> position = Rx(Duration.zero);
  final Rx<Duration> duration = Rx(Duration.zero);
  final RxBool hasNext = false.obs;
  final RxBool hasPrevious = false.obs;
  final RxBool isRepeating = false.obs;
  final RxList<QueueItem> queue = <QueueItem>[].obs;
  final RxInt queueCurrentIndex = 0.obs;
  final RxInt queueNumManuallyAdded = 0.obs;

  PlayerService(this._handler);

  @override
  void onInit() {
    super.onInit();
    _handler.playbackState.listen((state) {
      isPlaying.value = state.playing;
      _sync();
    });
    _handler.positionStream.listen((pos) => position.value = pos);
    _handler.durationStream.listen((d) => duration.value = d ?? Duration.zero);
    _handler.mediaItem.listen((_) => _sync());
  }

  /// Play a single track (no queue context — no next/previous).
  Future<void> play(Track track, String streamUrl) async {
    await _handler.loadQueue([(track: track, url: streamUrl)], 0);
    _sync();
  }

  /// Play [tracks] as a queue starting at [startIndex].
  /// [urlBuilder] maps each track to its stream URL.
  Future<void> playQueue(
    List<Track> tracks,
    int startIndex,
    String Function(Track) urlBuilder,
  ) async {
    await _handler.loadQueue(
      tracks.map((t) => (track: t, url: urlBuilder(t))).toList(),
      startIndex,
    );
    _sync();
  }

  /// Enqueue [track] to play after any previously queued manual tracks,
  /// before the album remainder.
  void addToQueue(Track track, String url) {
    _handler.addNextInQueue((track: track, url: url));
    _sync();
  }

  Future<void> togglePause() async {
    _handler.playbackState.value.playing
        ? await _handler.pause()
        : await _handler.play();
  }

  Future<void> seekTo(Duration pos) => _handler.seek(pos);

  Future<void> next() => _handler.skipToNext();
  Future<void> previous() => _handler.skipToPrevious();

  void toggleRepeat() {
    _handler.toggleRepeat();
    isRepeating.value = _handler.isRepeating;
  }

  Future<void> stop() async {
    await _handler.stop();
    _sync();
  }

  void _sync() {
    currentTrack.value = _handler.currentTrack;
    hasNext.value = _handler.hasNext;
    hasPrevious.value = _handler.hasPrevious;
    queue.value = _handler.queueSnapshot.toList();
    queueCurrentIndex.value = _handler.queueCurrentIndex;
    queueNumManuallyAdded.value = _handler.numManuallyAdded;
  }

  @override
  void onClose() {
    _handler.dispose();
    super.onClose();
  }
}
