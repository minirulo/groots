import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get/get.dart';

import '../../domain/models/playlist.dart';
import '../../domain/models/track.dart';
import '../../service_layer/blocs/library/library_bloc.dart';
import '../../service_layer/blocs/library/library_state.dart';
import '../../service_layer/blocs/playlist/playlist_bloc.dart';
import '../../service_layer/blocs/playlist/playlist_event.dart';
import '../../service_layer/blocs/playlist/playlist_state.dart';
import '../../service_layer/ipfs_local_node.dart';
import '../../service_layer/player_service.dart';

class PlaylistsView extends StatelessWidget {
  const PlaylistsView({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PlaylistBloc, PlaylistState>(
      builder: (context, state) {
        if (state.status == PlaylistStatus.loading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state.status == PlaylistStatus.error) {
          return Center(child: Text('Error: ${state.error}'));
        }
        if (state.playlists.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('No playlists yet.'),
                const SizedBox(height: 16),
                FilledButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Create Playlist'),
                  onPressed: () => _showCreateDialog(context),
                ),
              ],
            ),
          );
        }
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  FilledButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('New Playlist'),
                    onPressed: () => _showCreateDialog(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: state.playlists.length,
                itemBuilder: (context, i) =>
                    _PlaylistTile(playlist: state.playlists[i]),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showCreateDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Playlist'),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(labelText: 'Name'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (nameCtrl.text.isNotEmpty) {
                context.read<PlaylistBloc>().add(PlaylistCreateRequested(nameCtrl.text));
                Navigator.pop(ctx);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}

class _PlaylistTile extends StatelessWidget {
  final Playlist playlist;
  const _PlaylistTile({required this.playlist});

  @override
  Widget build(BuildContext context) {
    final libraryState = context.read<LibraryBloc>().state;
    final trackCount = libraryState.tracks
        .where((t) => playlist.trackIds.contains(t.id))
        .length;

    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.queue_music)),
      title: Text(playlist.name),
      subtitle: Text('$trackCount track${trackCount == 1 ? '' : 's'}'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Rename',
            onPressed: () => _showRenameDialog(context),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete',
            onPressed: () => context
                .read<PlaylistBloc>()
                .add(PlaylistDeleteRequested(playlist.id)),
          ),
        ],
      ),
      onTap: () => _showPlaylistDetail(context, libraryState),
    );
  }

  void _showRenameDialog(BuildContext context) {
    final nameCtrl = TextEditingController(text: playlist.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Playlist'),
        content: TextField(controller: nameCtrl, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (nameCtrl.text.isNotEmpty) {
                context.read<PlaylistBloc>().add(PlaylistRenameRequested(
                  playlistId: playlist.id,
                  name: nameCtrl.text,
                ));
                Navigator.pop(ctx);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showPlaylistDetail(BuildContext context, LibraryState libraryState) {
    final tracks = playlist.trackIds
        .map((id) => libraryState.tracks.where((t) => t.id == id).firstOrNull)
        .whereType<Track>()
        .toList();
    final playableTracks = tracks.where((t) => t.pinned).toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        expand: false,
        builder: (_, scrollCtrl) => Column(
          children: [
            ListTile(
              title: Text(playlist.name, style: Theme.of(ctx).textTheme.titleLarge),
              subtitle: Text('${tracks.length} track${tracks.length == 1 ? '' : 's'}'),
            ),
            const Divider(),
            Expanded(
              child: tracks.isEmpty
                  ? const Center(child: Text('No tracks in this playlist.'))
                  : ListView.builder(
                      controller: scrollCtrl,
                      itemCount: tracks.length,
                      itemBuilder: (_, i) {
                        final t = tracks[i];
                        final playableIndex =
                            playableTracks.indexWhere((p) => p.id == t.id);
                        return ListTile(
                          leading: const Icon(Icons.music_note),
                          title: Text(t.title),
                          subtitle: Text(t.artist),
                          onTap: t.pinned
                              ? () => _playPlaylist(playableTracks, playableIndex)
                              : null,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.play_arrow),
                                onPressed: t.pinned
                                    ? () => _playPlaylist(playableTracks, playableIndex)
                                    : null,
                              ),
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline),
                                tooltip: 'Remove from playlist',
                                onPressed: () {
                                  context.read<PlaylistBloc>().add(
                                        PlaylistRemoveTrackRequested(
                                          playlistId: playlist.id,
                                          trackId: t.id,
                                        ),
                                      );
                                  Navigator.pop(ctx);
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _playPlaylist(List<Track> playableTracks, int startIndex) {
    if (startIndex < 0) return;
    Get.find<PlayerService>().playQueue(
      playableTracks,
      startIndex,
      (t) => Get.find<IpfsLocalNode>().streamUrl(t.cid, t.mimeType),
    );
  }
}
