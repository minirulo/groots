import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get/get.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';
import 'package:path/path.dart' as p;

import '../../adapters/providers/album_provider.dart';
import '../../adapters/providers/library_provider.dart';
import '../../domain/models/album.dart';
import '../../service_layer/blocs/library/library_bloc.dart';
import '../../service_layer/blocs/library/library_event.dart';
import '../../service_layer/commands.dart';
import '../../service_layer/ipfs_local_node.dart';
import '../../service_layer/messagebus.dart';

// ── Data helpers ──────────────────────────────────────────────────────────────

class _ParsedEntry {
  final int? trackNumber;
  final String title;
  final String artist;
  const _ParsedEntry({this.trackNumber, required this.title, required this.artist});
}

_ParsedEntry _parseFilename(String filePath, {String fallbackArtist = ''}) {
  final filename = p.basenameWithoutExtension(filePath);

  // "01 - Title", "01. Title", "01 Title"
  final numMatch = RegExp(r'^(\d{1,3})[.\s\-]+(.+)$').firstMatch(filename);
  if (numMatch != null) {
    return _ParsedEntry(
      trackNumber: int.tryParse(numMatch.group(1)!),
      title: numMatch.group(2)!.trim(),
      artist: fallbackArtist,
    );
  }

  // "Artist - Title"
  final artMatch = RegExp(r'^(.+?)\s+-\s+(.+)$').firstMatch(filename);
  if (artMatch != null) {
    return _ParsedEntry(
      trackNumber: null,
      title: artMatch.group(2)!.trim(),
      artist: artMatch.group(1)!.trim(),
    );
  }

  return _ParsedEntry(trackNumber: null, title: filename, artist: fallbackArtist);
}

// ── Main widget ───────────────────────────────────────────────────────────────

class SyncView extends StatefulWidget {
  const SyncView({super.key});

  @override
  State<SyncView> createState() => _SyncViewState();
}

class _SyncViewState extends State<SyncView> {
  final List<_SyncEntry> _entries = [];
  String? _selectedDir;

  bool _searchingAlbum = false;
  bool _albumResolved = false;  // user has made a choice about the album
  String? _albumId;             // null = no album, or the resolved album_id
  Album? _resolvedAlbum;        // for display purposes

  bool _syncing = false;

  static const _audioExtensions = {'.mp3', '.flac', '.aac', '.ogg', '.wav', '.m4a', '.opus'};

  // ── Picking ─────────────────────────────────────────────────────────────────

  Future<void> _pickDirectory() async {
    final dir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select an album folder',
    );
    if (dir == null) return;

    final files = Directory(dir)
        .listSync(recursive: false)
        .whereType<File>()
        .where((f) => _audioExtensions.contains(p.extension(f.path).toLowerCase()))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    setState(() {
      _entries
        ..clear()
        ..addAll(files.map((f) => _SyncEntry(file: f)));
      _selectedDir = dir;
      _albumResolved = false;
      _albumId = null;
      _resolvedAlbum = null;
    });

