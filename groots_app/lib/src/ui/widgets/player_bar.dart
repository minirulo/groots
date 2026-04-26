import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';

import '../../adapters/providers/album_provider.dart';
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

      return GestureDetector(
        onTap: () => _openFullPlayer(context, player, coverUrl),
        child: _MiniPlayer(player: player, coverUrl: coverUrl),
      );
    });
  }

  String? _resolveCoverUrl(String? albumId) {
    if (albumId == null) return null;
    final albumBloc = Get.find<AlbumBloc>();
    if (albumBloc.state.status != AlbumStatus.loaded) return null;
    final album = albumBloc.state.albums.where((a) => a.id == albumId).firstOrNull;
    if (album?.coverCid == null) return null;
    return Get.find<AlbumProvider>().coverUrl(album!.coverCid!);
  }

  void _openFullPlayer(BuildContext context, PlayerService player, String? coverUrl) {
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
            color: coverUrl == null ? scheme.surfaceContainerHigh : Colors.transparent,
            border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
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
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      track.artist,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Obx(() => IconButton(
                    icon: const Icon(Icons.skip_previous),
                    onPressed: player.hasPrevious.value ? player.previous : null,
                    visualDensity: VisualDensity.compact,
                  )),
              Obx(() => IconButton(
                    icon: Icon(player.isPlaying.value ? Icons.pause : Icons.play_arrow),
                    onPressed: player.togglePause,
                    visualDensity: VisualDensity.compact,
                  )),
              Obx(() => IconButton(
                    icon: const Icon(Icons.skip_next),
                    onPressed: player.hasNext.value ? player.next : null,
                    visualDensity: VisualDensity.compact,
                  )),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Full player sheet ─────────────────────────────────────────────────────────

class _FullPlayerSheet extends StatelessWidget {
  final PlayerService player;
  final String? coverUrl;

  const _FullPlayerSheet({required this.player, this.coverUrl});

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
        if (track == null) {
          Navigator.pop(context);
          return const SizedBox.shrink();
        }

        final pos = player.position.value;
        final dur = player.duration.value;
        final total = dur.inMilliseconds > 0 ? dur.inMilliseconds.toDouble() : 1.0;

        // Resolve cover freshly inside Obx in case track changes
        final freshCover = _resolveCurrentCover();

        return Stack(
          fit: StackFit.expand,
          children: [
            // Blurred full-screen cover background
            if (freshCover != null)
              Image.network(
                freshCover,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            // Dark scrim over the cover
            Container(color: Colors.black.withValues(alpha: 0.55)),
            // Content
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    // Drag handle
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Cover art
                    Expanded(
                      child: Center(
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: freshCover != null
                                ? Image.network(
                                    freshCover,
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
                          Text(_fmt(pos),
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 12)),
                          Text(_fmt(dur),
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 12)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Playback controls
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Obx(() => IconButton(
                              iconSize: 40,
                              color: player.hasPrevious.value
                                  ? Colors.white
                                  : Colors.white30,
                              icon: const Icon(Icons.skip_previous_rounded),
                              onPressed:
                                  player.hasPrevious.value ? player.previous : null,
                            )),
                        Obx(() => Container(
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                              child: IconButton(
                                iconSize: 44,
                                color: Colors.black,
                                icon: Icon(
                                  player.isPlaying.value
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                ),
                                onPressed: player.togglePause,
                              ),
                            )),
                        Obx(() => IconButton(
                              iconSize: 40,
                              color: player.hasNext.value
                                  ? Colors.white
                                  : Colors.white30,
                              icon: const Icon(Icons.skip_next_rounded),
                              onPressed: player.hasNext.value ? player.next : null,
                            )),
                      ],
                    ),
                    const SizedBox(height: 24),
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
    if (track?.albumId == null) return coverUrl;
    final albumBloc = Get.find<AlbumBloc>();
    if (albumBloc.state.status != AlbumStatus.loaded) return coverUrl;
    final album = albumBloc.state.albums
        .where((a) => a.id == track!.albumId)
        .firstOrNull;
    if (album?.coverCid == null) return coverUrl;
    return Get.find<AlbumProvider>().coverUrl(album!.coverCid!);
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
