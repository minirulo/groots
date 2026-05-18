import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Displays a recorded waveform and lets the user manage split markers.
///
/// Interactions:
/// - Tap on an empty area → add a split marker at that position.
/// - Drag a split marker → move it.
/// - Drag the green ▶ start-trim marker → set where track 1 begins.
/// - Drag the orange ◀ end-trim marker → set where the last track ends.
/// - CMD + horizontal drag → zoom in/out (centred on the drag origin).
/// - Drag on empty space when zoomed in → pan the viewport.
/// - [playbackPosition] (0.0 – 1.0) draws a cyan cursor line when non-null.
class WaveformEditor extends StatefulWidget {
  final List<double> samples;

  /// Sample index where track 1 begins. Everything before is trimmed.
  final int startTrim;
  final ValueChanged<int>? onStartTrimChanged;

  /// Sample index where the last track ends. Everything after is trimmed.
  final int? endTrim;
  final ValueChanged<int>? onEndTrimChanged;

  /// Sorted list of sample indices where splits are placed.
  final List<int> splits;
  final ValueChanged<List<int>> onSplitsChanged;

  /// Playback cursor position normalised to 0.0 – 1.0. Null hides the cursor.
  final double? playbackPosition;

  const WaveformEditor({
    super.key,
    required this.samples,
    required this.splits,
    required this.onSplitsChanged,
    this.startTrim = 0,
    this.onStartTrimChanged,
    this.endTrim,
    this.onEndTrimChanged,
    this.playbackPosition,
  });

  @override
  State<WaveformEditor> createState() => _WaveformEditorState();
}

class _WaveformEditorState extends State<WaveformEditor> {
  // ── Zoom / pan ────────────────────────────────────────────────────────────
  double _zoomLevel = 1.0; // 1.0 = full waveform visible
  double _scrollOffset = 0.0; // normalised left edge [0, 1 − 1/zoomLevel]

  // ── Drag state ────────────────────────────────────────────────────────────
  int? _draggingIdx;
  bool _draggingStart = false;
  bool _draggingEnd = false;
  bool _isZooming = false;
  bool _isPanning = false;

  double _gestureStartX = 0.0;
  double _gestureStartZoom = 1.0;
  double _gestureStartScroll = 0.0;

  static const double _height = 140.0;
  static const double _hitSlop = 18.0;
  static const double _minimapHeight = 20.0;

  // ── Viewport helpers ──────────────────────────────────────────────────────

  int get _visibleStart => widget.samples.isEmpty
      ? 0
      : (_scrollOffset * widget.samples.length).round().clamp(0, widget.samples.length);

  int get _visibleEnd => widget.samples.isEmpty
      ? 0
      : (_visibleStart + widget.samples.length / _zoomLevel)
          .round()
          .clamp(1, widget.samples.length);

  double _sampleToX(int sampleIdx, double width) {
    final vLen = _visibleEnd - _visibleStart;
    if (vLen <= 0 || widget.samples.isEmpty) return 0;
    return (sampleIdx - _visibleStart) / vLen * width;
  }

  int _xToSample(double x, double width, {int min = 0, int? max}) {
    if (widget.samples.isEmpty || width == 0) return min;
    final m = max ?? widget.samples.length - 1;
    final vLen = _visibleEnd - _visibleStart;
    return (_visibleStart + x / width * vLen).round().clamp(min, m);
  }

  // ── Hit detection ─────────────────────────────────────────────────────────

  bool _isNearStartTrim(Offset pos, double width) =>
      (_sampleToX(widget.startTrim, width) - pos.dx).abs() < _hitSlop;

  bool _isNearEndTrim(Offset pos, double width) {
    final end = widget.endTrim ?? widget.samples.length;
    return widget.onEndTrimChanged != null &&
        (_sampleToX(end, width) - pos.dx).abs() < _hitSlop;
  }

  int? _findNearestSplit(Offset pos, double width) {
    for (int i = 0; i < widget.splits.length; i++) {
      if ((_sampleToX(widget.splits[i], width) - pos.dx).abs() < _hitSlop) {
        return i;
      }
    }
    return null;
  }

  // ── Gesture handlers ──────────────────────────────────────────────────────

