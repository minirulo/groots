import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get/get.dart';

import '../../domain/models/album.dart';
import '../../domain/models/track.dart';
import '../../service_layer/blocs/album/album_bloc.dart';
import '../../service_layer/blocs/album/album_state.dart';
import '../../service_layer/blocs/library/library_bloc.dart';
import '../../service_layer/blocs/library/library_event.dart';
import '../../service_layer/blocs/library/library_state.dart';
import '../../service_layer/ipfs_local_node.dart';
import '../../service_layer/player_service.dart';
import '../widgets/track_tile.dart';

class SearchView extends StatefulWidget {
  final void Function(Track track)? onTrackTapped;

  const SearchView({super.key, this.onTrackTapped});

  @override
  State<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<SearchView> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _play(List<Track> results, int index, Map<String, Album> albumsById) {
    final playable = results.where((t) => t.pinned).toList();
    final adjusted = playable.indexWhere((t) => t.id == results[index].id);
    if (adjusted < 0) return;
    Get.find<PlayerService>().playQueue(
      playable,
      adjusted,
      (t) => Get.find<IpfsLocalNode>().streamUrl(t.cid, t.mimeType),
      albumsById: albumsById,
    );
  }

  List<Track> _filter(List<Track> tracks, Map<String, Album> albumsById) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return [];
    return tracks.where((t) {
      if (t.title.toLowerCase().contains(q)) return true;
      final album = t.albumId != null ? albumsById[t.albumId!] : null;
      if (album == null) return false;
      return album.title.toLowerCase().contains(q) ||
          album.artist.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _controller,
            autofocus: false,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search tracks, artists, albums…',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _controller.clear();
                        setState(() => _query = '');
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide: BorderSide.none,
              ),
              filled: true,
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Expanded(
          child: BlocBuilder<LibraryBloc, LibraryState>(
            builder: (context, libraryState) {
              return BlocBuilder<AlbumBloc, AlbumState>(
                builder: (context, albumState) {
                  if (_query.trim().isEmpty) {
                    return const Center(child: Text('Type to search your library'));
                  }

                  if (libraryState.status == LibraryStatus.loading) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final albumsById = {
                    for (final a in albumState.albums) a.id: a,
                  };
                  final results = _filter(libraryState.tracks, albumsById);

                  if (results.isEmpty) {
                    return Center(
                      child: Text('No results for "${_query.trim()}"'),
                    );
                  }

                  return ListView.builder(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    itemCount: results.length,
                    itemBuilder: (context, i) {
                      final t = results[i];
                      final album =
                          t.albumId != null ? albumsById[t.albumId!] : null;
                      return TrackTile(
                        track: t,
                        album: album,
                        onPlay: () => _play(results, i, albumsById),
                        onTap: widget.onTrackTapped != null
                            ? () => widget.onTrackTapped!(t)
                            : null,
                        onPin: () => context
                            .read<LibraryBloc>()
                            .add(LibraryTrackPinRequested(t.id)),
                        onDelete: () => context
                            .read<LibraryBloc>()
                            .add(LibraryTrackRemoveRequested(t.id)),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
