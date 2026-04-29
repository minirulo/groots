import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../adapters/providers/album_provider.dart';
import '../widgets/cover_scanner.dart';
import '../../adapters/providers/discogs_provider.dart';
import '../../domain/models/album.dart';
import '../../domain/models/discogs.dart';
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

enum AlbumSortBy { albumName, artistName, genre }

// ── Library view (album grid + drill-down track list) ─────────────────────────

class AlbumsView extends StatefulWidget {
  final Album? pendingAlbum;
  final VoidCallback? onPendingAlbumConsumed;
  final String? pendingTrackId;
  final VoidCallback? onPendingTrackIdConsumed;
  final AlbumSortBy sortBy;
  final ValueChanged<AlbumSortBy>? onSortChanged;
  const AlbumsView({
    super.key,
    this.pendingAlbum,
    this.onPendingAlbumConsumed,
    this.pendingTrackId,
    this.onPendingTrackIdConsumed,
    this.sortBy = AlbumSortBy.albumName,
    this.onSortChanged,
  });

  @override
  State<AlbumsView> createState() => _AlbumsViewState();
}

class _AlbumsViewState extends State<AlbumsView> {
  Album? _selectedAlbum;
  bool _showingUnknown = false;
  String? _scrollToTrackId;
  final ScrollController _trackScrollController = ScrollController();

  bool get _inDetail => _selectedAlbum != null || _showingUnknown;

