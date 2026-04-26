import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get/get.dart';

import '../../adapters/providers/album_provider.dart';
import '../../domain/models/album.dart';
import '../../domain/models/track.dart';
import '../../service_layer/blocs/album/album_bloc.dart';
import '../../service_layer/blocs/album/album_event.dart';
import '../../service_layer/blocs/album/album_state.dart';
import '../../service_layer/blocs/authentication/authentication_bloc.dart';
import '../../service_layer/blocs/library/library_bloc.dart';
import '../../service_layer/blocs/library/library_event.dart';
import '../../service_layer/blocs/library/library_state.dart';
import '../../service_layer/ipfs_local_node.dart';
import '../../service_layer/player_service.dart';
import '../widgets/track_tile.dart';

// ── Library view (album grid + drill-down track list) ─────────────────────────

class AlbumsView extends StatefulWidget {
  const AlbumsView({super.key});

  @override
  State<AlbumsView> createState() => _AlbumsViewState();
}

class _AlbumsViewState extends State<AlbumsView> {
  /// Non-null while showing the track list for a real album.
  Album? _selectedAlbum;

  /// True while showing the "Unknown" bucket (tracks with no album).
  bool _showingUnknown = false;

  bool get _inDetail => _selectedAlbum != null || _showingUnknown;

  void _selectAlbum(Album a) => setState(() {
        _selectedAlbum = a;
        _showingUnknown = false;
      });

  void _selectUnknown() => setState(() {
        _selectedAlbum = null;
        _showingUnknown = true;
      });

  void _goBack() => setState(() {
        _selectedAlbum = null;
        _showingUnknown = false;
      });

  List<Track> _tracksFor(List<Track> all) {
    if (_showingUnknown) return all.where((t) => t.albumId == null).toList();
    return all.where((t) => t.albumId == _selectedAlbum!.id).toList()
      ..sort((a, b) => (a.trackNumber ?? 999).compareTo(b.trackNumber ?? 999));
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AlbumBloc, AlbumState>(
      builder: (context, albumState) => BlocBuilder<LibraryBloc, LibraryState>(
        builder: (context, libraryState) => _inDetail
            ? _buildDetail(context, albumState, libraryState)
            : _buildGrid(context, albumState, libraryState),
      ),
    );
  }

  // ── Album grid ──────────────────────────────────────────────────────────────