  void _onPanStart(DragStartDetails d, double width) {
    // CMD + drag → zoom
    if (HardwareKeyboard.instance.isMetaPressed) {
      _isZooming = true;
      _gestureStartX = d.localPosition.dx;
      _gestureStartZoom = _zoomLevel;
      _gestureStartScroll = _scrollOffset;
      return;
    }

    if (_isNearEndTrim(d.localPosition, width)) {
      setState(() => _draggingEnd = true);
    } else if (_isNearStartTrim(d.localPosition, width)) {
      setState(() => _draggingStart = true);
    } else {
      _draggingIdx = _findNearestSplit(d.localPosition, width);
      if (_draggingIdx == null && _zoomLevel > 1.0) {
        // Pan the viewport when zoomed and not on a marker
        _isPanning = true;
        _gestureStartX = d.localPosition.dx;
        _gestureStartScroll = _scrollOffset;
      }
    }
  }

  void _onPanUpdate(DragUpdateDetails d, double width) {
    if (_isZooming) {
      _handleZoom(d.localPosition.dx, width);
      return;
    }
    if (_isPanning) {
      _handlePan(d.localPosition.dx, width);
      return;
    }
    if (_draggingEnd) {
      _handleEndTrimDrag(d.localPosition.dx, width);
      return;
    }
    if (_draggingStart) {
      _handleStartTrimDrag(d.localPosition.dx, width);
      return;
    }
    if (_draggingIdx != null) {
      _handleSplitDrag(d.localPosition.dx, width);
    }
  }

  void _onPanEnd(DragEndDetails _) => setState(() {
        _draggingIdx = null;
        _draggingStart = false;
        _draggingEnd = false;
        _isZooming = false;
        _isPanning = false;
      });

  void _handleZoom(double currentX, double width) {
    final delta = currentX - _gestureStartX;
    final newZoom = (_gestureStartZoom * (1 + delta / 150)).clamp(1.0, 30.0);

    // Keep the sample under the drag-start pixel fixed as zoom changes.
    final visibleLenOld = widget.samples.length / _gestureStartZoom;
    final anchorSample =
        _gestureStartScroll * widget.samples.length + (_gestureStartX / width) * visibleLenOld;
    final newVisibleLen = widget.samples.length / newZoom;
    final newScrollSample = anchorSample - (_gestureStartX / width) * newVisibleLen;
    final maxScroll = widget.samples.length - newVisibleLen;

    setState(() {
      _zoomLevel = newZoom;
      _scrollOffset =
          (newScrollSample / widget.samples.length).clamp(0.0, maxScroll / widget.samples.length);
    });
  }

  void _handlePan(double currentX, double width) {
    final delta = currentX - _gestureStartX;
    final visibleFraction = 1.0 / _zoomLevel;
    final newOffset = (_gestureStartScroll - delta / width * visibleFraction)
        .clamp(0.0, (1.0 - visibleFraction).clamp(0.0, 1.0));
    setState(() => _scrollOffset = newOffset);
  }

  void _handleEndTrimDrag(double x, double width) {
    final minEnd = widget.splits.isNotEmpty
        ? widget.splits.last + 1
        : widget.startTrim + 1;
    final newIdx =
        _xToSample(x, width, min: minEnd, max: widget.samples.length);
    widget.onEndTrimChanged?.call(newIdx);
  }

  void _handleStartTrimDrag(double x, double width) {
    final maxTrim = widget.splits.isNotEmpty
        ? widget.splits.first - 1
        : (widget.endTrim ?? widget.samples.length) - 1;
    final newIdx = _xToSample(x, width, min: 0, max: maxTrim);
    widget.onStartTrimChanged?.call(newIdx);
  }

  void _handleSplitDrag(double x, double width) {
    final newIdx = _xToSample(x, width, min: 1);
    final updated = List<int>.from(widget.splits);
    updated[_draggingIdx!] = newIdx;
    updated.sort();
    _draggingIdx = updated.indexOf(newIdx);
    widget.onSplitsChanged(updated);
  }

  void _onTapUp(TapUpDetails d, double width) {
    if (HardwareKeyboard.instance.isMetaPressed) return;
    if (_isNearStartTrim(d.localPosition, width)) return;
    if (_isNearEndTrim(d.localPosition, width)) return;
    if (_findNearestSplit(d.localPosition, width) != null) return;
    final idx = _xToSample(d.localPosition.dx, width, min: 1);
    final updated = List<int>.from(widget.splits)..add(idx);
    updated.sort();
    widget.onSplitsChanged(updated);
  }