  @override
  void initState() {
    super.initState();
    if (widget.pendingAlbum != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _selectAlbum(widget.pendingAlbum!);
          widget.onPendingAlbumConsumed?.call();
        }
      });
    }
  }

  @override
  void dispose() {
    _trackScrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(AlbumsView old) {
    super.didUpdateWidget(old);
    if (widget.pendingAlbum != null &&
        widget.pendingAlbum != old.pendingAlbum) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _selectAlbum(widget.pendingAlbum!);
          widget.onPendingAlbumConsumed?.call();
        }
      });
    }
    if (widget.pendingTrackId != null &&
        widget.pendingTrackId != old.pendingTrackId) {
      _scrollToTrackId = widget.pendingTrackId;
      widget.onPendingTrackIdConsumed?.call();
    }
  }

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

  List<MapEntry<String, List<Album>>> _buildGroups(List<Album> albums) {
    // ── Genre mode: group by full genre name ──────────────────────────────
    if (widget.sortBy == AlbumSortBy.genre) {
      final groups = <String, List<Album>>{};
      for (final album in albums) {
        final g = album.genre?.trim().isNotEmpty == true
            ? album.genre!.trim()
            : 'No genre';
        groups.putIfAbsent(g, () => []).add(album);
      }
      for (final list in groups.values) {
        list.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
      }
      return groups.entries.toList()..sort((a, b) {
        if (a.key == 'No genre') return 1;
        if (b.key == 'No genre') return -1;
        return a.key.toLowerCase().compareTo(b.key.toLowerCase());
      });
    }

    // ── Album / Artist mode: group by first letter ────────────────────────
    String key(Album a) =>
        (widget.sortBy == AlbumSortBy.albumName ? a.title : a.artist).trim();

    final sorted = [...albums]
      ..sort((a, b) => key(a).toLowerCase().compareTo(key(b).toLowerCase()));

    final groups = <String, List<Album>>{};
    for (final album in sorted) {
      final raw = key(album);
      final first = raw.isEmpty ? '#' : raw[0].toUpperCase();
      final letter = RegExp(r'[A-Z]').hasMatch(first) ? first : '#';
      groups.putIfAbsent(letter, () => []).add(album);
    }

    return groups.entries.toList()..sort((a, b) {
      if (a.key == '#') return 1;
      if (b.key == '#') return -1;
      return a.key.compareTo(b.key);
    });
  }

  Widget _buildGrid(
    BuildContext context,
    AlbumState albumState,
    LibraryState libraryState,
  ) {
    if (albumState.status == AlbumStatus.loading ||
        libraryState.status == LibraryStatus.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final unknownCount = libraryState.tracks
        .where((t) => t.albumId == null)
        .length;
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

    final groups = _buildGroups(albumState.albums);
    const gridDelegate = SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 200,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 0.78,
    );

    final isMobile = switch (Theme.of(context).platform) {
      TargetPlatform.iOS || TargetPlatform.android => true,
      _ => false,
    };

    return Column(
      children: [
        if (!isMobile)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Row(
              children: [
                SegmentedButton<AlbumSortBy>(
                  segments: const [
                    ButtonSegment(
                      value: AlbumSortBy.albumName,
                      label: Text('Album'),
                      icon: Icon(Icons.album_outlined, size: 16),
                    ),
                    ButtonSegment(
                      value: AlbumSortBy.artistName,
                      label: Text('Artist'),
                      icon: Icon(Icons.person_outline, size: 16),
                    ),
                    ButtonSegment(
                      value: AlbumSortBy.genre,
                      label: Text('Genre'),
                      icon: Icon(Icons.category_outlined, size: 16),
                    ),
                  ],
                  selected: {widget.sortBy},
                  onSelectionChanged: (s) =>
                      widget.onSortChanged?.call(s.first),
                  style: SegmentedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const Spacer(),
                FilledButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('New Album'),
                  onPressed: () => _showCreateDialog(context),
                ),
              ],
            ),
          ),
        Expanded(
          child: CustomScrollView(
            slivers: [
              for (final entry in groups) ...[
                SliverToBoxAdapter(child: _SectionHeader(label: entry.key)),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  sliver: SliverGrid(
                    gridDelegate: gridDelegate,
                    delegate: SliverChildBuilderDelegate(
                      (_, i) => _AlbumCard(
                        album: entry.value[i],
                        onTap: () => _selectAlbum(entry.value[i]),
                      ),
                      childCount: entry.value.length,
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 8)),
              ],
              if (unknownCount > 0) ...[
                const SliverToBoxAdapter(child: _SectionHeader(label: '?')),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  sliver: SliverGrid(
                    gridDelegate: gridDelegate,
                    delegate: SliverChildBuilderDelegate(
                      (_, __) => _UnknownCard(
                        trackCount: unknownCount,
                        onTap: _selectUnknown,
                      ),
                      childCount: 1,
                    ),
                  ),
                ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
            ],
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
    final isMobile = switch (Theme.of(context).platform) {
      TargetPlatform.iOS || TargetPlatform.android => true,
      _ => false,
    };
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
              if (!_showingUnknown) ...[
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: 'Edit album details',
                  onPressed: () => _showEditDialog(context, _selectedAlbum!),
                ),
                if (isAdmin && !isMobile)
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Delete album and all its tracks',
                    onPressed: () => showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Delete album?'),
                        content: Text(
                          '"${_selectedAlbum!.title}" and all its tracks will be permanently deleted.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () {
                              Navigator.pop(ctx);
                              context.read<AlbumBloc>().add(
                                AlbumDeleteRequested(_selectedAlbum!.id),
                              );
                              context.read<LibraryBloc>().add(
                                LibraryLoadRequested(),
                              );
                              _goBack();
                            },
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
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
              : _buildTrackList(context, tracks),
        ),
      ],
    );
  }

  Widget _buildTrackList(BuildContext context, List<Track> tracks) {
    if (_scrollToTrackId != null) {
      final targetId = _scrollToTrackId!;
      _scrollToTrackId = null;
      final idx = tracks.indexWhere((t) => t.id == targetId);
      if (idx > 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _trackScrollController.hasClients) {
            _trackScrollController.animateTo(
              idx * 72.0,
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOut,
            );
          }
        });
      }
    }

    final hasMultiDisc = tracks.any((t) => t.discNumber != null);
    final hasSides = tracks.any((t) => t.side != null);

    // Build a flat list of items: String = section header, Track = track tile.
    final items = <Object>[];

    if (!hasMultiDisc && !hasSides) {
      items.addAll(tracks);
    } else {
      void addSection(String label, List<Track> sectionTracks) {
        if (label.isNotEmpty) items.add(label);
        items.addAll(
          sectionTracks
            ..sort((a, b) =>
                (a.trackNumber ?? 999).compareTo(b.trackNumber ?? 999)),
        );
      }

      // Collect unique disc keys, sorted (null first so ungrouped tracks lead).
      final discKeys = ({...tracks.map((t) => t.discNumber)}.toList()
        ..sort((a, b) {
          if (a == null && b == null) return 0;
          if (a == null) return -1;
          if (b == null) return 1;
          return a.compareTo(b);
        }));

      for (final disc in discKeys) {
        final discTracks = tracks.where((t) => t.discNumber == disc).toList();

        if (!hasSides) {
          final discLabel = disc != null ? 'Disc $disc' : '';
          addSection(discLabel, discTracks);
        } else {
          final sideKeys = ({...discTracks.map((t) => t.side)}.toList()
            ..sort((a, b) {
              if (a == null && b == null) return 0;
              if (a == null) return -1;
              if (b == null) return 1;
              return a.compareTo(b);
            }));

          for (final side in sideKeys) {
            final sideTracks =
                discTracks.where((t) => t.side == side).toList();
            final parts = [
              if (disc != null) 'Disc $disc',
              if (side != null) 'Side $side',
            ];
            addSection(parts.join(' · '), sideTracks);
          }
        }
      }
    }

    return ListView.builder(
      controller: _trackScrollController,
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = items[i];
        if (item is String) {
          return _TrackSectionLabel(label: item);
        }
        final t = item as Track;
        final tIdx = tracks.indexOf(t);
        return TrackTile(
          track: t,
          showLibraryActions: true,
          onTap: t.pinned ? () => _playFrom(tracks, tIdx) : null,
          onPlay: () => _playFrom(tracks, tIdx),
          onPin: () =>
              context.read<LibraryBloc>().add(LibraryTrackPinRequested(t.id)),
          onDelete: () => context.read<LibraryBloc>().add(
            LibraryTrackRemoveRequested(t.id),
          ),
        );
      },
    );
  }

  void _playFrom(List<Track> tracks, int index) {
    final playable = tracks.where((t) => t.pinned).toList();
    final adjusted = playable.indexWhere((t) => t.id == tracks[index].id);
    if (adjusted < 0) return;
    final coverUrl = _selectedAlbum?.coverCid != null
        ? Get.find<AlbumProvider>().coverUrl(_selectedAlbum!.coverCid!)
        : null;
    Get.find<PlayerService>().playQueue(
      playable,
      adjusted,
      (t) => Get.find<IpfsLocalNode>().streamUrl(t.cid, t.mimeType),
      artUriBuilder: coverUrl != null ? (_) => coverUrl : null,
    );
  }

  void _showEditDialog(BuildContext context, Album album) {
    final genres = context.read<AlbumBloc>().state.genres;
    showDialog(
      context: context,
      builder: (ctx) => _AlbumEditDialog(
        album: album,
        genres: genres,
        onSaved: (updated) => setState(() => _selectedAlbum = updated),
      ),
    );
  }

  void _showCreateDialog(BuildContext context) {
    final genres = context.read<AlbumBloc>().state.genres;
    showDialog(
      context: context,
      builder: (_) => _AlbumCreateDialog(genres: genres),
    );
  }
}

