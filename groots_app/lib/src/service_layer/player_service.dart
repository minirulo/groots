import 'package:get/get.dart';

import '../domain/models/album.dart';
import '../domain/models/track.dart';
import 'audio_handler.dart';

class PlayerService extends GetxService {
  final SoundNetAudioHandler _handler;

  final Rx<Track?> currentTrack = Rx(null);
  final Rx<Album?> currentAlbum = Rx(null);
  final RxBool isPlaying = false.obs;
  final Rx<Duration> position = Rx(Duration.zero);
  final Rx<Duration> duration = Rx(Duration.zero);
  final RxBool hasNext = false.obs;
  final RxBool hasPrevious = false.obs;
  final RxBool isRepeating = false.obs;
  final RxBool isBuffering = false.obs;
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
    _handler.bufferingStream.listen((buffering) => isBuffering.value = buffering);
    _handler.positionStream.listen((pos) {
      if (!isBuffering.value) position.value = pos;
    });
    _handler.durationStream.listen((d) => duration.value = d ?? Duration.zero);
    _handler.mediaItem.listen((_) => _sync());
  }

  /// Play a single track. Pass [album] so the lock screen / notification
  /// can display artist and album name.
  Future<void> play(Track track, String streamUrl, {Album? album}) async {
    await _handler.loadQueue(
      [_item(track, streamUrl, null, album)],
      0,
    );
    _sync();
  }

  /// Play [tracks] as a queue starting at [startIndex].
  /// [urlBuilder] maps each track to its stream URL.
  /// [albumsById] optionally supplies album metadata keyed by album ID so the
  /// lock screen / notification shows the correct artist per track.
  /// [artUriBuilder] optionally maps each track to a cover art URL.
  Future<void> playQueue(
    List<Track> tracks,
    int startIndex,
    String Function(Track) urlBuilder, {
    Map<String, Album>? albumsById,
    String? Function(Track)? artUriBuilder,
  }) async {
    await _handler.loadQueue(
      tracks
          .map((t) => _item(
                t,
                urlBuilder(t),
                artUriBuilder?.call(t),
                t.albumId == null ? null : albumsById?[t.albumId!],
              ))
          .toList(),
      startIndex,
    );
    _sync();
  }

  /// Enqueue [track] to play after any previously queued manual tracks.
  void addToQueue(Track track, String url, {Album? album}) {
    _handler.addNextInQueue(_item(track, url, null, album));
    _sync();
  }

  static QueueItem _item(Track track, String url, String? artUri, Album? album) =>
      (track: track, url: url, artUri: artUri, album: album);

  Future<void> togglePause() async {
    _handler.playbackState.value.playing
        ? await _handler.pause()
        : await _handler.play();
  }

  Future<void> seekTo(Duration pos) => _handler.seek(pos);

  Future<void> next() => _handler.skipToNext();
  Future<void> previous() => _handler.skipToPrevious();
  Future<void> skipToIndex(int index) async {
    await _handler.skipToQueueIndex(index);
    _sync();
  }

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
    currentAlbum.value = _handler.currentItem?.album;
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