  // ── Zoom helpers ──────────────────────────────────────────────────────────

  void _zoomBy(double factor, double width) {
    final newZoom = (_zoomLevel * factor).clamp(1.0, 30.0);
    // Keep the centre of the current viewport fixed.
    final centreNorm = _scrollOffset + 0.5 / _zoomLevel;
    final newVisibleFraction = 1.0 / newZoom;
    final newOffset = (centreNorm - newVisibleFraction / 2)
        .clamp(0.0, (1.0 - newVisibleFraction).clamp(0.0, 1.0));
    setState(() {
      _zoomLevel = newZoom;
      _scrollOffset = newOffset;
    });
  }

  void _onMinimapDrag(double dx, double width) {
    final visibleFraction = 1.0 / _zoomLevel;
    final newOffset =
        (dx / width - visibleFraction / 2).clamp(0.0, (1.0 - visibleFraction).clamp(0.0, 1.0));
    setState(() => _scrollOffset = newOffset);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Main waveform ──────────────────────────────────────────────
            SizedBox(
              height: _height,
              child: Stack(
                children: [
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTapUp: (d) => _onTapUp(d, width),
                      onPanStart: (d) => _onPanStart(d, width),
                      onPanUpdate: (d) => _onPanUpdate(d, width),
                      onPanEnd: _onPanEnd,
                      child: CustomPaint(
                        size: Size(width, _height),
                        painter: _WaveformPainter(
                          samples: widget.samples,
                          visibleStart: _visibleStart,
                          visibleEnd: _visibleEnd,
                          startTrim: widget.startTrim,
                          endTrim: widget.endTrim,
                          splits: widget.splits,
                          draggingIdx: _draggingIdx,
                          draggingStart: _draggingStart,
                          draggingEnd: _draggingEnd,
                          zoomLevel: _zoomLevel,
                          playbackPosition: widget.playbackPosition,
                          waveColor: Theme.of(context).colorScheme.primary,
                          markerColor: Colors.white,
                          dragColor: Theme.of(context).colorScheme.tertiary,
                        ),
                      ),
                    ),
                  ),
                  // ── Zoom buttons ─────────────────────────────────────────
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _ZoomButton(
                          icon: Icons.zoom_out,
                          onPressed: _zoomLevel > 1.0
                              ? () => _zoomBy(0.5, width)
                              : null,
                        ),
                        const SizedBox(width: 2),
                        _ZoomButton(
                          icon: Icons.zoom_in,
                          onPressed: _zoomLevel < 30.0
                              ? () => _zoomBy(2.0, width)
                              : null,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // ── Minimap scrollbar (visible only when zoomed) ───────────────
            if (_zoomLevel > 1.0)
              GestureDetector(
                onTapUp: (d) => _onMinimapDrag(d.localPosition.dx, width),
                onPanUpdate: (d) => _onMinimapDrag(d.localPosition.dx, width),
                child: CustomPaint(
                  size: Size(width, _minimapHeight),
                  painter: _MinimapPainter(
                    samples: widget.samples,
                    scrollOffset: _scrollOffset,
                    zoomLevel: _zoomLevel,
                    trackColor: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ── Zoom button ───────────────────────────────────────────────────────────────

class _ZoomButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  const _ZoomButton({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            icon,
            size: 16,
            color: onPressed != null
                ? Colors.white
                : Colors.white.withValues(alpha: 0.3),
          ),
        ),
      ),
    );
  }
}

// ── Painter ───────────────────────────────────────────────────────────────────

class _WaveformPainter extends CustomPainter {
  final List<double> samples;
  final int visibleStart;
  final int visibleEnd;
  final int startTrim;
  final int? endTrim;
  final List<int> splits;
  final int? draggingIdx;
  final bool draggingStart;
  final bool draggingEnd;
  final double zoomLevel;
  final double? playbackPosition;
  final Color waveColor;
  final Color markerColor;
  final Color dragColor;

  const _WaveformPainter({
    required this.samples,
    required this.visibleStart,
    required this.visibleEnd,
    required this.startTrim,
    required this.splits,
    required this.draggingIdx,
    required this.draggingStart,
    required this.draggingEnd,
    required this.zoomLevel,
    required this.waveColor,
    required this.markerColor,
    required this.dragColor,
    this.endTrim,
    this.playbackPosition,
  });

  double _sx(int sampleIdx, double width) {
    final vLen = visibleEnd - visibleStart;
    if (vLen <= 0) return 0;
    return (sampleIdx - visibleStart) / vLen * width;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFF1A1A2E),
    );

    if (samples.isEmpty) return;

    final vLen = visibleEnd - visibleStart;
    if (vLen <= 0) return;

    // ── Waveform bars ─────────────────────────────────────────────────────────
    final wavePaint = Paint()
      ..color = waveColor.withValues(alpha: 0.85)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    final barCount = size.width.toInt().clamp(1, 1 << 20);
    final samplesPerBar = vLen / barCount;
    final cy = size.height / 2;

    for (int col = 0; col < barCount; col++) {
      final iStart = (visibleStart + col * samplesPerBar).floor().clamp(0, samples.length - 1);
      final iEnd = (visibleStart + (col + 1) * samplesPerBar).ceil().clamp(1, samples.length);
      double peak = samples[iStart];
      for (int i = iStart + 1; i < iEnd; i++) {
        if (samples[i] > peak) peak = samples[i];
      }
      final halfH = peak * cy * 0.9;
      canvas.drawLine(
        Offset(col.toDouble(), cy - halfH),
        Offset(col.toDouble(), cy + halfH),
        wavePaint,
      );
    }

    // Centre line
    canvas.drawLine(Offset(0, cy), Offset(size.width, cy),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.1)
          ..strokeWidth = 0.5);

    // ── Trim overlays ─────────────────────────────────────────────────────────
    final trimX = _sx(startTrim, size.width).clamp(0.0, size.width);
    if (startTrim > visibleStart) {
      canvas.drawRect(Rect.fromLTWH(0, 0, trimX, size.height),
          Paint()..color = Colors.black.withValues(alpha: 0.50));
    }

    final endSample = endTrim ?? samples.length;
    final endX = _sx(endSample, size.width).clamp(0.0, size.width);
    if (endSample < visibleEnd) {
      canvas.drawRect(
          Rect.fromLTWH(endX, 0, size.width - endX, size.height),
          Paint()..color = Colors.black.withValues(alpha: 0.50));
    }

    // ── Start-trim marker ─────────────────────────────────────────────────────
    _drawTrimMarker(canvas, size, trimX, '▶ 1',
        dragging: draggingStart, color: Colors.greenAccent, badgeRight: true);

    // ── End-trim marker ───────────────────────────────────────────────────────
    final trackCount = splits.length + 1;
    _drawTrimMarker(canvas, size, endX, '$trackCount ◀',
        dragging: draggingEnd, color: Colors.orangeAccent, badgeRight: false);

    // ── Split markers ─────────────────────────────────────────────────────────
    for (int i = 0; i < splits.length; i++) {
      final x = _sx(splits[i], size.width);
      if (x < -_hitSlop || x > size.width + _hitSlop) continue; // off-screen
      final isDragging = i == draggingIdx;
      final color = isDragging ? dragColor : markerColor;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height),
          Paint()
            ..color = color.withValues(alpha: isDragging ? 1.0 : 0.8)
            ..strokeWidth = isDragging ? 2.5 : 1.5);
      _drawBadge(canvas, size, x, '${i + 2}', color, badgeRight: true);
    }

    // ── Zoom indicator ────────────────────────────────────────────────────────
    if (zoomLevel > 1.0) {
      final label = '${zoomLevel.toStringAsFixed(1)}×';
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 10,
              fontWeight: FontWeight.bold),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(size.width - tp.width - 6, size.height - tp.height - 4));
    }

    // ── Playback cursor ───────────────────────────────────────────────────────
    if (playbackPosition != null) {
      final totalSamples = samples.length;
      final cursorSample = (playbackPosition! * totalSamples).round();
      final cx = _sx(cursorSample, size.width);
      if (cx >= 0 && cx <= size.width) {
        canvas.drawLine(Offset(cx, 0), Offset(cx, size.height),
            Paint()
              ..color = Colors.cyanAccent.withValues(alpha: 0.9)
              ..strokeWidth = 2.0);
        final tri = Path()
          ..moveTo(cx - 6, 0)
          ..lineTo(cx + 6, 0)
          ..lineTo(cx, 9)
          ..close();
        canvas.drawPath(tri, Paint()..color = Colors.cyanAccent);
      }
    }
  }

  static const double _hitSlop = 18.0;

  void _drawTrimMarker(
    Canvas canvas,
    Size size,
    double x,
    String label, {
    required bool dragging,
    required Color color,
    required bool badgeRight,
  }) {
    final c = dragging ? Color.alphaBlend(Colors.white.withValues(alpha: 0.2), color) : color;
    canvas.drawLine(Offset(x, 0), Offset(x, size.height),
        Paint()
          ..color = c.withValues(alpha: dragging ? 1.0 : 0.85)
          ..strokeWidth = dragging ? 3.0 : 2.0);
    _drawBadge(canvas, size, x, label, c, badgeRight: badgeRight);
  }

  void _drawBadge(Canvas canvas, Size size, double x, String label, Color color,
      {required bool badgeRight}) {
    final tp = TextPainter(
      text: TextSpan(
          text: label,
          style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr,
    )..layout();
    final double bx;
    if (badgeRight) {
      bx = (x + 4).clamp(0.0, size.width - tp.width - 8);
    } else {
      bx = (x - tp.width - 6).clamp(0.0, size.width - tp.width - 8);
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(bx - 2, 3, tp.width + 4, tp.height + 2),
          const Radius.circular(3)),
      Paint()..color = color.withValues(alpha: 0.2),
    );
    tp.paint(canvas, Offset(bx, 4));
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.samples != samples ||
      old.visibleStart != visibleStart ||
      old.visibleEnd != visibleEnd ||
      old.startTrim != startTrim ||
      old.endTrim != endTrim ||
      old.splits != splits ||
      old.draggingIdx != draggingIdx ||
      old.draggingStart != draggingStart ||
      old.draggingEnd != draggingEnd ||
      old.zoomLevel != zoomLevel ||
      old.playbackPosition != playbackPosition;
}

