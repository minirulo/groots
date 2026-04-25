import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

/// Launches the full cover-scan flow (source sheet → crop → enhance).
/// Returns `(bytes, mime)` or `null` if the user cancels at any step.
Future<(Uint8List, String)?> scanAlbumCover(BuildContext context) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    builder: (_) => const _SourceSheet(),
  );
  if (source == null || !context.mounted) return null;

  final picked = await ImagePicker().pickImage(
    source: source,
    imageQuality: 95,
    maxWidth: 2000,
    maxHeight: 2000,
  );
  if (picked == null || !context.mounted) return null;

  final Uint8List rawBytes;
  if (Platform.isLinux) {
    // image_cropper has no Linux implementation — use the picked file directly.
    rawBytes = await picked.readAsBytes();
  } else {
    final cropped = await ImageCropper().cropImage(
      sourcePath: picked.path,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 95,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Align Cover',
          toolbarColor: Colors.black,
          toolbarWidgetColor: Colors.white,
          lockAspectRatio: true,
          hideBottomControls: false,
        ),
        IOSUiSettings(
          title: 'Align Cover',
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
          rotateButtonsHidden: false,
        ),
      ],
    );
    if (cropped == null || !context.mounted) return null;
    rawBytes = await cropped.readAsBytes();
  }
  if (!context.mounted) return null;

  final result = await Navigator.of(context).push<Uint8List>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _CoverEnhanceScreen(rawBytes: rawBytes),
    ),
  );

  if (result == null) return null;
  return (result, 'image/jpeg');
}

// ── Source selection sheet ────────────────────────────────────────────────────

class _SourceSheet extends StatelessWidget {
  const _SourceSheet();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 8),
          if (!Platform.isLinux)
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Scan with camera'),
              subtitle: const Text('Photograph and crop the album cover'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from gallery'),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ── Enhance screen ────────────────────────────────────────────────────────────

class _CoverEnhanceScreen extends StatefulWidget {
  final Uint8List rawBytes;
  const _CoverEnhanceScreen({required this.rawBytes});

  @override
  State<_CoverEnhanceScreen> createState() => _CoverEnhanceScreenState();
}

class _CoverEnhanceScreenState extends State<_CoverEnhanceScreen> {
  bool _enhanced = true;
  Uint8List? _enhancedBytes;
  bool _processing = true;

  @override
  void initState() {
    super.initState();
    _runEnhancement();
  }

  Future<void> _runEnhancement() async {
    setState(() => _processing = true);
    final result = await compute(_enhance, widget.rawBytes);
    if (mounted) {
      setState(() {
        _enhancedBytes = result;
        _processing = false;
      });
    }
  }

  // Runs in a separate isolate — no Flutter APIs allowed.
  static Uint8List _enhance(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;

    var out = img.adjustColor(
      decoded,
      saturation: 1.2,
      contrast: 1.12,
      gamma: 0.92,
    );

    // 3×3 unsharp/sharpen kernel
    out = img.convolution(
      out,
      filter: [0, -1, 0, -1, 5, -1, 0, -1, 0],
    );

    return Uint8List.fromList(img.encodeJpg(out, quality: 92));
  }

  Uint8List get _displayBytes =>
      _enhanced && _enhancedBytes != null ? _enhancedBytes! : widget.rawBytes;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Enhance Cover'),
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: _processing
                  ? const CircularProgressIndicator()
                  : Image.memory(_displayBytes, fit: BoxFit.contain),
            ),
          ),
          Container(
            color: scheme.surface,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  title: const Text('Auto Enhance'),
                  subtitle: const Text(
                    'Boosts contrast, saturation & sharpness',
                  ),
                  value: _enhanced,
                  onChanged: _processing
                      ? null
                      : (v) => setState(() => _enhanced = v),
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Retake'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: _processing
                            ? null
                            : () => Navigator.pop(context, _displayBytes),
                        child: const Text('Use Photo'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
