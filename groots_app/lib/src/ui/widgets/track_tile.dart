import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/models/track.dart';
import '../../service_layer/blocs/album/album_bloc.dart';
import '../../service_layer/blocs/album/album_event.dart';
import '../../service_layer/blocs/album/album_state.dart';
import '../../service_layer/blocs/playlist/playlist_bloc.dart';
import '../../service_layer/blocs/playlist/playlist_event.dart';

class TrackTile extends StatelessWidget {
  final Track track;
  final VoidCallback? onPlay;
  final VoidCallback? onPin;
  final VoidCallback? onDelete;

  const TrackTile({
    super.key,
    required this.track,
    this.onPlay,
    this.onPin,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.music_note),
      title: Text(track.title, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${track.artist}${track.album != null ? ' · ${track.album}' : ''}',
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(track.durationFormatted,
              style: Theme.of(context).textTheme.bodySmall),
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
            onPressed: onDelete,
          ),
          IconButton(
            icon: const Icon(Icons.play_arrow),
            tooltip: 'Play',
            onPressed: onPlay,
          ),
          PopupMenuButton<_TrackAction>(
            icon: const Icon(Icons.more_vert),
            onSelected: (action) => _handleAction(context, action),
            itemBuilder: (_) => [
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
            ],
          ),
        ],
      ),
    );
  }

  void _handleAction(BuildContext context, _TrackAction action) {
    switch (action) {
      case _TrackAction.addToPlaylist:
        _showAddToPlaylistSheet(context);
      case _TrackAction.assignToAlbum:
        _showAssignToAlbumSheet(context);
    }
  }

  void _showAddToPlaylistSheet(BuildContext context) {
    final state = context.read<PlaylistBloc>().state;
    if (state.playlists.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Create a playlist first.')),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ListTile(title: Text('Add to Playlist', style: TextStyle(fontWeight: FontWeight.bold))),
          const Divider(height: 1),
          ...state.playlists.map((p) => ListTile(
                leading: const Icon(Icons.queue_music),
                title: Text(p.name),
                onTap: () {
                  context.read<PlaylistBloc>().add(PlaylistAddTrackRequested(
                    playlistId: p.id,
                    trackId: track.id,
                  ));
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Added to "${p.name}"')),
                  );
                },
              )),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  void _showAssignToAlbumSheet(BuildContext context) {
    final state = context.read<AlbumBloc>().state;
    if (state.status != AlbumStatus.loaded || state.albums.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Create an album first.')),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ListTile(title: Text('Assign to Album', style: TextStyle(fontWeight: FontWeight.bold))),
          const Divider(height: 1),
          ...state.albums.map((a) => ListTile(
                leading: const Icon(Icons.album),
                title: Text(a.title),
                subtitle: Text(a.artist),
                onTap: () {
                  context.read<AlbumBloc>().add(AlbumTrackAssignRequested(
                    albumId: a.id,
                    trackId: track.id,
                  ));
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Assigned to "${a.title}"')),
                  );
                },
              )),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

enum _TrackAction { addToPlaylist, assignToAlbum }