    if (files.isNotEmpty) {
      await _findAndProposeAlbum();
    }
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select audio files',
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['mp3', 'flac', 'aac', 'ogg', 'wav', 'm4a', 'opus'],
    );
    if (result == null || result.files.isEmpty) return;

    final files = result.files
        .where((f) => f.path != null)
        .map((f) => File(f.path!))
        .toList();

    setState(() {
      _entries
        ..clear()
        ..addAll(files.map((f) => _SyncEntry(file: f)));
      _selectedDir = null;
      _albumResolved = false;
      _albumId = null;
      _resolvedAlbum = null;
    });

    _showCreateSheet();
  }

  // ── Album detection ─────────────────────────────────────────────────────────

  Future<void> _findAndProposeAlbum() async {
    setState(() => _searchingAlbum = true);
    Album? match;
    try {
      match = await _detectAlbum();
    } catch (_) {
      // Network error — fall through to create sheet
    } finally {
      if (mounted) setState(() => _searchingAlbum = false);
    }

    if (!mounted) return;

    if (match != null) {
      _showMatchSheet(match);
    } else {
      _showCreateSheet();
    }
  }

  /// Searches the catalogue for a matching album.
  /// Strategy: folder name first, then each track title, stopping at first hit.
  Future<Album?> _detectAlbum() async {
    final provider = Get.find<AlbumProvider>();
    final folderName = p.basename(_selectedDir!);

    // 1. Try the folder name as the album title
    final byFolder = await provider.searchAlbums(folderName);
    if (byFolder.isNotEmpty) return byFolder.first;

    // 2. Try each track title in order
    for (final entry in _entries.take(5)) {
      final parsed = _parseFilename(entry.file.path);
      if (parsed.title.length < 3) continue;
      final byTitle = await provider.searchAlbums(parsed.title);
      if (byTitle.isNotEmpty) return byTitle.first;
    }

    return null;
  }

  // ── Album bottom sheets ─────────────────────────────────────────────────────

  void _showMatchSheet(Album match) {
    showMaterialModalBottomSheet(
      context: context,
      builder: (ctx) => _AlbumMatchSheet(
        album: match,
        coverUrl: match.coverCid != null
            ? Get.find<AlbumProvider>().coverUrl(match.coverCid!)
            : null,
        onConfirm: () {
          Navigator.pop(ctx);
          _resolveAlbum(match.id, match);
        },
        onDecline: () {
          Navigator.pop(ctx);
          _showCreateSheet();
        },
      ),
    );
  }

  void _showCreateSheet() {
    final folderName = _selectedDir != null ? p.basename(_selectedDir!) : '';
    final artistHint = _entries.isNotEmpty
        ? _parseFilename(_entries.first.file.path).artist
        : '';

    showMaterialModalBottomSheet(
      context: context,
      builder: (ctx) => _AlbumCreateSheet(
        titleHint: folderName,
        artistHint: artistHint,
        onCreated: (albumId, album) {
          Navigator.pop(ctx);
          _resolveAlbum(albumId, album);
        },
        onSkip: () {
          Navigator.pop(ctx);
          setState(() {
            _albumId = null;
            _resolvedAlbum = null;
            _albumResolved = true;
          });
        },
      ),
    );
  }

  void _resolveAlbum(String albumId, Album album) {
    setState(() {
      _albumId = albumId;
      _resolvedAlbum = album;
      _albumResolved = true;
    });
  }

  // ── Syncing ─────────────────────────────────────────────────────────────────

  Future<void> _syncAll() async {
    setState(() => _syncing = true);
    final node = Get.find<IpfsLocalNode>();
    final useLocalNode = node.isRunning.value;

    for (final entry in _entries) {
      if (entry.status == _Status.done) continue;
      setState(() => entry.status = _Status.syncing);
      try {
        if (useLocalNode) {
          await _syncViaLocalNode(entry, node);
        } else {
          await _syncViaUpload(entry);
        }
        setState(() => entry.status = _Status.done);
      } catch (e) {
        setState(() {
          entry.status = _Status.error;
          entry.error = e.toString();
        });
      }
    }

    setState(() => _syncing = false);
    if (mounted) context.read<LibraryBloc>().add(LibraryLoadRequested());
  }

  /// Dev path: add to local Kubo node → register CID with API → API pins on server.
  Future<void> _syncViaLocalNode(_SyncEntry entry, IpfsLocalNode node) async {
    final bus = Get.find<Messagebus>();
    final albumArtist = _resolvedAlbum?.artist;
    final cid = await _ipfsAdd(entry.file);
    final parsed = _parseFilename(entry.file.path,
        fallbackArtist: albumArtist ?? 'Unknown');
    final stat = await entry.file.stat();

    final payload = <String, dynamic>{
      'cid': cid,
      'title': parsed.title,
      'artist': parsed.artist.isNotEmpty ? parsed.artist : (albumArtist ?? 'Unknown'),
      'duration_seconds': 0,
      'file_size_bytes': stat.size,
      'mime_type': _mimeFor(p.extension(entry.file.path)),
      if (_albumId != null) 'album': _resolvedAlbum?.title,
      if (_albumId != null) 'album_id': _albumId,
      if (parsed.trackNumber != null) 'track_number': parsed.trackNumber,
    };

    final trackId = await bus.handle<String>(AddTrackCommand(payload));
    await bus.handle(PinTrackCommand(trackId));
    node.pinAdd(cid).ignore();
  }

  /// Prod path: send raw bytes to POST /library/upload — server adds+pins in one shot.
  Future<void> _syncViaUpload(_SyncEntry entry) async {
    final provider = Get.find<LibraryProvider>();
    final albumArtist = _resolvedAlbum?.artist;
    final bytes = await entry.file.readAsBytes();
    final filename = p.basename(entry.file.path);
    final mimeType = _mimeFor(p.extension(entry.file.path));

    final result = await provider.uploadTrack(
      bytes: bytes,
      filename: filename,
      mimeType: mimeType,
    );

    // Assign to album if one was selected
    if (_albumId != null) {
      final parsed = _parseFilename(entry.file.path,
          fallbackArtist: albumArtist ?? 'Unknown');
      final bus = Get.find<Messagebus>();
      await bus.handle(AssignTrackToAlbumCommand(
        albumId: _albumId!,
        trackId: result['track_id'] as String,
        trackNumber: parsed.trackNumber,
      ));
    }
  }

  /// Adds [file] to the local Kubo node, copies it into MFS (so it appears in
  /// the Web UI Files tab), and returns the CID.
  ///
  /// Falls back to the Docker node on port 5001 when the local daemon is not
  /// running (e.g. first run before IpfsLocalNode has started).
  Future<String> _ipfsAdd(File file) async {
    final node = Get.find<IpfsLocalNode>();
    final apiPort = node.isRunning.value ? 5101 : 5001;
    final apiBase = 'http://127.0.0.1:$apiPort';

    final bytes = await file.readAsBytes();
    const boundary = '----soundnetboundary';

    // ── 1. ipfs add ────────────────────────────────────────────────────────
    final addReq = await HttpClient().postUrl(
      Uri.parse('$apiBase/api/v0/add?pin=true'),
    );
    addReq.headers.contentType =
        ContentType('multipart', 'form-data', parameters: {'boundary': boundary});
    final filename = p.basename(file.path);
    final header = '--$boundary\r\n'
        'Content-Disposition: form-data; name="file"; filename="$filename"\r\n'
        'Content-Type: application/octet-stream\r\n\r\n';
    addReq.add(header.codeUnits);
    addReq.add(bytes);
    addReq.add('\r\n--$boundary--\r\n'.codeUnits);
    final addRes = await addReq.close();
    final raw = await addRes.transform(const SystemEncoding().decoder).join();
    final line = raw.trim().split('\n').last;
    final match = RegExp(r'"Hash":"([^"]+)"').firstMatch(line);
    if (match == null) throw Exception('IPFS add failed: $line');
    final cid = match.group(1)!;

    // ── 2. Copy into MFS so it shows up in Web UI → Files tab ─────────────
    // /api/v0/files/cp?arg=/ipfs/<cid>&arg=/groots/<filename>
    // Creates /groots/ dir on first run (ignores error if it exists).
    try {
      final mkdirReq = await HttpClient().postUrl(
        Uri.parse('$apiBase/api/v0/files/mkdir?arg=%2Fgroots&parents=true'),
      );
      await (await mkdirReq.close()).drain<void>();

      final cpReq = await HttpClient().postUrl(
        Uri.parse(
          '$apiBase/api/v0/files/cp'
          '?arg=${Uri.encodeComponent('/ipfs/$cid')}'
          '&arg=${Uri.encodeComponent('/groots/$filename')}',
        ),
      );
      await (await cpReq.close()).drain<void>();
    } catch (_) {
      // MFS copy is best-effort — don't fail the upload if it errors
    }

    return cid;
  }

  String _mimeFor(String ext) => switch (ext.toLowerCase()) {
        '.mp3' => 'audio/mpeg',
        '.flac' => 'audio/flac',
        '.aac' => 'audio/aac',
        '.ogg' => 'audio/ogg',
        '.wav' => 'audio/wav',
        '.m4a' => 'audio/mp4',
        '.opus' => 'audio/opus',
        _ => 'audio/mpeg',
      };

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final canSync = _entries.isNotEmpty && _albumResolved && !_syncing;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Toolbar
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              FilledButton.icon(
                onPressed: _syncing ? null : _pickDirectory,
                icon: const Icon(Icons.folder_open),
                label: const Text('Select folder'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _syncing ? null : _pickFiles,
                icon: const Icon(Icons.audio_file),
                label: const Text('Select files'),
              ),
              const SizedBox(width: 12),
              if (_entries.isNotEmpty)
                FilledButton.icon(
                  onPressed: canSync ? _syncAll : null,
                  icon: const Icon(Icons.cloud_upload),
                  label: Text('Sync ${_entries.length} tracks'),
                ),
              if (_searchingAlbum) ...[
                const SizedBox(width: 12),
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                const Text('Searching for album…'),
              ],
              if (_syncing) ...[
                const SizedBox(width: 12),
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ],
          ),
        ),

        // Album resolution status bar
        if (_entries.isNotEmpty)
          _AlbumStatusBar(
            searchingAlbum: _searchingAlbum,
            albumResolved: _albumResolved,
            resolvedAlbum: _resolvedAlbum,
            onTap: _entries.isNotEmpty && !_syncing && !_searchingAlbum
                ? _showCreateSheet
                : null,
          ),

        // Track list
        Expanded(
          child: _entries.isEmpty
              ? const Center(
                  child: Text('Select an album folder to get started.'))
              : ListView.builder(
                  itemCount: _entries.length,
                  itemBuilder: (context, i) {
                    final e = _entries[i];
                    final parsed = _parseFilename(e.file.path);
                    final ext = p.extension(e.file.path).replaceFirst('.', '').toUpperCase();
                    final isPending = e.status == _Status.pending;
                    return ListTile(
                      leading: _StatusIcon(status: e.status),
                      title: Text(
                        parsed.title,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: e.error != null
                          ? Text(e.error!,
                              style: const TextStyle(color: Colors.red))
                          : parsed.trackNumber != null
                              ? Text('Track ${parsed.trackNumber}')
                              : null,
                      trailing: isPending && !_syncing
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(ext, style: Theme.of(context).textTheme.bodySmall),
                                const SizedBox(width: 4),
                                IconButton(
                                  icon: const Icon(Icons.close, size: 18),
                                  tooltip: 'Remove from list',
                                  onPressed: () => setState(() => _entries.removeAt(i)),
                                ),
                              ],
                            )
                          : Text(ext, style: Theme.of(context).textTheme.bodySmall),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ── Album status bar ──────────────────────────────────────────────────────────

class _AlbumStatusBar extends StatelessWidget {
  final bool searchingAlbum;
  final bool albumResolved;
  final Album? resolvedAlbum;
  final VoidCallback? onTap;

  const _AlbumStatusBar({
    required this.searchingAlbum,
    required this.albumResolved,
    required this.resolvedAlbum,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (searchingAlbum) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;

    Widget content;
    if (!albumResolved) {
      content = const SizedBox.shrink();
    } else if (resolvedAlbum != null) {
      final meta = [
        if (resolvedAlbum!.artist.isNotEmpty) resolvedAlbum!.artist,
        if (resolvedAlbum!.year != null) '${resolvedAlbum!.year}',
        if (resolvedAlbum!.recordingFormat != null) resolvedAlbum!.recordingFormat!,
      ].join(' · ');
      content = Row(
        children: [
          Icon(Icons.album, size: 18, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(resolvedAlbum!.title,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis),
                if (meta.isNotEmpty)
                  Text(meta,
                      style: Theme.of(context).textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          if (onTap != null)
            TextButton(onPressed: onTap, child: const Text('Change')),
        ],
      );
    } else {
      content = Row(
        children: [
          Icon(Icons.album_outlined, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Text('No album',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant)),
          const Spacer(),
          if (onTap != null)
            TextButton(onPressed: onTap, child: const Text('Set album')),
        ],
      );
    }

    return Container(
      color: scheme.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: content,
    );
  }
}

// ── Album match confirmation sheet ────────────────────────────────────────────

class _AlbumMatchSheet extends StatelessWidget {
  final Album album;
  final String? coverUrl;
  final VoidCallback onConfirm;
  final VoidCallback onDecline;

  const _AlbumMatchSheet({
    required this.album,
    this.coverUrl,
    required this.onConfirm,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final meta = [
      if (album.year != null) '${album.year}',
      if (album.recordingFormat != null) album.recordingFormat!,
      if (album.genre != null) album.genre!,
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Album found', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Does this match the folder you selected?',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              // Cover
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: coverUrl != null
                      ? Image.network(coverUrl!, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _CoverPlaceholder(scheme: scheme))
                      : _CoverPlaceholder(scheme: scheme),
                ),
              ),
              const SizedBox(width: 16),
              // Metadata
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
                    Text(album.artist,
                        style: Theme.of(context).textTheme.bodyMedium,
                        overflow: TextOverflow.ellipsis),
                    if (meta.isNotEmpty)
                      Text(meta,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onDecline,
                  child: const Text('No, create new'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: onConfirm,
                  child: const Text('Yes, that\'s it'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Album creation sheet ──────────────────────────────────────────────────────

class _AlbumCreateSheet extends StatefulWidget {
  final String titleHint;
  final String artistHint;
  final void Function(String albumId, Album album) onCreated;
  final VoidCallback onSkip;

  const _AlbumCreateSheet({
    required this.titleHint,
    required this.artistHint,
    required this.onCreated,
    required this.onSkip,
  });

  @override
  State<_AlbumCreateSheet> createState() => _AlbumCreateSheetState();
}

class _AlbumCreateSheetState extends State<_AlbumCreateSheet> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _artistCtrl;
  final TextEditingController _yearCtrl = TextEditingController();
  final TextEditingController _genreCtrl = TextEditingController();
  String? _selectedFormat;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.titleHint);
    _artistCtrl = TextEditingController(text: widget.artistHint);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _artistCtrl.dispose();
    _yearCtrl.dispose();
    _genreCtrl.dispose();
    super.dispose();
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
        if (_genreCtrl.text.isNotEmpty) 'genre': _genreCtrl.text,
        if (_selectedFormat != null) 'recording_format': _selectedFormat,
      });

      final album = Album(
        id: albumId,
        title: _titleCtrl.text,
        artist: _artistCtrl.text,
        year: int.tryParse(_yearCtrl.text),
        genre: _genreCtrl.text.isNotEmpty ? _genreCtrl.text : null,
        recordingFormat: _selectedFormat,
      );
      widget.onCreated(albumId, album);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create album: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Create album',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('Fill in the details for this album folder.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 20),
          TextField(
            controller: _titleCtrl,
            decoration: const InputDecoration(labelText: 'Title *', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _artistCtrl,
            decoration: const InputDecoration(labelText: 'Artist *', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _yearCtrl,
                  decoration: const InputDecoration(labelText: 'Year', border: OutlineInputBorder()),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _genreCtrl,
                  decoration: const InputDecoration(labelText: 'Genre', border: OutlineInputBorder()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _selectedFormat,
            decoration: const InputDecoration(labelText: 'Format', border: OutlineInputBorder()),
            items: recordingFormats
                .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                .toList(),
            onChanged: (v) => setState(() => _selectedFormat = v),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _creating ? null : widget.onSkip,
                  child: const Text('Sync without album'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _creating ||
                          _titleCtrl.text.isEmpty ||
                          _artistCtrl.text.isEmpty
                      ? null
                      : _create,
                  child: _creating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Create album'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Small shared widgets ──────────────────────────────────────────────────────

class _CoverPlaceholder extends StatelessWidget {
  final ColorScheme scheme;
  const _CoverPlaceholder({required this.scheme});

  @override
  Widget build(BuildContext context) => Container(
        color: scheme.surfaceContainerHighest,
        child: Icon(Icons.album, color: scheme.onSurfaceVariant),
      );
}

class _StatusIcon extends StatelessWidget {
  final _Status status;
  const _StatusIcon({required this.status});

  @override
  Widget build(BuildContext context) => Icon(
        switch (status) {
          _Status.pending => Icons.music_note_outlined,
          _Status.syncing => Icons.sync,
          _Status.done => Icons.check_circle_outline,
          _Status.error => Icons.error_outline,
        },
        color: switch (status) {
          _Status.done => Colors.green,
          _Status.error => Colors.red,
          _ => null,
        },
      );
}

// ── Models ────────────────────────────────────────────────────────────────────

enum _Status { pending, syncing, done, error }

class _SyncEntry {
  final File file;
  _Status status;
  String? error;
  _SyncEntry({required this.file}) : status = _Status.pending;
}
