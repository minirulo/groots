import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:file_picker/file_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../adapters/providers/album_provider.dart';
import '../../service_layer/vinyl_recorder.dart';
import '../../adapters/providers/discogs_provider.dart';
import '../../adapters/providers/library_provider.dart';
import '../../domain/models/album.dart';
import '../../domain/models/discogs.dart';
import '../widgets/waveform_editor.dart';

enum _VinylStep { discogs, record, edit }

class VinylSyncView extends StatefulWidget {
  const VinylSyncView({super.key});

  @override
  State<VinylSyncView> createState() => _VinylSyncViewState();
}

class _VinylSyncViewState extends State<VinylSyncView>
    with SingleTickerProviderStateMixin {
  _VinylStep _step = _VinylStep.discogs;

  // ── Discogs ───────────────────────────────────────────────────────────────────
  late final TabController _tabCtrl;
  final _barcodeCtrl = TextEditingController();
  final _artistCtrl = TextEditingController();
  final _albumCtrl = TextEditingController();
  final _freeCtrl = TextEditingController();
  bool _searching = false;
  List<DiscogsReleaseSummary> _results = [];
  String? _searchError;
  DiscogsReleaseSummary? _selectedSummary;
  DiscogsRelease? _release;
  bool _loadingRelease = false;
  String? _selectedSide;

  // ── Library album ─────────────────────────────────────────────────────────────
  final _librarySearchCtrl = TextEditingController();
  bool _librarySearching = false;
  List<Album> _libraryResults = [];
  Album? _existingAlbum;
  String _manualSide = 'A';
  int? _manualDisk;

  // ── Recording ─────────────────────────────────────────────────────────────────
  final VinylRecorder _recorder = VinylRecorder();
  List<InputDevice> _devices = [];
  InputDevice? _selectedDevice;
  bool _isRecording = false;
  bool _isLoadingFile = false;
  String? _recordingPath;
  Duration _elapsed = Duration.zero;
  Timer? _elapsedTimer;
  double _amplitude = -60.0;
  List<double> _samples = [];
  StreamSubscription<Amplitude>? _ampSub;

  // ── Edit ──────────────────────────────────────────────────────────────────────
  int _startTrim = 0;
  int? _endTrim;
  List<int> _splits = [];
  List<TextEditingController> _trackCtrls = [];
  bool _syncing = false;
  int _syncedCount = 0;
  int _totalTracks = 0;
  String? _syncError;

  // ── Playback ──────────────────────────────────────────────────────────────────
  AudioPlayer? _player;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<PlayerState>? _playerStateSub;
  double _playbackPos = 0.0; // 0.0 – 1.0 normalised over entire recording
  int? _playingSegment;
  Duration? _recordingDuration; // actual file duration from ffprobe

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
    _loadDevices();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _barcodeCtrl.dispose();
    _artistCtrl.dispose();
    _albumCtrl.dispose();
    _freeCtrl.dispose();
    _librarySearchCtrl.dispose();
    _elapsedTimer?.cancel();
    _ampSub?.cancel();
    _recorder.dispose();
    _positionSub?.cancel();
    _playerStateSub?.cancel();
    _player?.dispose();
    for (final c in _trackCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Discogs helpers ───────────────────────────────────────────────────────────

  Future<void> _search() async {
    setState(() {
      _searching = true;
      _searchError = null;
      _results = [];
    });
    try {
      final provider = Get.find<DiscogsProvider>();
      final tab = _tabCtrl.index;
      final results = await switch (tab) {
        0 => provider.search(
          barcode: _barcodeCtrl.text.trim(),
          format: 'Vinyl',
        ),
        1 => provider.search(
          artist: _artistCtrl.text.trim(),
          album: _albumCtrl.text.trim(),
          format: 'Vinyl',
        ),
        _ => provider.search(q: _freeCtrl.text.trim(), format: 'Vinyl'),
      };
      if (mounted) setState(() => _results = results);
    } catch (e) {
      if (mounted) setState(() => _searchError = e.toString());
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _selectRelease(DiscogsReleaseSummary summary) async {
    setState(() => _loadingRelease = true);
    try {
      final release = await Get.find<DiscogsProvider>().getRelease(summary.id);
      if (!mounted) return;

      final confirmed = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => _DiscogsDetailSheet(summary: summary, release: release),
      );

      if (confirmed == true && mounted) {
        setState(() {
          _selectedSummary = summary;
          _release = release;
          _selectedSide = release.availableSides.isNotEmpty
              ? release.availableSides.first
              : null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load release: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingRelease = false);
    }
  }

  Future<void> _searchLibrary() async {
    final q = _librarySearchCtrl.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _librarySearching = true;
      _libraryResults = [];
    });
    try {
      final results = await Get.find<AlbumProvider>().searchAlbums(q);
      if (mounted) setState(() => _libraryResults = results);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _librarySearching = false);
    }
  }

  // ── Disc / side resolution ────────────────────────────────────────────────────

  // Returns the side label to store on each uploaded track.
  // Discogs flow uses _selectedSide; existing-album flow uses _manualSide.
  String? _resolvedSide() {
    if (_release != null) return _selectedSide;
    if (_existingAlbum != null) return _manualSide;
    return null;
  }

  // Returns the disc number to store on each uploaded track.
  // null means single-disc album — no grouping header shown in the UI.
  // Discogs flow: single vinyl (≤2 sides) → null; double vinyl → 1 or 2 from side position.
  // Existing-album flow: driven by the user's manual disc picker.
  int? _resolvedDiscNumber() {
    if (_release != null && _selectedSide != null) {
      final sides = _release!.availableSides;
      if (sides.length <= 2) return null;
      final idx = sides.indexOf(_selectedSide!);
      return idx < 0 ? null : (idx ~/ 2) + 1;
    }
    if (_existingAlbum != null) return _manualDisk;
    return null;
  }

  // ── Genre helpers ─────────────────────────────────────────────────────────────

  static const _knownGenres = {
    'Blues',
    'Brass & Military',
    "Children's",
    'Classical',
    'Electronic',
    'Folk, World, & Country',
    'Funk / Soul',
    'Hip Hop',
    'Jazz',
    'Latin',
    'Non-Music',
    'Pop',
    'Reggae',
    'Rock',
    'Stage & Screen',
  };

  String? _matchGenre(List<String> discogsGenres) {
    for (final g in discogsGenres) {
      if (_knownGenres.contains(g)) return g;
    }
    return null;
  }

  // ── Recording helpers ─────────────────────────────────────────────────────────

  Widget _buildSidePicker() {
    final sides = _release!.availableSides;
    if (sides.length <= 1) {
      return Text(
        'Side ${sides.firstOrNull ?? '?'} · '
        '${((_selectedSide != null ? _release!.sides[_selectedSide] : null) ?? _release!.tracklist).length} tracks',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    }
    return Row(
      children: [
        Text('Side:', style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(width: 8),
        ...sides.map(
          (s) => Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: Text(s),
              selected: _selectedSide == s,
              onSelected: _isRecording
                  ? null
                  : (_) => setState(() => _selectedSide = s),
            ),
          ),
        ),
        if (_selectedSide != null) ...[
          const Spacer(),
          Text(
            '${((_release!.sides[_selectedSide]) ?? _release!.tracklist).length} tracks',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildManualSideDiskPicker() {
    const sides = ['A', 'B', 'C', 'D'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              Text('Side:', style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(width: 8),
              ...sides.map(
                (s) => Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(s),
                    selected: _manualSide == s,
                    onSelected: _isRecording
                        ? null
                        : (_) => setState(() => _manualSide = s),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Text('Disc:', style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(width: 8),
              ...List.generate(4, (i) => i + 1).map(
                (d) => Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text('$d'),
                    selected: _manualDisk == d,
                    onSelected: _isRecording
                        ? null
                        : (selected) =>
                            setState(() => _manualDisk = selected ? d : null),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _loadExistingFile() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['wav', 'flac', 'aiff', 'aif'],
    );
    final path = picked?.files.single.path;
    if (path == null || !mounted) return;

    setState(() => _isLoadingFile = true);
    try {
      final duration = await _recorder.probeInfo(path);
      final samples = await _recorder.generateWaveform(path, 1200);
      final splits = _autoSplitsFromDiscogs();
      final names = _defaultTrackNames(splits);
      for (final c in _trackCtrls) {
        c.dispose();
      }

      if (!mounted) return;
      setState(() {
        _recordingPath = path;
        _recordingDuration = duration;
        _samples = samples;
        _elapsed = duration ?? Duration.zero;
        _startTrim = 0;
        _endTrim = null;
        _splits = splits;
        _trackCtrls =
            names.map((n) => TextEditingController(text: n)).toList();
        _step = _VinylStep.edit;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load file: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingFile = false);
    }
  }

  Future<void> _loadDevices() async {
    try {
      final devices = await _recorder.listInputDevices();
      if (mounted) {
        setState(() {
          _devices = devices;
          _selectedDevice = devices.isNotEmpty ? devices.first : null;
        });
      }
    } catch (_) {
      // Proceed with system default
    }
  }

  Future<void> _startRecording() async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission denied')),
        );
      }
      return;
    }

    final dir = await getTemporaryDirectory();
    // WAV is universally readable by AVFoundation for preview playback;
    // ffmpeg converts each segment to FLAC at export time.
    final path =
        '${dir.path}/vinyl_${DateTime.now().millisecondsSinceEpoch}.wav';

    await _recorder.start(
      RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 48000,
        numChannels: 2,
        device: _selectedDevice,
      ),
      path: path,
    );

    _ampSub = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 100))
        .listen((amp) {
          if (!mounted) return;
          setState(() {
            _amplitude = amp.current;
            _samples.add(_normDb(amp.current));
          });
        });

    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsed += const Duration(seconds: 1));
    });

    setState(() {
      _isRecording = true;
      _recordingPath = path;
      _elapsed = Duration.zero;
      _samples = [];
      _amplitude = -60.0;
    });
  }

  Future<void> _stopRecording() async {
    await _ampSub?.cancel();
    _ampSub = null;
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
    await _recorder.stop();

    // Probe actual file duration so sample↔time mapping is exact.
    _recordingDuration = await _recorder.probeInfo(_recordingPath!);

    final splits = _autoSplitsFromDiscogs();
    final names = _defaultTrackNames(splits);
    for (final c in _trackCtrls) {
      c.dispose();
    }

    setState(() {
      _isRecording = false;
      _splits = splits;
      _trackCtrls = names.map((n) => TextEditingController(text: n)).toList();
      _step = _VinylStep.edit;
    });
  }

  double _normDb(double db) =>
      ((db - (-60.0)) / (0.0 - (-60.0))).clamp(0.0, 1.0);

  // Returns actual duration in seconds, falling back to sample count * 100 ms.
  double get _totalDurationSec =>
      (_recordingDuration?.inMilliseconds ?? _samples.length * 100) / 1000.0;

  List<int> _autoSplitsFromDiscogs() {
    if (_release == null || _samples.isEmpty) return [];
    final tracks =
        (_selectedSide != null ? _release!.sides[_selectedSide] : null) ??
        _release!.tracklist;
    if (tracks.length <= 1) return [];

    final splits = <int>[];
    double cumSec = 0;
    final totalSec = _totalDurationSec;
    for (int i = 0; i < tracks.length - 1; i++) {
      cumSec += (tracks[i].durationSeconds ?? 0).toDouble();
      final ratio = totalSec > 0 ? cumSec / totalSec : 0.0;
      splits.add(
        (ratio * _samples.length).round().clamp(1, _samples.length - 1),
      );
    }
    return splits..sort();
  }

  List<String> _defaultTrackNames(List<int> splits) {
    final tracks =
        (_selectedSide != null ? _release?.sides[_selectedSide] : null) ??
        _release?.tracklist ??
        [];
    final count = splits.length + 1;
    return List.generate(
      count,
      (i) => i < tracks.length ? tracks[i].title : 'Track ${i + 1}',
    );
  }

  // ── Playback helpers ──────────────────────────────────────────────────────────

  Future<void> _togglePlaySegment(int segIdx) async {
    if (_playingSegment == segIdx) {
      await _player?.stop();
      if (mounted) setState(() => _playingSegment = null);
      return;
    }

    final segments = _buildSegments();
    if (segIdx >= segments.length || _recordingPath == null) return;
    final (startSec, endSec) = segments[segIdx];

    _player ??= AudioPlayer();
    await _positionSub?.cancel();
    await _playerStateSub?.cancel();

    await _player!.setAudioSource(AudioSource.uri(Uri.file(_recordingPath!)));
    await _player!.seek(Duration(milliseconds: (startSec * 1000).round()));

    final endMs = (endSec * 1000).round();

    final totalMs = _totalDurationSec * 1000;
    _positionSub = _player!.positionStream.listen((pos) {
      if (!mounted) return;
      setState(() {
        _playbackPos = totalMs > 0
            ? (pos.inMilliseconds / totalMs).clamp(0.0, 1.0)
            : 0.0;
      });
      if (pos.inMilliseconds >= endMs) _player!.stop();
    });

    // Only flip back to "stopped" after we have actually started playing —
    // the player briefly sits in "ready + not playing" before play() fires.
    var hasStarted = false;
    _playerStateSub = _player!.playerStateStream.listen((state) {
      if (state.playing) {
        hasStarted = true;
      } else if (hasStarted) {
        if (mounted) setState(() => _playingSegment = null);
      }
    });

    setState(() => _playingSegment = segIdx);
    await _player!.play();
  }

  void _removeSplit(int splitIdx) {
    final ctrl = _trackCtrls[splitIdx + 1];
    final newSplits = List<int>.from(_splits)..removeAt(splitIdx);
    final newCtrls = List<TextEditingController>.from(_trackCtrls)
      ..removeAt(splitIdx + 1);
    ctrl.dispose();
    setState(() {
      _splits = newSplits;
      _trackCtrls = newCtrls;
      if (_playingSegment != null && _playingSegment! > splitIdx) {
        _playingSegment = _playingSegment! - 1;
      }
    });
  }

  // ── Edit helpers ──────────────────────────────────────────────────────────────

  void _onSplitsChanged(List<int> splits) {
    final newCount = splits.length + 1;
    final oldCount = _trackCtrls.length;
    setState(() {
      _splits = splits;
      if (newCount > oldCount) {
        _trackCtrls = List.generate(
          newCount,
          (i) => i < oldCount
              ? _trackCtrls[i]
              : TextEditingController(text: 'Track ${i + 1}'),
        );
      } else if (newCount < oldCount) {
        for (final c in _trackCtrls.sublist(newCount)) {
          c.dispose();
        }
        _trackCtrls = _trackCtrls.sublist(0, newCount);
      }
    });
  }

  void _autoSplitFromDiscogs() {
    final splits = _autoSplitsFromDiscogs();
    if (splits.isEmpty) return;
    final names = _defaultTrackNames(splits);
    for (final c in _trackCtrls) {
      c.dispose();
    }
    setState(() {
      _splits = splits;
      _trackCtrls = names.map((n) => TextEditingController(text: n)).toList();
    });
  }

  List<(double, double)> _buildSegments() {
    final totalSec = _totalDurationSec;
    final n = _samples.isNotEmpty ? _samples.length : 1;
    final bounds = [_startTrim, ..._splits, _endTrim ?? _samples.length];
    return List.generate(
      bounds.length - 1,
      (i) => (bounds[i] / n * totalSec, bounds[i + 1] / n * totalSec),
    );
  }

  Future<String> _exportSegment(
    int index,
    double startSec,
    double endSec,
  ) async {
    final dir = await getTemporaryDirectory();
    final outPath = '${dir.path}/vinyl_track_$index.flac';
    await _recorder.exportSegment(_recordingPath!, outPath, startSec, endSec);
    return outPath;
  }

  Future<void> _syncAll() async {
    final segments = _buildSegments();
    setState(() {
      _syncing = true;
      _syncedCount = 0;
      _totalTracks = segments.length;
      _syncError = null;
    });
    try {
      final albumProvider = Get.find<AlbumProvider>();
      final libraryProvider = Get.find<LibraryProvider>();

      // Resolve existing album or create one from Discogs metadata.
      String? albumId;
      bool albumIsNew = false;
      if (_release != null && _selectedSummary != null) {
        final q = '${_selectedSummary!.artist} ${_selectedSummary!.title}';
        final existing = await albumProvider.searchAlbums(q);
        if (existing.isNotEmpty) {
          albumId = existing.first.id;
        } else {
          final genre = _matchGenre(_release!.genres);
          albumId = await albumProvider.createAlbum({
            'title': _selectedSummary!.title,
            'artist': _selectedSummary!.artist,
            if (_selectedSummary!.year != null) 'year': _selectedSummary!.year,
            'recording_format': 'LP',
            if (genre != null) 'genre': genre,
          });
          albumIsNew = true;
        }
      }

      for (int i = 0; i < segments.length; i++) {
        final (start, end) = segments[i];
        final outPath = await _exportSegment(i, start, end);
        final bytes = await File(outPath).readAsBytes();
        final rawName = _trackCtrls[i].text
            .trim()
            .replaceAll(RegExp(r'[^\w\s\-]'), '')
            .trim();
        final filename = '${rawName.isEmpty ? 'track_${i + 1}' : rawName}.flac';
        final trackName = _trackCtrls[i].text.trim();
        final result = await libraryProvider.uploadTrack(
          bytes: bytes,
          filename: filename,
          mimeType: 'audio/flac',
          source: 'vinyl',
          hintArtist: _selectedSummary?.artist,
          hintTitle: trackName.isNotEmpty ? trackName : null,
          hintAlbum: _selectedSummary?.title,
          hintYear: _selectedSummary?.year,
          hintTrackNumber: i + 1,
        );
        final trackId = result['track_id'] as String;

        if (albumId != null) {
          await albumProvider.assignTrack(
            albumId,
            trackId,
            trackNumber: i + 1,
            discNumber: _resolvedDiscNumber(),
            side: _resolvedSide(),
          );
        }

        // Pin to cluster — this triggers mfs_copy which makes the file
        // visible in the IPFS cluster webui.
        await libraryProvider.pinTrack(trackId);

        await File(outPath).delete().catchError((_) => File(outPath));
        if (mounted) setState(() => _syncedCount = i + 1);
      }

      // Upload Discogs cover for newly created albums.
      if (albumIsNew && albumId != null) {
        final coverUrl = _release?.coverUrl;
        if (coverUrl != null) {
          try {
            final response = await http.get(Uri.parse(coverUrl));
            if (response.statusCode == 200) {
              final mime = response.headers['content-type'] ?? 'image/jpeg';
              await albumProvider.uploadCover(
                albumId,
                Uint8List.fromList(response.bodyBytes),
                mime,
              );
            }
          } catch (_) {
            // Cover upload is best-effort — don't fail the whole sync.
          }
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'No cover found — you can add one later from the album view.',
              ),
            ),
          );
        }
      }

      Album? syncedAlbum;
      if (albumId != null) {
        if (_existingAlbum != null) {
          syncedAlbum = _existingAlbum;
        } else if (_selectedSummary != null) {
          syncedAlbum = Album(
            id: albumId,
            title: _selectedSummary!.title,
            artist: _selectedSummary!.artist,
            year: _selectedSummary!.year,
            genre: _matchGenre(_release?.genres ?? []),
            recordingFormat: 'LP',
          );
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${segments.length} track${segments.length == 1 ? '' : 's'} synced.',
            ),
          ),
        );
        Navigator.of(context).pop(syncedAlbum);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _syncing = false;
          _syncError = e.toString();
        });
      }
    }
  }

  // ── Navigation ────────────────────────────────────────────────────────────────

  Future<void> _goBack() async {
    switch (_step) {
      case _VinylStep.discogs:
        if (mounted) Navigator.of(context).pop();
      case _VinylStep.record:
        if (_isRecording) return; // disallow while recording
        setState(() => _step = _VinylStep.discogs);
      case _VinylStep.edit:
        await _reRecord();
    }
  }

  /// Return to the Record step, discarding the current take but keeping Discogs data.
  Future<void> _reRecord() async {
    await _player?.stop();
    await _positionSub?.cancel();
    await _playerStateSub?.cancel();
    _positionSub = null;
    _playerStateSub = null;
    for (final c in _trackCtrls) {
      c.dispose();
    }
    setState(() {
      _playingSegment = null;
      _playbackPos = 0.0;
      _recordingPath = null;
      _recordingDuration = null;
      _samples = [];
      _amplitude = -60.0;
      _elapsed = Duration.zero;
      _startTrim = 0;
      _endTrim = null;
      _splits = [];
      _trackCtrls = [];
      _step = _VinylStep.record;
    });
  }

  // ── Build ──────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goBack();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Vinyl Sync'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _isRecording ? null : _goBack,
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(40),
            child: _StepIndicator(step: _step),
          ),
        ),
        body: switch (_step) {
          _VinylStep.discogs => _buildDiscogsStep(),
          _VinylStep.record => _buildRecordStep(),
          _VinylStep.edit => _buildEditStep(),
        },
      ),
    );
  }

  // ── Step 1: Discogs ───────────────────────────────────────────────────────────

  Widget _buildDiscogsStep() {
    final isLibraryTab = _tabCtrl.index == 3;
    return Column(
      children: [
        TabBar(
          controller: _tabCtrl,
          onTap: (_) => setState(() {
            _results = [];
            _searchError = null;
            _libraryResults = [];
          }),
          tabs: const [
            Tab(text: 'Barcode'),
            Tab(text: 'Artist / Album'),
            Tab(text: 'Free text'),
            Tab(text: 'My Library'),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: isLibraryTab ? _buildLibrarySearchRow() : _buildSearchRow(),
        ),
        if (_searchError != null && !isLibraryTab)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              _searchError!,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        Expanded(
          child: isLibraryTab
              ? _buildLibraryResultsList()
              : _buildResultsList(),
        ),
        if (_existingAlbum != null)
          _buildExistingAlbumBar()
        else if (_selectedSummary != null && _release != null)
          _buildReleaseBar(),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              OutlinedButton(
                onPressed: () => setState(() => _step = _VinylStep.record),
                child: const Text('Skip lookup'),
              ),
              const Spacer(),
              if (_existingAlbum != null ||
                  (_selectedSummary != null && _release != null))
                FilledButton(
                  onPressed: () => setState(() => _step = _VinylStep.record),
                  child: const Text('Next: Record'),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSearchRow() {
    Widget input;
    if (_tabCtrl.index == 1) {
      input = Row(
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
      );
    } else {
      final ctrl = _tabCtrl.index == 0 ? _barcodeCtrl : _freeCtrl;
      final label = _tabCtrl.index == 0 ? 'Barcode' : 'Search…';
      final icon = _tabCtrl.index == 0 ? Icons.qr_code : Icons.search;
      input = TextField(
        controller: ctrl,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          prefixIcon: Icon(icon),
        ),
        onSubmitted: (_) => _search(),
      );
    }

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
          'Search to find your vinyl release.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8),
      itemCount: _results.length,
      itemBuilder: (_, i) {
        final r = _results[i];
        final isSelected = _selectedSummary?.id == r.id;
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
          selected: isSelected,
          trailing: isSelected
              ? (_loadingRelease
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle, color: Colors.green))
              : null,
          onTap: _loadingRelease ? null : () => _selectRelease(r),
        );
      },
    );
  }

  Widget _buildReleaseBar() {
    final sides = _release!.availableSides;
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.album, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${_selectedSummary!.artist} – ${_selectedSummary!.title}',
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          if (sides.length > 1) ...[
            const SizedBox(width: 8),
            const Text('Side:'),
            const SizedBox(width: 4),
            DropdownButton<String>(
              value: _selectedSide,
              underline: const SizedBox(),
              items: sides
                  .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                  .toList(),
              onChanged: (v) => setState(() => _selectedSide = v),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLibrarySearchRow() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _librarySearchCtrl,
            decoration: const InputDecoration(
              labelText: 'Search your library…',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.search),
            ),
            onSubmitted: (_) => _searchLibrary(),
          ),
        ),
        const SizedBox(width: 12),
        FilledButton.icon(
          onPressed: _librarySearching ? null : _searchLibrary,
          icon: _librarySearching
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

  Widget _buildLibraryResultsList() {
    if (_libraryResults.isEmpty && !_librarySearching) {
      return Center(
        child: Text(
          'Search your library to select an existing album.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8),
      itemCount: _libraryResults.length,
      itemBuilder: (_, i) {
        final album = _libraryResults[i];
        final isSelected = _existingAlbum?.id == album.id;
        final meta = [
          if (album.artist.isNotEmpty) album.artist,
          if (album.year != null) '${album.year}',
          if (album.recordingFormat != null) album.recordingFormat!,
        ].join(' · ');
        return ListTile(
          leading: const Icon(Icons.album),
          title: Text(album.title, overflow: TextOverflow.ellipsis),
          subtitle: meta.isNotEmpty
              ? Text(meta, overflow: TextOverflow.ellipsis)
              : null,
          selected: isSelected,
          trailing: isSelected
              ? const Icon(Icons.check_circle, color: Colors.green)
              : null,
          onTap: () => setState(() {
            _existingAlbum = album;
            _selectedSummary = null;
            _release = null;
          }),
        );
      },
    );
  }

  Widget _buildExistingAlbumBar() {
    const sides = ['A', 'B', 'C', 'D'];
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.album, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${_existingAlbum!.artist} – ${_existingAlbum!.title}',
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              TextButton(
                onPressed: () => setState(() => _existingAlbum = null),
                child: const Text('Change'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                const Text('Side: '),
                const SizedBox(width: 6),
                ...sides.map(
                  (s) => Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: ChoiceChip(
                      label: Text(s),
                      selected: _manualSide == s,
                      onSelected: (_) => setState(() => _manualSide = s),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                const Text('Disc: '),
                const SizedBox(width: 6),
                ...List.generate(4, (i) => i + 1).map(
                  (d) => Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: ChoiceChip(
                      label: Text('$d'),
                      selected: _manualDisk == d,
                      onSelected: (selected) =>
                          setState(() => _manualDisk = selected ? d : null),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Step 2: Record ────────────────────────────────────────────────────────────

  Widget _buildRecordStep() {
    final minutes = _elapsed.inMinutes.toString().padLeft(2, '0');
    final seconds = (_elapsed.inSeconds % 60).toString().padLeft(2, '0');
    final ampNorm = _normDb(_amplitude);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Device picker
          if (_devices.isNotEmpty) ...[
            DropdownButtonFormField<InputDevice>(
              decoration: const InputDecoration(
                labelText: 'Audio input',
                border: OutlineInputBorder(),
              ),
              initialValue: _selectedDevice,
              items: _devices
                  .map((d) => DropdownMenuItem(value: d, child: Text(d.label)))
                  .toList(),
              onChanged: _isRecording
                  ? null
                  : (v) => setState(() => _selectedDevice = v),
            ),
            const SizedBox(height: 16),
          ],

          // Side / disk picker — Discogs flow
          if (_release != null) ...[
            _buildSidePicker(),
            const SizedBox(height: 16),
          ],

          // Side / disk picker — existing album flow
          if (_existingAlbum != null) ...[
            _buildManualSideDiskPicker(),
            const SizedBox(height: 16),
          ],

          // VU meter
          Text(
            'Level',
            style: Theme.of(context).textTheme.labelMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          _VuMeter(amplitude: ampNorm),
          const SizedBox(height: 32),

          // Elapsed timer
          Text(
            '$minutes:$seconds',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.displaySmall,
          ),
          const SizedBox(height: 8),
          Text(
            '${_samples.length} samples',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),

          const Spacer(),

          // Record / Stop
          Center(
            child: _isRecording
                ? FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: Colors.red),
                    onPressed: _stopRecording,
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop recording'),
                  )
                : FilledButton.icon(
                    onPressed: _startRecording,
                    icon: const Icon(Icons.fiber_manual_record),
                    label: const Text('Start recording'),
                  ),
          ),
          const SizedBox(height: 12),
          Center(
            child: OutlinedButton.icon(
              onPressed: _isRecording || _isLoadingFile ? null : _loadExistingFile,
              icon: _isLoadingFile
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.folder_open),
              label: Text(_isLoadingFile ? 'Loading…' : 'Load existing recording'),
            ),
          ),
        ],
      ),
    );
  }

  // ── Step 3: Edit ──────────────────────────────────────────────────────────────

  Widget _buildEditStep() {
    final segments = _buildSegments();
    final hasDiscogs = _release != null;

    return Column(
      children: [
        // Waveform editor
        Padding(
          padding: const EdgeInsets.all(16),
          child: WaveformEditor(
            samples: _samples,
            startTrim: _startTrim,
            onStartTrimChanged: (v) => setState(() => _startTrim = v),
            endTrim: _endTrim,
            onEndTrimChanged: (v) => setState(() => _endTrim = v),
            splits: _splits,
            onSplitsChanged: _onSplitsChanged,
            playbackPosition: _playingSegment != null ? _playbackPos : null,
          ),
        ),

        // Toolbar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              if (hasDiscogs)
                OutlinedButton.icon(
                  onPressed: _autoSplitFromDiscogs,
                  icon: const Icon(Icons.auto_fix_high, size: 16),
                  label: const Text('Auto-split'),
                ),
              const Spacer(),
              Text(
                '${segments.length} track${segments.length == 1 ? '' : 's'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),

        const SizedBox(height: 8),
        const Divider(height: 1),

        // Track list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: segments.length,
            itemBuilder: (_, i) {
              final (startSec, endSec) = segments[i];
              final durSec = (endSec - startSec).round();
              final mins = durSec ~/ 60;
              final secs = (durSec % 60).toString().padLeft(2, '0');
              final isPlaying = _playingSegment == i;
              return ListTile(
                leading: CircleAvatar(
                  radius: 14,
                  child: Text('${i + 1}', style: const TextStyle(fontSize: 11)),
                ),
                title: TextField(
                  controller: _trackCtrls[i],
                  decoration: const InputDecoration(
                    hintText: 'Track name',
                    border: UnderlineInputBorder(),
                    isDense: true,
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$mins:$secs',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(width: 4),
                    // Play / stop segment
                    IconButton(
                      iconSize: 20,
                      visualDensity: VisualDensity.compact,
                      tooltip: isPlaying ? 'Stop' : 'Preview track',
                      icon: Icon(
                        isPlaying
                            ? Icons.stop_circle_outlined
                            : Icons.play_circle_outline,
                        color: isPlaying
                            ? Theme.of(context).colorScheme.tertiary
                            : null,
                      ),
                      onPressed: _recordingPath != null
                          ? () => _togglePlaySegment(i)
                          : null,
                    ),
                    // Remove the split that begins this track (not for track 0)
                    if (i > 0)
                      IconButton(
                        iconSize: 20,
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Remove split',
                        icon: Icon(
                          Icons.remove_circle_outline,
                          color: Colors.red.shade300,
                        ),
                        onPressed: () => _removeSplit(i - 1),
                      ),
                  ],
                ),
              );
            },
          ),
        ),

        if (_syncError != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              _syncError!,
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
          ),

        // Bottom bar
        Padding(
          padding: const EdgeInsets.all(16),
          child: _syncing
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LinearProgressIndicator(
                      value: _totalTracks > 0
                          ? _syncedCount / _totalTracks
                          : null,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Syncing track $_syncedCount of $_totalTracks…',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                )
              : Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _reRecord,
                      icon: const Icon(Icons.fiber_manual_record, size: 16),
                      label: const Text('Re-record'),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: _recordingPath != null ? _syncAll : null,
                      icon: const Icon(Icons.cloud_upload),
                      label: Text(
                        'Sync ${segments.length} track${segments.length == 1 ? '' : 's'}',
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

// ── Step indicator ────────────────────────────────────────────────────────────

class _StepIndicator extends StatelessWidget {
  final _VinylStep step;
  const _StepIndicator({required this.step});

  static const _labels = ['Search', 'Record', 'Edit'];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final current = step.index;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
      child: Row(
        children: List.generate(_labels.length * 2 - 1, (i) {
          if (i.isOdd) {
            final done = i ~/ 2 < current;
            return Expanded(
              child: Divider(
                color: done ? scheme.primary : scheme.outlineVariant,
                thickness: 1.5,
              ),
            );
          }
          final idx = i ~/ 2;
          final done = idx < current;
          final active = idx == current;
          final bg = done || active
              ? scheme.primary
              : scheme.surfaceContainerHighest;
          final fg = done || active
              ? scheme.onPrimary
              : scheme.onSurfaceVariant;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 11,
                backgroundColor: bg,
                child: done
                    ? Icon(Icons.check, size: 12, color: fg)
                    : Text(
                        '${idx + 1}',
                        style: TextStyle(fontSize: 10, color: fg),
                      ),
              ),
              const SizedBox(height: 2),
              Text(
                _labels[idx],
                style: TextStyle(
                  fontSize: 9,
                  color: active ? scheme.primary : scheme.onSurfaceVariant,
                  fontWeight: active ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}

// ── VU meter ──────────────────────────────────────────────────────────────────

class _VuMeter extends StatelessWidget {
  final double amplitude; // 0.0 – 1.0
  const _VuMeter({required this.amplitude});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 20,
        child: CustomPaint(painter: _VuPainter(amplitude: amplitude)),
      ),
    );
  }
}

class _VuPainter extends CustomPainter {
  final double amplitude;
  const _VuPainter({required this.amplitude});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFF1A1A2E),
    );

    if (amplitude > 0) {
      final filled = size.width * amplitude;
      canvas.drawRect(
        Rect.fromLTWH(0, 0, filled, size.height),
        Paint()
          ..shader = LinearGradient(
            colors: [
              Colors.green.shade600,
              Colors.green.shade400,
              Colors.yellow.shade600,
              Colors.red.shade600,
            ],
            stops: const [0.0, 0.6, 0.8, 1.0],
          ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
      );
    }

    // Tick marks at 10% intervals
    final tickPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.15)
      ..strokeWidth = 1;
    for (int i = 1; i < 10; i++) {
      final x = size.width * i / 10;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), tickPaint);
    }
  }

  @override
  bool shouldRepaint(_VuPainter old) => old.amplitude != amplitude;
}

// ── Discogs release detail sheet ──────────────────────────────────────────────

class _DiscogsDetailSheet extends StatefulWidget {
  final DiscogsReleaseSummary summary;
  final DiscogsRelease release;

  const _DiscogsDetailSheet({required this.summary, required this.release});

  @override
  State<_DiscogsDetailSheet> createState() => _DiscogsDetailSheetState();
}

class _DiscogsDetailSheetState extends State<_DiscogsDetailSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    final sides = widget.release.availableSides;
    _tabs = TabController(
      length: sides.isNotEmpty ? sides.length : 1,
      vsync: this,
    );
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final release = widget.release;
    final sides = release.availableSides;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (_, scrollCtrl) => Column(
        children: [
          // drag handle
          const SizedBox(height: 8),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Cover + metadata
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Cover image
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    width: 100,
                    height: 100,
                    child: release.coverUrl != null
                        ? Image.network(
                            release.coverUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const Icon(Icons.album, size: 48),
                          )
                        : const Icon(Icons.album, size: 48),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        release.title,
                        style: Theme.of(context).textTheme.titleMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        release.artist,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (release.year != null) _Chip('${release.year}'),
                          if (release.label != null) _Chip(release.label!),
                          if (release.format != null) _Chip(release.format!),
                          if (release.catalogNumber != null)
                            _Chip(release.catalogNumber!),
                          ...release.genres.map(_Chip.new),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),
          const Divider(height: 1),

          // Side tabs (only shown when multiple sides)
          if (sides.length > 1)
            TabBar(
              controller: _tabs,
              tabs: sides.map((s) => Tab(text: 'Side $s')).toList(),
            ),

          // Tracklist
          Expanded(
            child: sides.isNotEmpty
                ? TabBarView(
                    controller: _tabs,
                    children: sides
                        .map(
                          (s) => _TrackList(
                            tracks: release.sides[s] ?? [],
                            scrollCtrl: scrollCtrl,
                          ),
                        )
                        .toList(),
                  )
                : _TrackList(tracks: release.tracklist, scrollCtrl: scrollCtrl),
          ),

          // Action buttons
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(context, true),
                  icon: const Icon(Icons.check),
                  label: const Text('Select this release'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackList extends StatelessWidget {
  final List<DiscogsTrack> tracks;
  final ScrollController scrollCtrl;

  const _TrackList({required this.tracks, required this.scrollCtrl});

  @override
  Widget build(BuildContext context) {
    if (tracks.isEmpty) {
      return const Center(child: Text('No tracks'));
    }
    return ListView.builder(
      controller: scrollCtrl,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: tracks.length,
      itemBuilder: (_, i) {
        final t = tracks[i];
        return ListTile(
          dense: true,
          leading: SizedBox(
            width: 28,
            child: Text(
              t.position,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          title: Text(t.title, style: Theme.of(context).textTheme.bodyMedium),
          trailing: t.duration.isNotEmpty
              ? Text(
                  t.duration,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                )
              : null,
        );
      },
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  const _Chip(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
