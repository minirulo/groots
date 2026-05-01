import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';

import '../../adapters/providers/album_provider.dart';
import '../../service_layer/audio_handler.dart';
import '../../service_layer/blocs/album/album_bloc.dart';
import '../../service_layer/blocs/album/album_state.dart';
import '../../service_layer/player_service.dart';

class PlayerBar extends StatelessWidget {
  const PlayerBar({super.key});

  @override
  Widget build(BuildContext context) {
    final player = Get.find<PlayerService>();
    return Obx(() {
      final track = player.currentTrack.value;
      if (track == null) return const SizedBox.shrink();

      final coverUrl = _resolveCoverUrl(track.albumId);

      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => _openFullPlayer(context, player, coverUrl),
          child: _MiniPlayer(player: player, coverUrl: coverUrl),
        ),
      );
    });
  }

  String? _resolveCoverUrl(String? albumId) {
    if (albumId == null) return null;
    final albumBloc = Get.find<AlbumBloc>();
    if (albumBloc.state.status != AlbumStatus.loaded) return null;
    final album = albumBloc.state.albums
        .where((a) => a.id == albumId)
        .firstOrNull;
    if (album?.coverCid == null) return null;
    return Get.find<AlbumProvider>().coverUrl(album!.coverCid!);
  }

  void _openFullPlayer(
    BuildContext context,
    PlayerService player,
    String? coverUrl,
  ) {
    showCupertinoModalBottomSheet(
      context: context,
      expand: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FullPlayerSheet(player: player, coverUrl: coverUrl),
    );
  }
}

// ── Mini player (always-visible bar) ─────────────────────────────────────────

class _MiniPlayer extends StatelessWidget {
  final PlayerService player;
  final String? coverUrl;

  const _MiniPlayer({required this.player, this.coverUrl});

