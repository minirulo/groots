import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get/get.dart';

import '../../domain/models/album.dart';
import '../../domain/models/track.dart';
import '../../service_layer/blocs/album/album_bloc.dart';
import '../../service_layer/blocs/album/album_event.dart';
import '../../service_layer/blocs/album/album_state.dart';
import '../../service_layer/blocs/playlist/playlist_bloc.dart';
import '../../service_layer/blocs/playlist/playlist_event.dart';
import '../../service_layer/ipfs_local_node.dart';
import '../../service_layer/player_service.dart';

class TrackTile extends StatelessWidget {
  final Track track;
  final Album? album;
  final VoidCallback? onPlay;
  final VoidCallback? onPin;
  final VoidCallback? onDelete;
  final VoidCallback? onReplaceRecording;
  final VoidCallback? onTap;
  final bool showLibraryActions;

  const TrackTile({
    super.key,
    required this.track,
    this.album,
    this.onPlay,
    this.onPin,
    this.onDelete,
    this.onReplaceRecording,
    this.onTap,
    this.showLibraryActions = false,
  });

  @override
  Widget build(BuildContext context) {
    final isMobile = switch (Theme.of(context).platform) {
      TargetPlatform.iOS || TargetPlatform.android => true,
      _ => false,
    };

    return ListTile(
      onTap: onTap,
      leading: const Icon(Icons.music_note),
      title: Text(track.title, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          if (album?.artist != null) album!.artist,
          if (track.discNumber != null) 'Disc ${track.discNumber}',
          if (track.side != null) 'Side ${track.side}',
        ].join(' · '),
        overflow: TextOverflow.ellipsis,
      ),
      trailing: isMobile
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showLibraryActions && track.pinned)
                  const Tooltip(
                    message: 'Pinned on server',
                    child: Padding(
                      padding: EdgeInsets.only(right: 4),
                      child: Icon(Icons.push_pin, size: 16),
                    ),
                  ),
                PopupMenuButton<_TrackAction>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (action) => _handleAction(context, action),
                  itemBuilder: (_) => _buildMenuItems(
                    includePlay: false,
                    includeLibraryActions: showLibraryActions,
                  ),
                ),
              ],
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  track.durationFormatted,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(width: 4),
                if (!track.pinned)
                  IconButton(
                    icon: const Icon(Icons.push_pin_outlined),
                    tooltip: 'Pin to server',
                    onPressed: onPin,
                  ),
                if (track.pinned)
                  const Tooltip(
                    message: 'Pinned on server',
                    child: Icon(Icons.push_pin, size: 18),
                  ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Remove',
                  onPressed: onDelete == null
                      ? null
                      : () => _confirmDelete(context, onDelete!),
                ),
                IconButton(
                  icon: const Icon(Icons.play_arrow),
                  tooltip: 'Play',
                  onPressed: onPlay,
                ),
                PopupMenuButton<_TrackAction>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (action) => _handleAction(context, action),
                  itemBuilder: (_) => _buildMenuItems(
                    includePlay: false,
                    includeLibraryActions: showLibraryActions,
                  ),
                ),
              ],
            ),
    );
  }

  List<PopupMenuEntry<_TrackAction>> _buildMenuItems({
    required bool includePlay,
    bool includeLibraryActions = false,
  }) {
    final player = Get.find<PlayerService>();
    final isQueueActive = player.currentTrack.value != null;
    final currentAlbumId = player.currentTrack.value?.albumId;
    final sameAlbum = track.albumId != null && track.albumId == currentAlbumId;
    return [
      if (includePlay)
        PopupMenuItem(
          value: _TrackAction.play,
          enabled: track.pinned,
          child: const ListTile(
            leading: Icon(Icons.play_arrow),
            title: Text('Play'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      if (includeLibraryActions && !track.pinned)
        const PopupMenuItem(
          value: _TrackAction.pin,
          child: ListTile(
            leading: Icon(Icons.push_pin_outlined),
            title: Text('Pin to server'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      if (includeLibraryActions)
        const PopupMenuItem(
          value: _TrackAction.replaceRecording,
          child: ListTile(
            leading: Icon(Icons.swap_horiz),
            title: Text('Replace Recording'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      if (includeLibraryActions)
        const PopupMenuItem(
          value: _TrackAction.delete,
          child: ListTile(
            leading: Icon(Icons.delete_outline),
            title: Text('Remove'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      const PopupMenuItem(
        value: _TrackAction.addToPlaylist,
        child: ListTile(
          leading: Icon(Icons.queue_music),
          title: Text('Add to Playlist'),
          contentPadding: EdgeInsets.zero,
        ),
      ),
      const PopupMenuItem(
        value: _TrackAction.assignToAlbum,
        child: ListTile(
          leading: Icon(Icons.album),
          title: Text('Assign to Album'),
          contentPadding: EdgeInsets.zero,
        ),
      ),
      PopupMenuItem(
        value: _TrackAction.addToQueue,
        enabled: isQueueActive && !sameAlbum && track.pinned,
        child: const ListTile(
          leading: Icon(Icons.playlist_add),
          title: Text('Add to Queue'),
          contentPadding: EdgeInsets.zero,
        ),
      ),
    ];
  }

  void _confirmDelete(BuildContext context, VoidCallback onConfirmed) {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove track?'),
        content: Text('"${track.title}" will be permanently removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              onConfirmed();
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  void _handleAction(BuildContext context, _TrackAction action) {
    switch (action) {
      case _TrackAction.play:
        onPlay?.call();
      case _TrackAction.pin:
        onPin?.call();
      case _TrackAction.replaceRecording:
        onReplaceRecording?.call();
      case _TrackAction.delete:
        if (onDelete != null) _confirmDelete(context, onDelete!);
      case _TrackAction.addToPlaylist:
        _showAddToPlaylistSheet(context);
      case _TrackAction.assignToAlbum:
        _showAssignToAlbumSheet(context);
      case _TrackAction.addToQueue:
        _addToQueue(context);
    }
  }

  void _addToQueue(BuildContext context) {
    final player = Get.find<PlayerService>();
    final url = Get.find<IpfsLocalNode>().streamUrl(track.cid, track.mimeType);
    player.addToQueue(track, url);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('"${track.title}" added to queue')));
  }

  void _showAddToPlaylistSheet(BuildContext context) {
    final state = context.read<PlaylistBloc>().state;
    if (state.playlists.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Create a playlist first.')));
      return;
    }
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ListTile(
            title: Text(
              'Add to Playlist',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          const Divider(height: 1),
          ...state.playlists.map(
            (p) => ListTile(
              leading: const Icon(Icons.queue_music),
              title: Text(p.name),
              onTap: () {
                context.read<PlaylistBloc>().add(
                  PlaylistAddTrackRequested(
                    playlistId: p.id,
                    trackId: track.id,
                  ),
                );
                Navigator.pop(ctx);
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('Added to "${p.name}"')));
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  void _showAssignToAlbumSheet(BuildContext context) {
    final state = context.read<AlbumBloc>().state;
    if (state.status != AlbumStatus.loaded || state.albums.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Create an album first.')));
      return;
    }
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ListTile(
            title: Text(
              'Assign to Album',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          const Divider(height: 1),
          ...state.albums.map(
            (a) => ListTile(
              leading: const Icon(Icons.album),
              title: Text(a.title),
              subtitle: Text(a.artist),
              onTap: () {
                context.read<AlbumBloc>().add(
                  AlbumTrackAssignRequested(albumId: a.id, trackId: track.id),
                );
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Assigned to "${a.title}"')),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

enum _TrackAction {
  play,
  pin,
  replaceRecording,
  delete,
  addToPlaylist,
  assignToAlbum,
  addToQueue,
}
