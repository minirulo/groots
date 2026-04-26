import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get/get.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';

import '../../adapters/providers/library_provider.dart';
import '../../domain/models/music_source.dart';
import '../../service_layer/blocs/library/library_bloc.dart';
import '../../service_layer/blocs/library/library_event.dart';
import '../widgets/source_picker_sheet.dart';

class MobileUploadView extends StatefulWidget {
  const MobileUploadView({super.key});

  @override
  State<MobileUploadView> createState() => _MobileUploadViewState();
}

class _MobileUploadViewState extends State<MobileUploadView> {
  bool _uploading = false;
  String? _status;

  static const _audioExtensions = [
    'mp3',
    'flac',
    'aac',
    'ogg',
    'wav',
    'm4a',
    'opus',
  ];

  static const _mimeMap = {
    'mp3': 'audio/mpeg',
    'flac': 'audio/flac',
    'aac': 'audio/aac',
    'ogg': 'audio/ogg',
    'wav': 'audio/wav',
    'm4a': 'audio/mp4',
    'opus': 'audio/opus',
  };

  Future<void> _pickAndUpload() async {
    // Step 1: choose source
    final source = await showMaterialModalBottomSheet<MusicSource>(
      context: context,
      builder: (_) => const SourcePickerSheet(),
    );
    if (source == null) return;

    // Step 2: pick files
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _audioExtensions,
      allowMultiple: true,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    setState(() {
      _uploading = true;
      _status = 'Uploading ${result.files.length} track(s)…';
    });

    final provider = Get.find<LibraryProvider>();
    int done = 0;
    int failed = 0;
    int cdWeak = 0;

    for (final file in result.files) {
      if (file.bytes == null) continue;
      final ext = file.extension?.toLowerCase() ?? 'mp3';
      try {
        final res = await provider.uploadTrack(
          bytes: file.bytes!,
          filename: file.name,
          mimeType: _mimeMap[ext] ?? 'audio/mpeg',
          source: source.apiValue,
        );
        if (source == MusicSource.cd) {
          final cv = res['cd_verification'] as Map<String, dynamic>?;
          if (cv?['confidence'] == 'weak') cdWeak++;
        }
        done++;
        setState(() => _status = 'Uploaded $done / ${result.files.length}…');
      } catch (e) {
        failed++;
      }
    }

    // Refresh library
    if (mounted) context.read<LibraryBloc>().add(LibraryLoadRequested());

    setState(() {
      _uploading = false;
      _status = failed == 0
          ? '$done track(s) uploaded and pinned.'
          : '$done uploaded, $failed failed.';
    });

    // Warn if CD source had no verifiable CD signals
    if (mounted && source == MusicSource.cd && cdWeak > 0) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(
            Icons.warning_amber_rounded,
            size: 40,
            color: Colors.orange,
          ),
          title: const Text('No CD metadata found'),
          content: Text(
            '$cdWeak track${cdWeak == 1 ? '' : 's'} had no ISRC, MCN or ripper '
            'signature — the files do not appear to originate from a physical CD.\n\n'
            'Consider re-tagging your files or selecting "Other" as the source.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_upload_outlined, size: 64),
            const SizedBox(height: 16),
            const Text(
              'Upload your purchased music',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Files are sent to the server, added to IPFS and pinned automatically.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (_uploading)
              const CircularProgressIndicator()
            else
              FilledButton.icon(
                onPressed: _pickAndUpload,
                icon: const Icon(Icons.audio_file),
                label: const Text('Pick audio files'),
              ),
            if (_status != null) ...[
              const SizedBox(height: 16),
              Text(_status!, textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }
}
