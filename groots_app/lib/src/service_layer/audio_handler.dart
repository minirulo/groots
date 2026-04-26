import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';

import '../config/environment.dart';
import '../domain/models/track.dart';
import 'ipfs_local_node.dart';

typedef QueueItem = ({Track track, String url});

class SoundNetAudioHandler extends BaseAudioHandler with SeekHandler {
  AudioPlayer _player = AudioPlayer();
  final List<QueueItem> _queue = [];
  int _currentIndex = -1;
  // How many manually-added items sit between current and album remainder.
  int _numManuallyAdded = 0;
  bool _repeat = false;

  bool get isRepeating => _repeat;
  void toggleRepeat() => _repeat = !_repeat;

  SoundNetAudioHandler() {
    _player.playingStream.listen((_) => _broadcastState());
    _player.processingStateStream.listen((state) {
      _broadcastState();
      if (state == ProcessingState.completed) {
        if (_repeat) {
          _playCurrentItem();
        } else {
          skipToNext();
        }
      }
    });
    _player.durationStream.listen((d) {
      final current = mediaItem.value;
      if (current != null && d != null) {
        mediaItem.add(current.copyWith(duration: d));
      }
    });
  }

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;

  Track? get currentTrack =>
      (_currentIndex >= 0 && _currentIndex < _queue.length)
      ? _queue[_currentIndex].track
      : null;

  bool get hasNext => _currentIndex < _queue.length - 1;
  bool get hasPrevious => _currentIndex > 0;

  List<QueueItem> get queueSnapshot => List.unmodifiable(_queue);
  int get queueCurrentIndex => _currentIndex;
  int get numManuallyAdded => _numManuallyAdded;

  Future<void> loadQueue(List<QueueItem> items, int startIndex) async {
    _queue
      ..clear()
      ..addAll(items);
    _currentIndex = startIndex.clamp(0, items.length - 1);
    _numManuallyAdded = 0;
    await _playCurrentItem();
  }

  /// Insert [item] right after all previously enqueued manual tracks but before
  /// the album remainder, so manually-added tracks play in insertion order.
  void addNextInQueue(QueueItem item) {
    final insertAt = _currentIndex + 1 + _numManuallyAdded;
    _queue.insert(insertAt, item);
    _numManuallyAdded++;
  }

  Future<void> _playCurrentItem() async {
    if (_currentIndex < 0 || _currentIndex >= _queue.length) return;
    final item = _queue[_currentIndex];
    final t = item.track;
    mediaItem.add(
      MediaItem(
        id: t.id,
        title: t.title,
        artist: t.artist,
        album: t.album,
        duration: Duration(seconds: t.durationSeconds),
      ),
    );
    try {
      await _player.setUrl(item.url);
      await _player.play();
      // Pin the CID on the local node so it's available on future hot restarts.
      Get.find<IpfsLocalNode>().pinAdd(t.cid).ignore();
    } on MissingPluginException {
      // Native audio channel stale after hot restart — rebuild and retry.
      await _rebuildPlayer();
      try {
        await _player.setUrl(item.url);
        await _player.play();
        Get.find<IpfsLocalNode>().pinAdd(t.cid).ignore();
      } on MissingPluginException catch (e) {
        debugPrint(
          '[AudioHandler] channel still broken after rebuild: $e — full restart required',
        );
      } catch (e) {
        debugPrint('[AudioHandler] playback error after rebuild: $e');
      }
    } catch (e) {
      // Local IPFS gateway couldn't serve the CID (not yet pinned locally).
      // Fall back to the central gateway URL.
      debugPrint(
        '[AudioHandler] local URL failed ($e), falling back to central gateway',
      );
      final fallbackUrl = Environment().config.ipfsStreamUrl(t.cid, t.mimeType);
      try {
        await _player.setUrl(fallbackUrl);
        await _player.play();
        Get.find<IpfsLocalNode>().pinAdd(t.cid).ignore();
      } catch (e2) {
        debugPrint('[AudioHandler] central gateway also failed: $e2');
      }
    }
  }

  Future<void> _rebuildPlayer() async {
    await _player.dispose();
    _player = AudioPlayer();
    _player.playingStream.listen((_) => _broadcastState());
    _player.processingStateStream.listen((state) {
      _broadcastState();
      if (state == ProcessingState.completed) skipToNext();
    });
    _player.durationStream.listen((d) {
      final current = mediaItem.value;
      if (current != null && d != null)
        mediaItem.add(current.copyWith(duration: d));
    });
  }

  @override
  Future<void> play() async {
    try {
      await _player.play();
    } on MissingPluginException {
      debugPrint('[AudioHandler] stale channel on play() — rebuilding player');
      await _rebuildPlayer();
      if (_currentIndex >= 0 && _currentIndex < _queue.length) {
        await _playCurrentItem();
      }
    } catch (e) {
      debugPrint('[AudioHandler] play() error: $e');
    }
  }

  @override
  Future<void> pause() async {
    try {
      await _player.pause();
    } on MissingPluginException catch (e) {
      debugPrint('pause() called on stale channel: $e');
    }
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    _queue.clear();
    _currentIndex = -1;
    _numManuallyAdded = 0;
    mediaItem.add(null);
    _broadcastState();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    if (hasNext) {
      if (_numManuallyAdded > 0) _numManuallyAdded--;
      _currentIndex++;
      await _playCurrentItem();
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (hasPrevious) {
      _currentIndex--;
      await _playCurrentItem();
    }
  }

  @override
  Future<void> onTaskRemoved() => stop();

  void dispose() => _player.dispose();

  void _broadcastState() {
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          _player.playing ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.stop,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 2],
        playing: _player.playing,
        updatePosition: _player.position,
        processingState: const {
          ProcessingState.idle: AudioProcessingState.idle,
          ProcessingState.loading: AudioProcessingState.loading,
          ProcessingState.buffering: AudioProcessingState.buffering,
          ProcessingState.ready: AudioProcessingState.ready,
          ProcessingState.completed: AudioProcessingState.completed,
        }[_player.processingState]!,
      ),
    );
  }
}
