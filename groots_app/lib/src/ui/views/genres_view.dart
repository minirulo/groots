import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get/get.dart';

import '../../service_layer/blocs/library/library_bloc.dart';
import '../../service_layer/blocs/library/library_state.dart';
import '../../service_layer/ipfs_local_node.dart';
import '../../service_layer/player_service.dart';

class GenresView extends StatelessWidget {
  const GenresView({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LibraryBloc, LibraryState>(
      builder: (context, state) {
        if (state.status == LibraryStatus.loading) {
          return const Center(child: CircularProgressIndicator());
        }

        final genres = state.tracks
            .map((t) => t.genre)
            .whereType<String>()
            .toSet()
            .toList()
          ..sort();

        if (genres.isEmpty) {
          return const Center(
            child: Text('No genres yet.\nAdd genre metadata to your tracks.'),
          );
        }

        return ListView.builder(
          itemCount: genres.length,
          itemBuilder: (context, i) => _GenreTile(genre: genres[i]),
        );
      },
    );
  }
}

class _GenreTile extends StatelessWidget {
  final String genre;
  const _GenreTile({required this.genre});

  static const _genreColors = [
    Colors.deepPurple,
    Colors.indigo,
    Colors.blue,
    Colors.teal,
    Colors.green,
    Colors.orange,
    Colors.red,
    Colors.pink,
  ];

  Color get _color => _genreColors[genre.hashCode.abs() % _genreColors.length];

  @override
  Widget build(BuildContext context) {
    final state = context.read<LibraryBloc>().state;
    final tracks = state.tracks.where((t) => t.genre == genre).toList();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showGenreDetail(context, tracks),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: _color, width: 4)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: _color.withValues(alpha: 0.15),
                child: Icon(Icons.music_note, color: _color),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(genre,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    Text('${tracks.length} track${tracks.length == 1 ? '' : 's'}',
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }

  void _showGenreDetail(BuildContext context, List tracks) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        expand: false,
        builder: (_, scrollCtrl) => Column(
          children: [
            ListTile(
              leading: CircleAvatar(
                backgroundColor: _color.withValues(alpha: 0.15),
                child: Icon(Icons.music_note, color: _color),
              ),
              title: Text(genre, style: Theme.of(ctx).textTheme.titleLarge),
              subtitle: Text('${tracks.length} tracks'),
            ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                controller: scrollCtrl,
                itemCount: tracks.length,
                itemBuilder: (_, i) {
                  final t = tracks[i];
                  return ListTile(
                    leading: const Icon(Icons.music_note),
                    title: Text(t.title),
                    subtitle: Text(t.artist),
                    trailing: IconButton(
                      icon: const Icon(Icons.play_arrow),
                      onPressed: t.pinned
                          ? () {
                              final player = Get.find<PlayerService>();
                              player.play(
                                t,
                                Get.find<IpfsLocalNode>().streamUrl(t.cid, t.mimeType),
                              );
                              Navigator.pop(ctx);
                            }
                          : null,
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
}