  Widget _buildGrid(
    BuildContext context,
    AlbumState albumState,
    LibraryState libraryState,
  ) {
    if (albumState.status == AlbumStatus.loading ||
        libraryState.status == LibraryStatus.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final unknownCount =
        libraryState.tracks.where((t) => t.albumId == null).length;
    final hasContent = albumState.albums.isNotEmpty || unknownCount > 0;

    if (!hasContent) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'No music yet.\nUse the Sync tab to add tracks.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Create Album'),
              onPressed: () => _showCreateDialog(context),
            ),
          ],
        ),
      );
    }

    final albums = albumState.albums;
    final extraTile = unknownCount > 0 ? 1 : 0;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              FilledButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('New Album'),
                onPressed: () => _showCreateDialog(context),
              ),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 200,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.78,
            ),
            itemCount: albums.length + extraTile,
            itemBuilder: (context, i) {
              if (i == albums.length) {
                return _UnknownCard(
                  trackCount: unknownCount,
                  onTap: _selectUnknown,
                );
              }
              return _AlbumCard(
                album: albums[i],
                onTap: () => _selectAlbum(albums[i]),
              );
            },
          ),
        ),
      ],
    );
  }

  // ── Album detail (track list) ───────────────────────────────────────────────

  Widget _buildDetail(
    BuildContext context,
    AlbumState albumState,
    LibraryState libraryState,
  ) {
    final isAdmin =
        context.read<AuthenticationBloc>().state.user?.isAdmin ?? false;
    final tracks = _tracksFor(libraryState.tracks);
    final albumTitle = _showingUnknown ? 'Unknown' : _selectedAlbum!.title;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Breadcrumb ────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 8, 0),
          child: Row(
            children: [
              TextButton.icon(
                icon: const Icon(Icons.chevron_left, size: 18),
                label: const Text('Library'),
                onPressed: _goBack,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const Text('›', style: TextStyle(color: Colors.grey)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  albumTitle,
                  style: Theme.of(context).textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isAdmin && !_showingUnknown)
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Delete album and all its tracks',
                  onPressed: () {
                    context
                        .read<AlbumBloc>()
                        .add(AlbumDeleteRequested(_selectedAlbum!.id));
                    context.read<LibraryBloc>().add(LibraryLoadRequested());
                    _goBack();
                  },
                ),
            ],
          ),
        ),

        // ── Album header ──────────────────────────────────────────────────
        if (!_showingUnknown) _AlbumHeader(album: _selectedAlbum!),

        const Divider(height: 1),

        // ── Track list ────────────────────────────────────────────────────
        Expanded(
          child: tracks.isEmpty
              ? const Center(child: Text('No tracks in this album.'))
              : ListView.builder(
                  itemCount: tracks.length,
                  itemBuilder: (context, i) {
                    final t = tracks[i];
                    return TrackTile(
                      track: t,
                      onPlay: () => _playFrom(tracks, i),
                      onPin: () => context
                          .read<LibraryBloc>()
                          .add(LibraryTrackPinRequested(t.id)),
                      onDelete: () => context
                          .read<LibraryBloc>()
                          .add(LibraryTrackRemoveRequested(t.id)),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _playFrom(List<Track> tracks, int index) {
    final playable = tracks.where((t) => t.pinned).toList();
    final adjusted = playable.indexWhere((t) => t.id == tracks[index].id);
    if (adjusted < 0) return;
    Get.find<PlayerService>().playQueue(
      playable,
      adjusted,
      (t) => Get.find<IpfsLocalNode>().streamUrl(t.cid, t.mimeType),
    );
  }

  void _showCreateDialog(BuildContext context) {
    final titleCtrl = TextEditingController();
    final artistCtrl = TextEditingController();
    final yearCtrl = TextEditingController();
    final genreCtrl = TextEditingController();
    String? selectedFormat;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('New Album'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: titleCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Title *')),
                TextField(
                    controller: artistCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Artist *')),
                TextField(
                    controller: yearCtrl,
                    decoration: const InputDecoration(labelText: 'Year'),
                    keyboardType: TextInputType.number),
                TextField(
                    controller: genreCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Genre')),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: selectedFormat,
                  decoration:
                      const InputDecoration(labelText: 'Format'),
                  items: recordingFormats
                      .map((f) =>
                          DropdownMenuItem(value: f, child: Text(f)))
                      .toList(),
                  onChanged: (v) => setState(() => selectedFormat = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (titleCtrl.text.isNotEmpty &&
                    artistCtrl.text.isNotEmpty) {
                  context.read<AlbumBloc>().add(AlbumCreateRequested(
                        title: titleCtrl.text,
                        artist: artistCtrl.text,
                        year: int.tryParse(yearCtrl.text),
                        genre: genreCtrl.text.isNotEmpty
                            ? genreCtrl.text
                            : null,
                        recordingFormat: selectedFormat,
                      ));
                  Navigator.pop(ctx);
                }
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Album grid cards ──────────────────────────────────────────────────────────

class _AlbumCard extends StatelessWidget {
  final Album album;
  final VoidCallback onTap;
  const _AlbumCard({required this.album, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final coverUrl = album.coverCid != null
        ? Get.find<AlbumProvider>().coverUrl(album.coverCid!)
        : null;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: coverUrl != null
                  ? Image.network(coverUrl,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      errorBuilder: (_, __, ___) =>
                          const _AlbumPlaceholder())
                  : const _AlbumPlaceholder(),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(album.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  Text(album.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall),
                  Row(children: [
                    if (album.year != null)
                      Text('${album.year}',
                          style: Theme.of(context).textTheme.bodySmall),
                    if (album.year != null &&
                        album.recordingFormat != null)
                      Text(' · ',
                          style: Theme.of(context).textTheme.bodySmall),
                    if (album.recordingFormat != null)
                      Text(album.recordingFormat!,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary)),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnknownCard extends StatelessWidget {
  final int trackCount;
  final VoidCallback onTap;
  const _UnknownCard({required this.trackCount, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                color: scheme.surfaceContainerHigh,
                width: double.infinity,
                child: Icon(Icons.music_note,
                    size: 48, color: scheme.onSurfaceVariant),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Unknown',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  Text('$trackCount track${trackCount == 1 ? '' : 's'}',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Album detail header ───────────────────────────────────────────────────────

class _AlbumHeader extends StatelessWidget {
  final Album album;
  const _AlbumHeader({required this.album});

  @override
  Widget build(BuildContext context) {
    final coverUrl = album.coverCid != null
        ? Get.find<AlbumProvider>().coverUrl(album.coverCid!)
        : null;

    final meta = [
      album.artist,
      if (album.year != null) '${album.year}',
      if (album.recordingFormat != null) album.recordingFormat!,
      if (album.genre != null) album.genre!,
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 64,
              height: 64,
              child: coverUrl != null
                  ? Image.network(coverUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const _AlbumPlaceholder())
                  : const _AlbumPlaceholder(),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(album.title,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis),
                if (meta.isNotEmpty)
                  Text(meta,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant),
                      overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared ────────────────────────────────────────────────────────────────────

class _AlbumPlaceholder extends StatelessWidget {
  const _AlbumPlaceholder();

  @override
  Widget build(BuildContext context) => Container(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        child: const Center(child: Icon(Icons.album, size: 48)),
      );
}
