import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:record/record.dart';

/// Drop-in replacement for [AudioRecorder] that routes macOS recording through
/// a custom AVAudioEngine method channel, bypassing AVCaptureSession's
/// microphone-oriented gain processing which clips line-in signals.
///
/// On non-macOS platforms it delegates to [AudioRecorder] unchanged.
class VinylRecorder {
  static const _ch = MethodChannel('vinyl_recorder');

  final AudioRecorder? _fallback = Platform.isMacOS ? null : AudioRecorder();

  // ── Device listing ────────────────────────────────────────────────────────

  Future<List<InputDevice>> listInputDevices() async {
    if (_fallback != null) return _fallback.listInputDevices();
    final raw = await _ch.invokeListMethod<Map>('listDevices') ?? [];
    return raw
        .map((d) => InputDevice(
              id: d['id'] as String,
              label: d['label'] as String,
            ))
        .toList();
  }

  // ── Permission ────────────────────────────────────────────────────────────

  Future<bool> hasPermission() async {
    if (_fallback != null) return _fallback.hasPermission();
    return await _ch.invokeMethod<bool>('hasPermission') ?? false;
  }

  // ── Input monitoring ──────────────────────────────────────────────────────

  Future<List<InputDevice>> listOutputDevices() async {
    if (_fallback != null) return [];
    final raw = await _ch.invokeListMethod<Map>('listOutputDevices') ?? [];
    return raw
        .map((d) => InputDevice(id: d['id'] as String, label: d['label'] as String))
        .toList();
  }

  Future<void> startMonitoring(InputDevice? inputDevice, InputDevice? outputDevice) async {
    if (_fallback != null) return;
    await _ch.invokeMethod<void>('startMonitoring', {
      'deviceId': inputDevice?.id,
      'outputDeviceId': outputDevice?.id,
    });
  }

  Future<void> stopMonitoring() async {
    if (_fallback != null) return;
    await _ch.invokeMethod<void>('stopMonitoring');
  }

  // ── Recording ─────────────────────────────────────────────────────────────

  Future<void> start(RecordConfig config, {required String path}) async {
    if (_fallback != null) {
      return _fallback.start(config, path: path);
    }
    await _ch.invokeMethod<void>('start', {
      'deviceId': config.device?.id,
      'path': path,
    });
  }

  Future<void> stop() async {
    if (_fallback != null) {
      await _fallback.stop();
      return;
    }
    await _ch.invokeMethod<void>('stop');
  }

  // ── Amplitude stream ──────────────────────────────────────────────────────

  Stream<Amplitude> onAmplitudeChanged(Duration interval) {
    if (_fallback != null) return _fallback.onAmplitudeChanged(interval);

    late StreamController<Amplitude> controller;
    Timer? timer;

    controller = StreamController<Amplitude>(
      onListen: () {
        timer = Timer.periodic(interval, (_) async {
          try {
            final db =
                await _ch.invokeMethod<double>('getAmplitude') ?? -160.0;
            if (!controller.isClosed) {
              controller.add(Amplitude(current: db, max: db));
            }
          } catch (_) {}
        });
      },
      onCancel: () {
        timer?.cancel();
        controller.close();
      },
    );

    return controller.stream;
  }

  // ── File operations ───────────────────────────────────────────────────────

  /// Returns the duration of an audio file. On macOS uses AVAudioFile natively
  /// (safe inside the sandbox); elsewhere falls back to ffprobe.
  Future<Duration?> probeInfo(String path) async {
    if (_fallback != null) {
      try {
        final r = await Process.run('ffprobe', [
          '-v', 'quiet',
          '-show_entries', 'format=duration',
          '-of', 'csv=p=0',
          path,
        ]);
        final secs = double.tryParse((r.stdout as String).trim());
        return secs != null
            ? Duration(milliseconds: (secs * 1000).round())
            : null;
      } catch (_) {
        return null;
      }
    }
    try {
      final map =
          await _ch.invokeMapMethod<String, dynamic>('probeInfo', {'path': path});
      final secs = (map?['duration'] as num?)?.toDouble();
      return secs != null
          ? Duration(milliseconds: (secs * 1000).round())
          : null;
    } catch (_) {
      return null;
    }
  }

  /// Extracts [startSec]–[endSec] from [inputPath] and writes FLAC to
  /// [outputPath]. On macOS uses AVAudioFile; elsewhere falls back to ffmpeg.
  Future<void> exportSegment(
    String inputPath,
    String outputPath,
    double startSec,
    double endSec,
  ) async {
    if (_fallback != null) {
      final r = await Process.run('ffmpeg', [
        '-y', '-i', inputPath,
        '-ss', startSec.toStringAsFixed(3),
        '-to', endSec.toStringAsFixed(3),
        '-c:a', 'flac',
        outputPath,
      ]);
      if (r.exitCode != 0) {
        throw Exception('ffmpeg error: ${r.stderr}');
      }
      return;
    }
    await _ch.invokeMethod<void>('exportSegment', {
      'inputPath': inputPath,
      'outputPath': outputPath,
      'startSec': startSec,
      'endSec': endSec,
    });
  }

  /// Reads [path] and returns [numSamples] normalised amplitude values (0–1)
  /// for waveform display. Returns empty list on non-macOS (recording path
  /// generates samples live instead).
  Future<List<double>> generateWaveform(String path, int numSamples) async {
    if (_fallback != null) return [];
    final raw = await _ch.invokeListMethod<double>('generateWaveform', {
      'path': path,
      'numSamples': numSamples,
    });
    return raw ?? [];
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  void dispose() {
    _fallback?.dispose();
    // Native side is cleaned up on stop(); no persistent resources to release.
  }
}
