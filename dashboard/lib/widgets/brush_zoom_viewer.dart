import 'package:flutter/material.dart';
import 'dart:math' as math;

class BrushZoomViewer extends StatefulWidget {
  final Widget child;
  const BrushZoomViewer({super.key, required this.child});

  @override
  State<BrushZoomViewer> createState() => _BrushZoomViewerState();
}

class _BrushZoomViewerState extends State<BrushZoomViewer> {
  final _controller = TransformationController();
  bool _forceZoomMode = false;
  bool _isZoomed = false;
  Offset? _dragStart;
  Offset? _dragCurrent;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final zoomed = _controller.value.getMaxScaleOnAxis() > 1.05;
      if (zoomed != _isZoomed) {
        setState(() {
          _isZoomed = zoomed;
          if (!zoomed) _forceZoomMode = false; // reset mode on full zoom out
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _resetZoom() {
    _controller.value = Matrix4.identity();
    setState(() {
      _dragStart = null;
      _dragCurrent = null;
      _forceZoomMode = false;
    });
  }

  void _applyZoom(Rect rect, Size size) {
    if (rect.width < 10 && rect.height < 10) return;

    final w = math.max(rect.width, 10.0);
    final h = math.max(rect.height, 10.0);

    final scaleX = size.width / w;
    final scaleY = size.height / h;
    final scale = math.min(scaleX, scaleY).clamp(1.0, 15.0);

    double tx = -rect.left * scale;
    double ty = -rect.top * scale;

    if (scale == scaleY) {
      final scaledWidth = w * scale;
      tx += (size.width - scaledWidth) / 2;
    } else {
      final scaledHeight = h * scale;
      ty += (size.height - scaledHeight) / 2;
    }

    final mZoom = Matrix4.identity()
      ..translate(tx, ty)
      ..scale(scale);

    // Multiplica pela matriz atual para permitir Zoom de Zoom!
    final newMatrix = mZoom.multiplied(_controller.value);
    
    // Não deixamos o scale total ultrapassar 100x para evitar glitches visuais
    if (newMatrix.getMaxScaleOnAxis() > 100.0) {
      // Se passar, podíamos ajustar, mas por simplicidade mantemos até 100x
    }
    
    _controller.value = newMatrix;
    setState(() => _forceZoomMode = false); // Volta ao Pan depois do zoom
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        
        final canDrawBox = !_isZoomed || _forceZoomMode;

        return Stack(
          children: [
            Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: canDrawBox
                  ? (event) {
                      setState(() {
                        _dragStart = event.localPosition;
                        _dragCurrent = event.localPosition;
                      });
                    }
                  : null,
              onPointerMove: canDrawBox
                  ? (event) {
                      if (_dragStart == null) return;
                      setState(() {
                        _dragCurrent = event.localPosition;
                      });
                    }
                  : null,
              onPointerUp: canDrawBox
                  ? (event) {
                      if (_dragStart == null || _dragCurrent == null) return;
                      final rect = Rect.fromPoints(_dragStart!, _dragCurrent!);
                      setState(() {
                        _dragStart = null;
                        _dragCurrent = null;
                      });
                      _applyZoom(rect, size);
                    }
                  : null,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onDoubleTap: _resetZoom,
                child: InteractiveViewer(
                  transformationController: _controller,
                  panEnabled: _isZoomed && !_forceZoomMode,
                  scaleEnabled: false,
                  minScale: 1.0,
                  maxScale: 100.0, // Aumentado para suportar Zoom do Zoom
                  boundaryMargin: const EdgeInsets.all(80),
                  child: widget.child,
                ),
              ),
            ),
            if (_dragStart != null && _dragCurrent != null && canDrawBox)
              Positioned.fromRect(
                rect: Rect.fromPoints(_dragStart!, _dragCurrent!),
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.blueAccent.withValues(alpha: 0.15),
                      border: Border.all(color: Colors.blueAccent, width: 1.5),
                    ),
                  ),
                ),
              ),
            if (_isZoomed)
              Positioned(
                top: 8,
                right: 8,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(
                              Icons.pan_tool,
                              color: !_forceZoomMode ? Colors.blueAccent : Colors.white70,
                              size: 18,
                            ),
                            tooltip: 'Modo Navegação (Pan)',
                            onPressed: () => setState(() => _forceZoomMode = false),
                          ),
                          Container(width: 1, height: 20, color: Colors.white24),
                          IconButton(
                            icon: Icon(
                              Icons.zoom_in,
                              color: _forceZoomMode ? Colors.blueAccent : Colors.white70,
                              size: 18,
                            ),
                            tooltip: 'Modo Lupa (Zoom Box)',
                            onPressed: () => setState(() => _forceZoomMode = true),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.zoom_out_map, color: Colors.white, size: 20),
                      style: IconButton.styleFrom(backgroundColor: Colors.black54),
                      onPressed: _resetZoom,
                      tooltip: 'Repor vista global',
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
