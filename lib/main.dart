import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'pen_report.dart';

void main() => runApp(const LenovoGraphicsPadApp());

class LenovoGraphicsPadApp extends StatelessWidget {
  const LenovoGraphicsPadApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Lenovo Graphics Pad',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff3478f6)),
      useMaterial3: true,
    ),
    home: const DrawingPreviewPage(),
  );
}

class DrawingPreviewPage extends StatefulWidget {
  const DrawingPreviewPage({super.key});

  @override
  State<DrawingPreviewPage> createState() => _DrawingPreviewPageState();
}

class _DrawingPreviewPageState extends State<DrawingPreviewPage> {
  static const int _maxStoredPoints = 2000;
  final List<List<Offset>> _strokes = [];
  int _storedPoints = 0;
  int? _activePointer;
  String _transport = 'USB';
  String _tool = 'No input yet';
  Offset? _normalized;
  double? _pressure;
  bool _tip = false;
  Uint8List? _report;

  void _record(PointerEvent event, {required bool tip}) {
    // Locate the drawing area independently of the page's layout coordinates.
    final area = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    final size = area?.size ?? Size.zero;
    final local = area?.globalToLocal(event.position) ?? Offset.zero;
    final point = Offset(
      size.width == 0 ? 0 : (local.dx / size.width).clamp(0.0, 1.0).toDouble(),
      size.height == 0
          ? 0
          : (local.dy / size.height).clamp(0.0, 1.0).toDouble(),
    );
    final pressure = event.pressure.clamp(0.0, 1.0).toDouble();
    setState(() {
      _tool = event.kind.name;
      _normalized = point;
      _pressure = pressure;
      _tip = tip;
      final payload = PenReport.encode(
        tip: tip,
        inRange: tip,
        barrel: false,
        x: (point.dx * PenReport.maxCoordinate).round(),
        y: (point.dy * PenReport.maxCoordinate).round(),
        pressure: (pressure * PenReport.maxPressure).round(),
      );
      _report = Uint8List.fromList(payload);
    });
  }

  final GlobalKey _canvasKey = GlobalKey();

  void _beginStroke(Offset localPosition) {
    if (_activePointer == null || _storedPoints >= _maxStoredPoints) return;
    setState(() {
      _strokes.add([localPosition]);
      _storedPoints++;
    });
  }

  void _extendStroke(Offset localPosition) {
    if (_activePointer == null ||
        _strokes.isEmpty ||
        _storedPoints >= _maxStoredPoints) {
      return;
    }
    setState(() {
      _strokes.last.add(localPosition);
      _storedPoints++;
    });
  }

  void _clearDrawing() {
    setState(() {
      _strokes.clear();
      _storedPoints = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final normalized = _normalized;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lenovo Graphics Pad'),
        actions: [
          IconButton(
            tooltip: 'Clear drawing',
            onPressed: _clearDrawing,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Card(
                color: Theme.of(context).colorScheme.secondaryContainer,
                child: const Padding(
                  padding: EdgeInsets.all(14),
                  child: Text(
                    'Local preview only. No tablet or host is connected, and USB/Bluetooth transport is not implemented.',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('Transport'),
                  const SizedBox(width: 12),
                  DropdownButton<String>(
                    value: _transport,
                    items: const [
                      DropdownMenuItem(value: 'USB', child: Text('USB')),
                      DropdownMenuItem(
                        value: 'Bluetooth',
                        child: Text('Bluetooth'),
                      ),
                    ],
                    onChanged: (value) => setState(() => _transport = value!),
                  ),
                  const Expanded(child: SizedBox()),
                  const Text('Not implemented', style: TextStyle(fontSize: 12)),
                ],
              ),
              const SizedBox(height: 8),
              const Text('Draw here to inspect Flutter pointer events.'),
              const SizedBox(height: 8),
              Expanded(
                child: Listener(
                  key: _canvasKey,
                  onPointerDown: (event) {
                    _activePointer ??= event.pointer;
                    if (_activePointer == event.pointer) {
                      _record(event, tip: true);
                    }
                  },
                  onPointerMove: (event) {
                    if (_activePointer == event.pointer) {
                      _record(event, tip: true);
                    }
                  },
                  onPointerUp: (event) {
                    if (_activePointer == event.pointer) {
                      _record(event, tip: false);
                      _activePointer = null;
                    }
                  },
                  onPointerCancel: (event) {
                    if (_activePointer == event.pointer) {
                      _record(event, tip: false);
                      _activePointer = null;
                    }
                  },
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (details) =>
                        _beginStroke(details.localPosition),
                    onPanUpdate: (details) =>
                        _extendStroke(details.localPosition),
                    onPanEnd: (_) {},
                    child: CustomPaint(
                      size: Size.infinite,
                      key: const ValueKey('preview-canvas'),
                      foregroundPainter: _StrokePainter(_strokes),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Center(
                          child: Text(
                            'Touch, mouse, or pen input is previewed locally',
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Pointer tool: $_tool'),
                  Text(
                    'Normalized position: ${normalized == null ? '—' : '${normalized.dx.toStringAsFixed(3)}, ${normalized.dy.toStringAsFixed(3)}'}',
                  ),
                  Text(
                    'Flutter-reported pressure: ${_pressure?.toStringAsFixed(3) ?? '—'} (may be synthetic or unavailable)',
                  ),
                  Text('Tip: ${_tip ? 'down' : 'up'}'),
                  Text('Encoded report ID: ${_report?.first ?? '—'}'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StrokePainter extends CustomPainter {
  const _StrokePainter(this.strokes);

  final List<List<Offset>> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xff3478f6)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    for (final points in strokes) {
      for (var i = 1; i < points.length; i++) {
        canvas.drawLine(points[i - 1], points[i], paint);
      }
      if (points.length == 1) canvas.drawCircle(points.first, 2, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _StrokePainter oldDelegate) => true;
}
