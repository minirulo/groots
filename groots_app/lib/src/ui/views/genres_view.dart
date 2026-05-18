import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get/get.dart';

import '../../domain/models/album.dart';
import '../../service_layer/blocs/album/album_bloc.dart';
import '../../service_layer/blocs/album/album_state.dart';
import '../../service_layer/blocs/library/library_bloc.dart';
import '../../service_layer/blocs/library/library_state.dart';
import '../../service_layer/ipfs_local_node.dart';
import '../../service_layer/player_service.dart';

class GenresView extends StatelessWidget {
  const GenresView({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AlbumBloc, AlbumState>(
      builder: (context, state) {
        if (state.status == AlbumStatus.loading) {
          return const Center(child: CircularProgressIndicator());
        }

        final genres = state.albums
            .map((a) => a.genre)
            .whereType<String>()
            .toSet()
            .toList()
          ..sort();

        if (genres.isEmpty) {
          return const Center(
            child: Text('No genres yet.\nAdd genre metadata to your albums.'),
          );
        }

        return ListView.builder(
          itemCount: genres.length,
          itemBuilder: (context, i) => _GenreTile(
            genre: genres[i],
            albums: state.albums.where((a) => a.genre == genres[i]).toList(),
          ),
        );
      },
    );
  }
}

class _GenreTile extends StatelessWidget {
  final String genre;
  final List<Album> albums;

  const _GenreTile({required this.genre, required this.albums});

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
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showGenreDetail(context),
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
                    Text('${albums.length} album${albums.length == 1 ? '' : 's'}',
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

  void _showGenreDetail(BuildContext context) {
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
              subtitle: Text('${albums.length} albums'),
            ),
            const Divider(),
            Expanded(
              child: BlocBuilder<LibraryBloc, LibraryState>(
                builder: (context, libraryState) {
                  return ListView.builder(
                    controller: scrollCtrl,
                    itemCount: albums.length,
                    itemBuilder: (_, i) {
                      final album = albums[i];
                      final tracks = libraryState.tracks
                          .where((t) => t.albumId == album.id)
                          .toList();
                      return ListTile(
                        leading: const Icon(Icons.album),
                        title: Text(album.title),
                        subtitle: Text(
                          [
                            album.artist,
                            '${tracks.length} track${tracks.length == 1 ? '' : 's'}',
                          ].join(' · '),
                        ),
                        trailing: tracks.any((t) => t.pinned)
                            ? IconButton(
                                icon: const Icon(Icons.play_arrow),
                                onPressed: () {
                                  final playable =
                                      tracks.where((t) => t.pinned).toList();
                                  Get.find<PlayerService>().playQueue(
                                    playable,
                                    0,
                                    (t) => Get.find<IpfsLocalNode>()
                                        .streamUrl(t.cid, t.mimeType),
                                    albumsById: {album.id: album},
                                  );
                                  Navigator.pop(ctx);
                                },
                              )
                            : null,
                      );
                    },
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
