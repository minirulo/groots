import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get/get.dart';

import '../../domain/models/track.dart';
import '../../service_layer/ipfs_local_node.dart';
import '../../service_layer/blocs/library/library_bloc.dart';
import '../../service_layer/blocs/library/library_event.dart';
import '../../service_layer/blocs/library/library_state.dart';
import '../../service_layer/player_service.dart';
import '../widgets/track_tile.dart';

class LibraryView extends StatelessWidget {
  const LibraryView({super.key});

  Future<void> _onPlay(BuildContext context, Track track, List<Track> allTracks) async {
    if (!track.pinned) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pin this track first so the server can serve it.')),
        );
      }
      return;
    }
    final player = Get.find<PlayerService>();
    try {
      final playableTracks = allTracks.where((t) => t.pinned).toList();
      final startIndex = playableTracks.indexWhere((t) => t.id == track.id);
      await player.playQueue(
        playableTracks,
        startIndex < 0 ? 0 : startIndex,
        (t) => Get.find<IpfsLocalNode>().streamUrl(t.cid, t.mimeType),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Playback error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LibraryBloc, LibraryState>(
      builder: (context, state) {
        if (state.status == LibraryStatus.loading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state.status == LibraryStatus.error) {
          return Center(child: Text('Error: ${state.error}'));
        }
        if (state.tracks.isEmpty) {
          return const Center(
            child: Text('No tracks yet.\nUse the Sync tab to add music from your library.'),
          );
        }
        return ListView.builder(
          itemCount: state.tracks.length,
          itemBuilder: (context, i) {
            final track = state.tracks[i];
            return TrackTile(
              track: track,
              onPlay: () => _onPlay(context, track, state.tracks),
              onPin: () => context.read<LibraryBloc>().add(LibraryTrackPinRequested(track.id)),
              onDelete: () => context.read<LibraryBloc>().add(LibraryTrackRemoveRequested(track.id)),
            );
          },
        );
      },
    );
  }
}