// ── Alphabetical section header ───────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
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
                  ? Image.network(
                      coverUrl,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      errorBuilder: (_, __, ___) => const _AlbumPlaceholder(),
                    )
                  : const _AlbumPlaceholder(),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    album.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    album.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Row(
                    children: [
                      if (album.year != null)
                        Text(
                          '${album.year}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      if (album.year != null && album.recordingFormat != null)
                        Text(
                          ' · ',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      if (album.recordingFormat != null)
                        Text(
                          album.recordingFormat!,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                        ),
                    ],
                  ),
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
                child: Icon(
                  Icons.music_note,
                  size: 48,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Unknown',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '$trackCount track${trackCount == 1 ? '' : 's'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
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
                  ? Image.network(
                      coverUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const _AlbumPlaceholder(),
                    )
                  : const _AlbumPlaceholder(),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  album.title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (meta.isNotEmpty)
                  Text(
                    meta,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared ────────────────────────────────────────────────────────────────────

class _TrackSectionLabel extends StatelessWidget {
  final String label;
  const _TrackSectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _AlbumPlaceholder extends StatelessWidget {
  const _AlbumPlaceholder();

  @override
  Widget build(BuildContext context) => Container(
    color: Theme.of(context).colorScheme.surfaceContainerHigh,
    child: const Center(child: Icon(Icons.album, size: 48)),
  );
}

// ── Album edit dialog ─────────────────────────────────────────────────────────

class _AlbumEditDialog extends StatefulWidget {
  final Album album;
  final List<String> genres;
  final void Function(Album updated) onSaved;

  const _AlbumEditDialog({
    required this.album,
    required this.genres,
    required this.onSaved,
  });

  @override
  State<_AlbumEditDialog> createState() => _AlbumEditDialogState();
}

class _AlbumEditDialogState extends State<_AlbumEditDialog> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _artistCtrl;
  late final TextEditingController _yearCtrl;
  String? _selectedGenre;
  String? _selectedFormat;

  // null  = no pending change (keep current coverCid)
  // bytes = user picked a new image → upload on save
  Uint8List? _pendingCoverBytes;
  String? _pendingCoverMime;
  // true  = user explicitly removed the cover (future: needs delete endpoint)
  bool _coverRemoved = false;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.album.title);
    _artistCtrl = TextEditingController(text: widget.album.artist);
    _yearCtrl = TextEditingController(
      text: widget.album.year != null ? '${widget.album.year}' : '',
    );
    _selectedGenre = widget.album.genre;
    _selectedFormat = widget.album.recordingFormat;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _artistCtrl.dispose();
    _yearCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickCover() async {
    if (Platform.isAndroid || Platform.isIOS) {
      final result = await scanAlbumCover(context);
      if (result == null || !mounted) return;
      setState(() {
        _pendingCoverBytes = result.$1;
        _pendingCoverMime = result.$2;
        _coverRemoved = false;
      });
    } else {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      final path = result?.files.firstOrNull?.path;
      if (path == null || !mounted) return;
      final bytes = await File(path).readAsBytes();
      final ext = p.extension(path).toLowerCase();
      setState(() {
        _pendingCoverBytes = bytes;
        _pendingCoverMime = ext == '.png' ? 'image/png' : 'image/jpeg';
        _coverRemoved = false;
      });
    }
  }

  Future<void> _save() async {
    if (_titleCtrl.text.isEmpty || _artistCtrl.text.isEmpty) return;
    setState(() => _saving = true);
    try {
      final albumProvider = Get.find<AlbumProvider>();
      final albumBloc = context.read<AlbumBloc>();

      albumBloc.add(
        AlbumUpdateRequested(
          albumId: widget.album.id,
          title: _titleCtrl.text,
          artist: _artistCtrl.text,
          year: int.tryParse(_yearCtrl.text),
          genre: _selectedGenre,
          recordingFormat: _selectedFormat,
        ),
      );

      if (_pendingCoverBytes != null) {
        await albumProvider.uploadCover(
          widget.album.id,
          _pendingCoverBytes!,
          _pendingCoverMime ?? 'image/jpeg',
        );
      }

      widget.onSaved(
        Album(
          id: widget.album.id,
          title: _titleCtrl.text,
          artist: _artistCtrl.text,
          year: int.tryParse(_yearCtrl.text),
          genre: _selectedGenre,
          description: widget.album.description,
          coverCid: _coverRemoved ? null : widget.album.coverCid,
          recordingFormat: _selectedFormat,
          createdBy: widget.album.createdBy,
        ),
      );

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Save failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final currentCoverUrl = widget.album.coverCid != null && !_coverRemoved
        ? Get.find<AlbumProvider>().coverUrl(widget.album.coverCid!)
        : null;

    Widget coverWidget;
    if (_pendingCoverBytes != null) {
      coverWidget = Image.memory(_pendingCoverBytes!, fit: BoxFit.cover);
    } else if (currentCoverUrl != null) {
      coverWidget = Image.network(
        currentCoverUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _AlbumPlaceholder(),
      );
    } else {
      coverWidget = const _AlbumPlaceholder();
    }

    final hasCover =
        _pendingCoverBytes != null ||
        (currentCoverUrl != null && !_coverRemoved);

    return AlertDialog(
      title: const Text('Edit Album'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover row
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: _saving ? null : _pickCover,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 88,
                      height: 88,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          coverWidget,
                          Positioned(
                            right: 4,
                            bottom: 4,
                            child: Container(
                              decoration: BoxDecoration(
                                color: scheme.surface.withValues(alpha: 0.8),
                                shape: BoxShape.circle,
                              ),
                              padding: const EdgeInsets.all(4),
                              child: Icon(
                                Platform.isAndroid || Platform.isIOS
                                    ? Icons.camera_alt
                                    : Icons.edit,
                                size: 14,
                                color: scheme.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _titleCtrl,
                        decoration: const InputDecoration(labelText: 'Title *'),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _artistCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Artist *',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (hasCover)
              TextButton.icon(
                onPressed: _saving
                    ? null
                    : () => setState(() {
                        _pendingCoverBytes = null;
                        _pendingCoverMime = null;
                        _coverRemoved = true;
                      }),
                icon: const Icon(Icons.close, size: 14),
                label: const Text('Remove cover'),
                style: TextButton.styleFrom(
                  foregroundColor: scheme.onSurfaceVariant,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                ),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _yearCtrl,
              decoration: const InputDecoration(labelText: 'Year'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: widget.genres.contains(_selectedGenre)
                  ? _selectedGenre
                  : null,
              decoration: const InputDecoration(labelText: 'Genre'),
              items: widget.genres
                  .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                  .toList(),
              onChanged: _saving
                  ? null
                  : (v) => setState(() => _selectedGenre = v),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _selectedFormat,
              decoration: const InputDecoration(labelText: 'Format'),
              items: recordingFormats
                  .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                  .toList(),
              onChanged: _saving
                  ? null
                  : (v) => setState(() => _selectedFormat = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed:
              _saving || _titleCtrl.text.isEmpty || _artistCtrl.text.isEmpty
              ? null
              : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}

// ── Album create dialog ───────────────────────────────────────────────────────

class _AlbumCreateDialog extends StatefulWidget {
  final List<String> genres;
  const _AlbumCreateDialog({required this.genres});

  @override
  State<_AlbumCreateDialog> createState() => _AlbumCreateDialogState();
}

class _AlbumCreateDialogState extends State<_AlbumCreateDialog> {
  final _titleCtrl = TextEditingController();
  final _artistCtrl = TextEditingController();
  final _yearCtrl = TextEditingController();
  String? _selectedGenre;
  String? _selectedFormat;

  Uint8List? _coverBytes;
  String? _coverMime;
  bool _loadingCover = false;
  bool _creating = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _artistCtrl.dispose();
    _yearCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickCover() async {
    if (Platform.isAndroid || Platform.isIOS) {
      final result = await scanAlbumCover(context);
      if (result == null || !mounted) return;
      setState(() {
        _coverBytes = result.$1;
        _coverMime = result.$2;
      });
    } else {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      final path = result?.files.firstOrNull?.path;
      if (path == null || !mounted) return;
      final bytes = await File(path).readAsBytes();
      final ext = p.extension(path).toLowerCase();
      setState(() {
        _coverBytes = bytes;
        _coverMime = ext == '.png' ? 'image/png' : 'image/jpeg';
      });
    }
  }

  Future<void> _onDiscogsSelected(DiscogsReleaseSummary release) async {
    setState(() {
      _titleCtrl.text = release.title;
      _artistCtrl.text = release.artist;
      if (release.year != null) _yearCtrl.text = '${release.year}';
    });

    if (release.thumbUrl == null) return;
    setState(() => _loadingCover = true);
    try {
      final res = await http.get(Uri.parse(release.thumbUrl!));
      if (!mounted) return;
      if (res.statusCode == 200) {
        setState(() {
          _coverBytes = res.bodyBytes;
          _coverMime = res.headers['content-type'] ?? 'image/jpeg';
        });
      }
    } catch (_) {
      // Cover download is best-effort; proceed without it.
    } finally {
      if (mounted) setState(() => _loadingCover = false);
    }
  }

  Future<void> _create() async {
    if (_titleCtrl.text.isEmpty || _artistCtrl.text.isEmpty) return;
    setState(() => _creating = true);
    try {
      final provider = Get.find<AlbumProvider>();
      final albumId = await provider.createAlbum({
        'title': _titleCtrl.text,
        'artist': _artistCtrl.text,
        if (_yearCtrl.text.isNotEmpty) 'year': int.tryParse(_yearCtrl.text),
        if (_selectedGenre != null) 'genre': _selectedGenre,
        if (_selectedFormat != null) 'recording_format': _selectedFormat,
      });
      if (_coverBytes != null) {
        await provider.uploadCover(
          albumId,
          _coverBytes!,
          _coverMime ?? 'image/jpeg',
        );
      }
      if (mounted) {
        context.read<AlbumBloc>().add(AlbumLoadRequested());
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create album: $e'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _creating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Widget coverChild;
    if (_loadingCover) {
      coverChild = Container(
        color: scheme.surfaceContainerHighest,
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    } else if (_coverBytes != null) {
      coverChild = Image.memory(_coverBytes!, fit: BoxFit.cover);
    } else {
      coverChild = Container(
        color: scheme.surfaceContainerHighest,
        child: Icon(
          Icons.add_photo_alternate_outlined,
          color: scheme.onSurfaceVariant,
          size: 36,
        ),
      );
    }

    return AlertDialog(
      title: const Text('New Album'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover + title/artist row
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: _creating || _loadingCover ? null : _pickCover,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 88,
                      height: 88,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          coverChild,
                          if (!_loadingCover)
                            Positioned(
                              right: 4,
                              bottom: 4,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: scheme.surface.withValues(alpha: 0.8),
                                  shape: BoxShape.circle,
                                ),
                                padding: const EdgeInsets.all(4),
                                child: Icon(
                                  Icons.edit,
                                  size: 14,
                                  color: scheme.onSurface,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _titleCtrl,
                        decoration: const InputDecoration(labelText: 'Title *'),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _artistCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Artist *',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_coverBytes != null)
              TextButton.icon(
                onPressed: _creating
                    ? null
                    : () => setState(() {
                        _coverBytes = null;
                        _coverMime = null;
                      }),
                icon: const Icon(Icons.close, size: 14),
                label: const Text('Remove cover'),
                style: TextButton.styleFrom(
                  foregroundColor: scheme.onSurfaceVariant,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                ),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _creating
                  ? null
                  : () async {
                      final release = await showDialog<DiscogsReleaseSummary>(
                        context: context,
                        builder: (_) => const Dialog.fullscreen(
                          child: _DiscogsSearchDialog(),
                        ),
                      );
                      if (release != null) await _onDiscogsSelected(release);
                    },
              icon: const Icon(Icons.search, size: 18),
              label: const Text('Search'),
            ),
            const SizedBox(height: 4),
            const Divider(),
            const SizedBox(height: 4),
            TextField(
              controller: _yearCtrl,
              decoration: const InputDecoration(labelText: 'Year'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _selectedGenre,
              decoration: const InputDecoration(labelText: 'Genre'),
              items: widget.genres
                  .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                  .toList(),
              onChanged: _creating
                  ? null
                  : (v) => setState(() => _selectedGenre = v),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _selectedFormat,
              decoration: const InputDecoration(labelText: 'Format'),
              items: recordingFormats
                  .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                  .toList(),
              onChanged: _creating
                  ? null
                  : (v) => setState(() => _selectedFormat = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _creating ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed:
              _creating || _titleCtrl.text.isEmpty || _artistCtrl.text.isEmpty
              ? null
              : _create,
          child: _creating
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create'),
        ),
      ],
    );
  }
}

// ── Discogs search dialog (full-screen) ───────────────────────────────────────

class _DiscogsSearchDialog extends StatefulWidget {
  const _DiscogsSearchDialog();

  @override
  State<_DiscogsSearchDialog> createState() => _DiscogsSearchDialogState();
}

class _DiscogsSearchDialogState extends State<_DiscogsSearchDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  final _artistCtrl = TextEditingController();
  final _albumCtrl = TextEditingController();
  final _freeCtrl = TextEditingController();
  bool _searching = false;
  List<DiscogsReleaseSummary> _results = [];
  String? _searchError;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _artistCtrl.dispose();
    _albumCtrl.dispose();
    _freeCtrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() {
      _searching = true;
      _searchError = null;
      _results = [];
    });
    try {
      final provider = Get.find<DiscogsProvider>();
      final results = await switch (_tabCtrl.index) {
        0 => provider.search(
          artist: _artistCtrl.text.trim(),
          album: _albumCtrl.text.trim(),
        ),
        _ => provider.search(q: _freeCtrl.text.trim()),
      };
      if (mounted) setState(() => _results = results);
    } catch (e) {
      if (mounted) setState(() => _searchError = e.toString());
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Search'),
        leading: CloseButton(onPressed: () => Navigator.pop(context)),
        bottom: TabBar(
          controller: _tabCtrl,
          onTap: (_) => setState(() {
            _results = [];
            _searchError = null;
          }),
          tabs: const [
            Tab(text: 'Artist / Album'),
            Tab(text: 'Free text'),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(padding: const EdgeInsets.all(16), child: _buildSearchRow()),
          if (_searchError != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                _searchError!,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          Expanded(child: _buildResultsList()),
        ],
      ),
    );
  }

  Widget _buildSearchRow() {
    final input = _tabCtrl.index == 0
        ? Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _artistCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Artist',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _search(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _albumCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Album',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _search(),
                ),
              ),
            ],
          )
        : TextField(
            controller: _freeCtrl,
            decoration: const InputDecoration(
              labelText: 'Search Discogs…',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.search),
            ),
            onSubmitted: (_) => _search(),
          );

    return Row(
      children: [
        Expanded(child: input),
        const SizedBox(width: 12),
        FilledButton.icon(
          onPressed: _searching ? null : _search,
          icon: _searching
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.search),
          label: const Text('Search'),
        ),
      ],
    );
  }

  Widget _buildResultsList() {
    if (_results.isEmpty && !_searching) {
      return Center(
        child: Text(
          'Search to pre-fill album details.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8),
      itemCount: _results.length,
      itemBuilder: (_, i) {
        final r = _results[i];
        return ListTile(
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              width: 48,
              height: 48,
              child: r.thumbUrl != null
                  ? Image.network(
                      r.thumbUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.album, size: 32),
                    )
                  : const Icon(Icons.album, size: 32),
            ),
          ),
          title: Text(r.title, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            [
              r.artist,
              if (r.year != null) '${r.year}',
              if (r.label != null) r.label!,
            ].join(' · '),
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => Navigator.pop(context, r),
        );
      },
    );
  }
}
