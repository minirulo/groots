import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get/get.dart';

import '../../domain/models/track.dart';
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

  void _play(List<Track> results, int index) {
    final playable = results.where((t) => t.pinned).toList();
    final adjusted = playable.indexWhere((t) => t.id == results[index].id);
    if (adjusted < 0) return;
    Get.find<PlayerService>().playQueue(
      playable,
      adjusted,
      (t) => Get.find<IpfsLocalNode>().streamUrl(t.cid, t.mimeType),
    );
  }

  List<Track> _filter(List<Track> tracks) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return [];
    return tracks.where((t) {
      return t.title.toLowerCase().contains(q) ||
          t.artist.toLowerCase().contains(q) ||
          (t.album?.toLowerCase().contains(q) ?? false);
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
            builder: (context, state) {
              if (_query.trim().isEmpty) {
                return const Center(child: Text('Type to search your library'));
              }

              if (state.status == LibraryStatus.loading) {
                return const Center(child: CircularProgressIndicator());
              }

              final results = _filter(state.tracks);

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
                  return TrackTile(
                    track: t,
                    onPlay: () => _play(results, i),
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
          ),
        ),
      ],
    );
  }
}