  @override
  Widget build(BuildContext context) {
    final track = player.currentTrack.value!;
    final scheme = Theme.of(context).colorScheme;

    return Stack(
      children: [
        if (coverUrl != null)
          Positioned.fill(
            child: ShaderMask(
              shaderCallback: (bounds) => LinearGradient(
                colors: [
                  scheme.surface.withValues(alpha: 0.85),
                  scheme.surface.withValues(alpha: 0.95),
                ],
              ).createShader(bounds),
              blendMode: BlendMode.srcOver,
              child: Image.network(
                coverUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ),
        Container(
          decoration: BoxDecoration(
            color: coverUrl == null
                ? scheme.surfaceContainerHigh
                : Colors.transparent,
            border: Border(
              top: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              _CoverThumbnail(coverUrl: coverUrl, size: 44),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      track.title,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      track.artist,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Obx(
                () => IconButton(
                  icon: const Icon(Icons.skip_previous),
                  onPressed: player.hasPrevious.value ? player.previous : null,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              Obx(
                () => player.isBuffering.value
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : IconButton(
                        icon: Icon(
                          player.isPlaying.value ? Icons.pause : Icons.play_arrow,
                        ),
                        onPressed: player.togglePause,
                        visualDensity: VisualDensity.compact,
                      ),
              ),
              Obx(
                () => IconButton(
                  icon: const Icon(Icons.skip_next),
                  onPressed: player.hasNext.value ? player.next : null,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Full player sheet ─────────────────────────────────────────────────────────

class _FullPlayerSheet extends StatefulWidget {
  final PlayerService player;
  final String? coverUrl;

  const _FullPlayerSheet({required this.player, this.coverUrl});

  @override
  State<_FullPlayerSheet> createState() => _FullPlayerSheetState();
}

class _FullPlayerSheetState extends State<_FullPlayerSheet> {
  bool _showQueue = false;
  late final Worker _closeWatcher;

  PlayerService get player => widget.player;

  @override
  void initState() {
    super.initState();
    _closeWatcher = ever(player.currentTrack, (track) {
      if (track == null && mounted) {
        Navigator.of(context).maybePop();
      }
    });
  }

  @override
  void dispose() {
    _closeWatcher.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black,
      child: Obx(() {
        final track = player.currentTrack.value;
        if (track == null) return const SizedBox.shrink();

        final freshCover = _resolveCurrentCover();

        return Stack(
          fit: StackFit.expand,
          children: [
            if (freshCover != null)
              Image.network(
                freshCover,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            Container(color: Colors.black.withValues(alpha: 0.55)),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    // Drag handle
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_showQueue)
                      Expanded(child: _QueueView(player: player))
                    else
                      _PlayerContent(
                        player: player,
                        track: track,
                        freshCover: freshCover,
                        fmt: _fmt,
                      ),
                    // Bottom action row: repeat | stop | queue
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Obx(
                            () => IconButton(
                              icon: Icon(
                                Icons.repeat_one,
                                color: player.isRepeating.value
                                    ? Colors.white
                                    : Colors.white38,
                              ),
                              tooltip: player.isRepeating.value
                                  ? 'Repeat off'
                                  : 'Repeat track',
                              onPressed: player.toggleRepeat,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.stop_circle_outlined,
                              color: Colors.white54,
                            ),
                            tooltip: 'Stop & clear queue',
                            onPressed: player.stop,
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.queue_music,
                              color: _showQueue ? Colors.white : Colors.white38,
                            ),
                            tooltip: _showQueue ? 'Now Playing' : 'Queue',
                            onPressed: () =>
                                setState(() => _showQueue = !_showQueue),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ],
        );
      }),
    );
  }

  String? _resolveCurrentCover() {
    final track = player.currentTrack.value;
    if (track?.albumId == null) return widget.coverUrl;
    final albumBloc = Get.find<AlbumBloc>();
    if (albumBloc.state.status != AlbumStatus.loaded) return widget.coverUrl;
    final album = albumBloc.state.albums
        .where((a) => a.id == track!.albumId)
        .firstOrNull;
    if (album?.coverCid == null) return widget.coverUrl;
    return Get.find<AlbumProvider>().coverUrl(album!.coverCid!);
  }
}

// ── Player content (cover + scrubber + controls) ──────────────────────────────

class _PlayerContent extends StatelessWidget {
  final PlayerService player;
  final dynamic track;
  final String? freshCover;
  final String Function(Duration) fmt;

  const _PlayerContent({
    required this.player,
    required this.track,
    required this.freshCover,
    required this.fmt,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          // Cover art
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 1,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: freshCover != null
                      ? Image.network(
                          freshCover!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              const _PlaceholderCover(),
                        )
                      : const _PlaceholderCover(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),
          // Track info
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                track.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                track.artist,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.75),
                  fontSize: 16,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (track.album != null)
                Text(
                  track.album!,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
          const SizedBox(height: 24),
          // Scrubber
          Obx(() {
            final pos = player.position.value;
            final dur = player.duration.value;
            final total = dur.inMilliseconds > 0
                ? dur.inMilliseconds.toDouble()
                : 1.0;
            return Column(
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: Colors.white,
                    inactiveTrackColor: Colors.white24,
                    thumbColor: Colors.white,
                    overlayColor: Colors.white24,
                  ),
                  child: Slider(
                    value: pos.inMilliseconds.toDouble().clamp(0, total),
                    max: total,
                    onChanged: (v) =>
                        player.seekTo(Duration(milliseconds: v.toInt())),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        fmt(pos),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        fmt(dur),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }),
          const SizedBox(height: 12),
          // Playback controls
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Obx(
                () => IconButton(
                  iconSize: 40,
                  color: player.hasPrevious.value
                      ? Colors.white
                      : Colors.white30,
                  icon: const Icon(Icons.skip_previous_rounded),
                  onPressed: player.hasPrevious.value ? player.previous : null,
                ),
              ),
              Obx(
                () => Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: player.isBuffering.value
                      ? const Padding(
                          padding: EdgeInsets.all(20),
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: Colors.black,
                          ),
                        )
                      : IconButton(
                          iconSize: 44,
                          color: Colors.black,
                          icon: Icon(
                            player.isPlaying.value
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                          ),
                          onPressed: player.togglePause,
                        ),
                ),
              ),
              Obx(
                () => IconButton(
                  iconSize: 40,
                  color: player.hasNext.value ? Colors.white : Colors.white30,
                  icon: const Icon(Icons.skip_next_rounded),
                  onPressed: player.hasNext.value ? player.next : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Queue view ────────────────────────────────────────────────────────────────

class _QueueView extends StatefulWidget {
  final PlayerService player;

  const _QueueView({required this.player});

  @override
  State<_QueueView> createState() => _QueueViewState();
}

class _QueueViewState extends State<_QueueView> {
  final _scrollController = ScrollController();
  int _lastIndex = -1;
  Set<int> _animatingOut = {};

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _jumpTo(int targetIndex) async {
    final cur = widget.player.queueCurrentIndex.value;
    final skippedCount = targetIndex - cur - 1;
    if (skippedCount > 0) {
      setState(() {
        _animatingOut = {for (int i = cur + 1; i < targetIndex; i++) i};
      });
      await Future.delayed(const Duration(milliseconds: 260));
    }
    widget.player.skipToIndex(targetIndex);
    if (mounted) setState(() => _animatingOut = {});
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final q = widget.player.queue;
      final cur = widget.player.queueCurrentIndex.value;
      final manual = widget.player.queueNumManuallyAdded.value;

      // Scroll back to top whenever the current track changes so the
      // "Now Playing" section is always visible after a tap.
      if (cur != _lastIndex) {
        _lastIndex = cur;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(0);
          }
        });
      }

      // Indices of upcoming sections
      final manualStart = cur + 1;
      final manualEnd = cur + manual; // inclusive
      final albumStart = cur + manual + 1;

      return ListView(
        controller: _scrollController,
        children: [
          _QueueSectionHeader('Now Playing'),
          if (cur >= 0 && cur < q.length)
            _QueueTrackTile(
              key: ValueKey(cur),
              item: q[cur],
              index: cur,
              player: widget.player,
              isCurrent: true,
            ),

          if (manual > 0) ...[
            _QueueSectionHeader('Next Up'),
            for (int i = manualStart; i <= manualEnd && i < q.length; i++)
              _QueueTrackTile(
                key: ValueKey(i),
                item: q[i],
                index: i,
                player: widget.player,
                isAnimatingOut: _animatingOut.contains(i),
                onTap: () => _jumpTo(i),
              ),
          ],

          if (albumStart < q.length) ...[
            _QueueSectionHeader('From Album'),
            for (int i = albumStart; i < q.length; i++)
              _QueueTrackTile(
                key: ValueKey(i),
                item: q[i],
                index: i,
                player: widget.player,
                isAnimatingOut: _animatingOut.contains(i),
                onTap: () => _jumpTo(i),
              ),
          ],
        ],
      );
    });
  }
}

class _QueueSectionHeader extends StatelessWidget {
  final String title;
  const _QueueSectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
      child: Text(
        title,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.5),
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _QueueTrackTile extends StatelessWidget {
  final QueueItem item;
  final int index;
  final PlayerService player;
  final bool isCurrent;
  final bool isAnimatingOut;
  final VoidCallback? onTap;

  const _QueueTrackTile({
    super.key,
    required this.item,
    required this.index,
    required this.player,
    this.isCurrent = false,
    this.isAnimatingOut = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = item.track;
    final tile = ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      onTap: isCurrent ? null : onTap,
      leading: isCurrent
          ? const Icon(Icons.graphic_eq, color: Colors.white, size: 20)
          : const Icon(Icons.music_note, color: Colors.white38, size: 20),
      title: Text(
        t.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: isCurrent ? Colors.white : Colors.white70,
          fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
          fontSize: 14,
        ),
      ),
      subtitle: Text(
        t.artist,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white38, fontSize: 12),
      ),
      trailing: Text(
        t.durationFormatted,
        style: const TextStyle(color: Colors.white38, fontSize: 12),
      ),
    );

    return AnimatedSlide(
      offset: isAnimatingOut ? const Offset(-0.18, 0) : Offset.zero,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeIn,
      child: AnimatedOpacity(
        opacity: isAnimatingOut ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeIn,
        child: tile,
      ),
    );
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────────

class _CoverThumbnail extends StatelessWidget {
  final String? coverUrl;
  final double size;

  const _CoverThumbnail({this.coverUrl, this.size = 48});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: size,
        height: size,
        child: coverUrl != null
            ? Image.network(
                coverUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const _PlaceholderCover(),
              )
            : const _PlaceholderCover(),
      ),
    );
  }
}

class _PlaceholderCover extends StatelessWidget {
  const _PlaceholderCover();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white10,
      child: const Icon(Icons.music_note, color: Colors.white54, size: 48),
    );
  }
}
