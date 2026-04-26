import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../adapters/providers/album_provider.dart';
import '../../domain/models/album.dart';
import '../../domain/models/track.dart';
import '../../service_layer/blocs/admin/admin_bloc.dart';
import '../../service_layer/blocs/admin/admin_event.dart';
import '../../service_layer/blocs/admin/admin_state.dart';
import 'package:get/get.dart';

class AdminView extends StatefulWidget {
  const AdminView({super.key});

  @override
  State<AdminView> createState() => _AdminViewState();
}

class _AdminViewState extends State<AdminView>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    context.read<AdminBloc>().add(AdminCentralLibraryLoadRequested());
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _tabCtrl,
          tabs: const [
            Tab(icon: Icon(Icons.library_music), text: 'Central Library'),
            Tab(icon: Icon(Icons.album), text: 'Album Management'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabCtrl,
            children: const [
              _CentralLibraryTab(),
              _AlbumManagementTab(),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Central Library Tab ────────────────────────────────────────────────────────

class _CentralLibraryTab extends StatelessWidget {
  const _CentralLibraryTab();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<AdminBloc, AdminState>(
      listenWhen: (prev, curr) =>
          curr.status == AdminStatus.ingested || curr.status == AdminStatus.error,
      listener: (context, state) {
        final msg = state.status == AdminStatus.ingested
            ? (state.ingestMessage ?? 'Track ingested!')
            : (state.error ?? 'Error');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      },
      builder: (context, state) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  FilledButton.icon(
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Ingest Track'),
                    onPressed: state.status == AdminStatus.ingesting
                        ? null
                        : () => _pickAndIngest(context),
                  ),
                ],
              ),
            ),
            if (state.status == AdminStatus.loading ||
                state.status == AdminStatus.ingesting)
              const LinearProgressIndicator(),
            Expanded(
              child: state.centralLibrary.isEmpty
                  ? const Center(child: Text('Central library is empty.'))
                  : ListView.builder(
                      itemCount: state.centralLibrary.length,
                      itemBuilder: (_, i) =>
                          _CentralTrackTile(track: state.centralLibrary[i]),
                    ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _pickAndIngest(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) return;

    final mimeType = _mimeForExtension(file.extension ?? '');
    if (context.mounted) {
      context.read<AdminBloc>().add(AdminTrackIngestRequested(
            filename: file.name,
            content: file.bytes!,
            fileSizeBytes: file.size,
            mimeType: mimeType,
          ));
    }
  }

  String _mimeForExtension(String ext) {
    return switch (ext.toLowerCase()) {
      'mp3' => 'audio/mpeg',
      'flac' => 'audio/flac',
      'aac' => 'audio/aac',
      'ogg' => 'audio/ogg',
      'wav' => 'audio/wav',
      'm4a' => 'audio/mp4',
      'opus' => 'audio/opus',
      _ => 'audio/mpeg',
    };
  }
}

class _CentralTrackTile extends StatelessWidget {
  final Track track;
  const _CentralTrackTile({required this.track});

  @override
  Widget build(BuildContext context) {
    final sub = [
      track.artist,
      if (track.album != null) track.album!,
      if (track.year != null) '${track.year}',
    ].join(' · ');

    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.music_note)),
      title: Text(track.title),
      subtitle: Text(sub),
      trailing: Text(
        track.durationFormatted,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

// ── Album Management Tab ───────────────────────────────────────────────────────

class _AlbumManagementTab extends StatefulWidget {
  const _AlbumManagementTab();

  @override
  State<_AlbumManagementTab> createState() => _AlbumManagementTabState();
}

class _AlbumManagementTabState extends State<_AlbumManagementTab> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(
                    hintText: 'Search albums…',
                    prefixIcon: Icon(Icons.search),
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (q) {
                    if (q.trim().isNotEmpty) {
                      context
                          .read<AdminBloc>()
                          .add(AdminAlbumSearchRequested(q.trim()));
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('New'),
                onPressed: () => _showCreateDialog(context),
              ),
            ],
          ),
        ),
        Expanded(
          child: BlocBuilder<AdminBloc, AdminState>(
            builder: (context, state) {
              if (state.searchResults.isEmpty) {
                return const Center(
                  child: Text('Search for albums to manage them.'),
                );
              }
              return ListView.builder(
                itemCount: state.searchResults.length,
                itemBuilder: (_, i) =>
                    _AdminAlbumTile(album: state.searchResults[i]),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showCreateDialog(BuildContext context) {
    final titleCtrl = TextEditingController();
    final artistCtrl = TextEditingController();
    final yearCtrl = TextEditingController();
    final genreCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Album'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(labelText: 'Title *')),
              TextField(
                  controller: artistCtrl,
                  decoration: const InputDecoration(labelText: 'Artist *')),
              TextField(
                controller: yearCtrl,
                decoration: const InputDecoration(labelText: 'Year'),
                keyboardType: TextInputType.number,
              ),
              TextField(
                  controller: genreCtrl,
                  decoration: const InputDecoration(labelText: 'Genre')),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (titleCtrl.text.isNotEmpty && artistCtrl.text.isNotEmpty) {
                context.read<AdminBloc>().add(AdminAlbumCreateRequested(
                      title: titleCtrl.text,
                      artist: artistCtrl.text,
                      year: int.tryParse(yearCtrl.text),
                      genre: genreCtrl.text.isNotEmpty ? genreCtrl.text : null,
                    ));
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

class _AdminAlbumTile extends StatelessWidget {
  final Album album;
  const _AdminAlbumTile({required this.album});

  @override
  Widget build(BuildContext context) {
    final albumProvider = Get.find<AlbumProvider>();
    final coverUrl =
        album.coverCid != null ? albumProvider.coverUrl(album.coverCid!) : null;

    return ListTile(
      leading: coverUrl != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.network(coverUrl,
                  width: 48, height: 48, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.album, size: 48)),
            )
          : const Icon(Icons.album, size: 48),
      title: Text(album.title),
      subtitle: Text('${album.artist}${album.year != null ? ' · ${album.year}' : ''}'),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        tooltip: 'Delete album',
        onPressed: () => _confirmDelete(context),
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Album'),
        content: Text('Delete "${album.title}"? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () {
              context
                  .read<AdminBloc>()
                  .add(AdminAlbumDeleteRequested(album.id));
              Navigator.pop(ctx);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
