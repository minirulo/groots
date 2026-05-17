import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';

import '../config/environment.dart';
import '../domain/models/album.dart';
import '../domain/models/track.dart';
import 'ipfs_local_node.dart';

typedef QueueItem = ({Track track, String url, String? artUri, Album? album});

AudioPlayer _buildPlayer() => AudioPlayer(
  audioLoadConfiguration: const AudioLoadConfiguration(
    androidLoadControl: AndroidLoadControl(
      minBufferDuration: Duration(seconds: 30),
      maxBufferDuration: Duration(seconds: 120),
      bufferForPlaybackDuration: Duration(seconds: 3),
      bufferForPlaybackAfterRebufferDuration: Duration(seconds: 6),
    ),
    darwinLoadControl: DarwinLoadControl(
      preferredForwardBufferDuration: Duration(seconds: 60),
    ),
  ),
);

class SoundNetAudioHandler extends BaseAudioHandler with SeekHandler {
  AudioPlayer _player = _buildPlayer();
  final List<QueueItem> _queue = [];
  int _currentIndex = -1;
  // How many manually-added items sit between current and album remainder.
  int _numManuallyAdded = 0;
  bool _repeat = false;
  // While true, stream-listener broadcasts are suppressed so intermediate
  // just_audio states (idle → loading → buffering) during a track transition
  // don't overwrite the explicit "playing + loading" state we broadcast at the
  // start of _playCurrentItem().
  bool _transitioning = false;

  bool get isRepeating => _repeat;
  void toggleRepeat() => _repeat = !_repeat;

  SoundNetAudioHandler() {
    _attachPlayerListeners();
  }

  void _attachPlayerListeners() {
    _player.playingStream.listen((_) {
      if (!_transitioning &&
          _player.processingState != ProcessingState.completed) {
        _broadcastState();
      }
    });
    _player.processingStateStream.listen((state) {
      if (_transitioning) return;
      if (state == ProcessingState.completed) {
        // Do not broadcast the completed state when there is a next track —
        // that would signal audio_service to drop the foreground service before
        // the new track starts.
        if (_repeat) {
          _playCurrentItem();
        } else if (hasNext) {
          skipToNext();
        } else {
          _broadcastState();
        }
      } else {
        _broadcastState();
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

  QueueItem? get currentItem =>
      (_currentIndex >= 0 && _currentIndex < _queue.length)
          ? _queue[_currentIndex]
          : null;

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

    // Suppress all listener-driven broadcasts while we transition between
    // tracks. just_audio fires idle → loading → buffering → ready as it loads
    // the new URL, and each fires _broadcastState() which would overwrite the
    // "playing + loading" state we set below.
    _transitioning = true;

    // Update the media item immediately so the lock screen / notification
    // shows the new track title and artwork before the audio engine loads.
    mediaItem.add(
      MediaItem(
        id: t.id,
        title: t.title,
        artist: item.album?.artist,
        album: item.album?.title,
        duration: Duration(seconds: t.durationSeconds),
        artUri: item.artUri != null ? Uri.tryParse(item.artUri!) : null,
      ),
    );

    // Broadcast an active "playing + loading" state so the lock screen banner
    // stays alive and reads "playing" (not "Not Playing") during the gap.
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          MediaControl.pause,
          MediaControl.skipToNext,
          MediaControl.stop,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 2],
        playing: true,
        updatePosition: Duration.zero,
        processingState: AudioProcessingState.loading,
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
    } finally {
      _transitioning = false;
      // just_audio's play() blocks until the track ends, which means
      // processingStateStream fired ProcessingState.completed while
      // _transitioning was true and the listener returned early.
      // Handle advancement here so we don't miss end-of-track.
      if (_player.processingState == ProcessingState.completed) {
        if (_repeat) {
          _playCurrentItem();
        } else if (hasNext) {
          skipToNext();
        } else {
          _broadcastState();
        }
      } else {
        _broadcastState();
      }
    }
  }

  Stream<bool> get bufferingStream => _player.processingStateStream.map(
    (s) => s == ProcessingState.buffering || s == ProcessingState.loading,
  );

  Future<void> _rebuildPlayer() async {
    await _player.dispose();
    _player = _buildPlayer();
    _attachPlayerListeners();
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

  Future<void> skipToQueueIndex(int index) async {
    if (index < 0 || index >= _queue.length || index == _currentIndex) return;
    _currentIndex = index;
    _numManuallyAdded = 0;
    await _playCurrentItem();
  }

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