// ── Minimap painter ───────────────────────────────────────────────────────────

class _MinimapPainter extends CustomPainter {
  final List<double> samples;
  final double scrollOffset;
  final double zoomLevel;
  final Color trackColor;

  const _MinimapPainter({
    required this.samples,
    required this.scrollOffset,
    required this.zoomLevel,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFF0D0D1A),
    );

    if (samples.isEmpty) return;

    // Full waveform overview (downsampled to width)
    final wavePaint = Paint()
      ..color = trackColor.withValues(alpha: 0.4)
      ..strokeWidth = 1.0;
    final barCount = size.width.toInt().clamp(1, samples.length);
    final samplesPerBar = samples.length / barCount;
    final cy = size.height / 2;

    for (int col = 0; col < barCount; col++) {
      final iStart = (col * samplesPerBar).floor().clamp(0, samples.length - 1);
      final iEnd = ((col + 1) * samplesPerBar).ceil().clamp(1, samples.length);
      double peak = samples[iStart];
      for (int i = iStart + 1; i < iEnd; i++) {
        if (samples[i] > peak) peak = samples[i];
      }
      final halfH = peak * cy * 0.85;
      canvas.drawLine(
        Offset(col.toDouble(), cy - halfH),
        Offset(col.toDouble(), cy + halfH),
        wavePaint,
      );
    }

    // Viewport window highlight
    final visibleFraction = 1.0 / zoomLevel;
    final winLeft = scrollOffset * size.width;
    final winWidth = visibleFraction * size.width;
    canvas.drawRect(
      Rect.fromLTWH(winLeft, 0, winWidth, size.height),
      Paint()..color = trackColor.withValues(alpha: 0.18),
    );
    // Window border
    canvas.drawRect(
      Rect.fromLTWH(winLeft, 0, winWidth, size.height),
      Paint()
        ..color = trackColor.withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
  }

  @override
  bool shouldRepaint(_MinimapPainter old) =>
      old.samples != samples ||
      old.scrollOffset != scrollOffset ||
      old.zoomLevel != zoomLevel ||
      old.trackColor != trackColor;
}
