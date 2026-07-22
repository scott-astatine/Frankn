// ignore_for_file: deprecated_member_use
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:frankn/utils/utils.dart';
import 'package:frankn/widgets/markdown/mermaid_parser.dart';
import 'package:google_fonts/google_fonts.dart';

class NeoMermaidWidget extends StatefulWidget {
  final String code;

  const NeoMermaidWidget({super.key, required this.code});

  @override
  State<NeoMermaidWidget> createState() => _NeoMermaidWidgetState();
}

class _NeoMermaidWidgetState extends State<NeoMermaidWidget> {
  late MermaidGraph _graph;
  final TransformationController _transformationController =
      TransformationController();

  @override
  void initState() {
    super.initState();
    _parse();
  }

  @override
  void didUpdateWidget(NeoMermaidWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.code != widget.code) {
      _parse();
    }
  }

  void _parse() {
    try {
      _graph = MermaidGraph.parse(widget.code);
    } catch (_) {
      _graph = MermaidGraph();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_graph.nodes.isEmpty) {
      return _buildFallbackCodeBlock();
    }

    double maxX = 0;
    double maxY = 0;
    for (var node in _graph.nodes.values) {
      maxX = max(maxX, node.position.dx + node.size.width + 80);
      maxY = max(maxY, node.position.dy + node.size.height + 80);
    }

    final Size canvasSize = Size(max(maxX, 320), max(maxY, 240));
    final double inlineHeight = min(max(canvasSize.height + 40, 220.0), 550.0);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.accentPrimary.withValues(alpha: 0.3),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(canvasSize),
          ClipRRect(
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
            child: SizedBox(
              height: inlineHeight,
              width: double.infinity,
              child: InteractiveViewer(
                transformationController: _transformationController,
                boundaryMargin: const EdgeInsets.all(80),
                minScale: 0.2,
                maxScale: 4.0,
                child: Center(
                  child: CustomPaint(
                    size: canvasSize,
                    painter: NeoMermaidGraphPainter(graph: _graph),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(Size canvasSize) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        border: Border(
          bottom: BorderSide(
            color: AppColors.accentPrimary.withValues(alpha: 0.2),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Icon(
                Icons.schema_rounded,
                color: AppColors.accentPrimary,
                size: 15,
              ),
              const SizedBox(width: 8),
              Text(
                "MERMAID GRAPH",
                style: GoogleFonts.jetBrainsMono(
                  color: AppColors.accentPrimary,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(
                  Icons.open_in_full_rounded,
                  color: AppColors.accentPrimary,
                  size: 16,
                ),
                tooltip: "Full Screen & Interactive Zoom",
                onPressed: () => _openFullScreenModal(canvasSize),
              ),
              IconButton(
                icon: const Icon(
                  Icons.center_focus_weak_rounded,
                  color: AppColors.textSecondary,
                  size: 16,
                ),
                tooltip: "Reset Zoom",
                onPressed: () {
                  _transformationController.value = Matrix4.identity();
                },
              ),
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: widget.code));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        "Mermaid code copied to clipboard",
                        style: GoogleFonts.jetBrainsMono(fontSize: 11),
                      ),
                      duration: const Duration(seconds: 2),
                      backgroundColor: AppColors.surfaceSecondary,
                    ),
                  );
                },
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    Icons.copy_all_rounded,
                    color: AppColors.textSecondary,
                    size: 16,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _openFullScreenModal(Size canvasSize) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.9),
      builder: (context) {
        final TransformationController fullController =
            TransformationController();
        return Dialog.fullscreen(
          backgroundColor: AppColors.background,
          child: StatefulBuilder(
            builder: (context, setState) {
              return Stack(
                children: [
                  // Interactive Graph View
                  Positioned.fill(
                    child: InteractiveViewer(
                      transformationController: fullController,
                      boundaryMargin: const EdgeInsets.all(300),
                      minScale: 0.1,
                      maxScale: 8.0,
                      child: Center(
                        child: CustomPaint(
                          size: canvasSize,
                          painter: NeoMermaidGraphPainter(graph: _graph),
                        ),
                      ),
                    ),
                  ),

                  // Top Header Bar
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surface.withValues(alpha: 0.85),
                        border: Border(
                          bottom: BorderSide(
                            color: AppColors.accentPrimary.withValues(alpha: 0.3),
                            width: 0.5,
                          ),
                        ),
                      ),
                      child: SafeArea(
                        bottom: false,
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.close_rounded,
                                color: AppColors.accentPrimary,
                              ),
                              onPressed: () => Navigator.pop(context),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              "INTERACTIVE MERMAID DIAGRAM",
                              style: GoogleFonts.jetBrainsMono(
                                color: AppColors.accentPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(
                                Icons.copy_all_rounded,
                                color: AppColors.textSecondary,
                                size: 20,
                              ),
                              tooltip: "Copy Source Code",
                              onPressed: () {
                                Clipboard.setData(
                                    ClipboardData(text: widget.code));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      "Mermaid code copied to clipboard",
                                      style: GoogleFonts.jetBrainsMono(
                                          fontSize: 11),
                                    ),
                                    duration: const Duration(seconds: 2),
                                    backgroundColor: AppColors.surfaceSecondary,
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Floating Zoom HUD Controls (Bottom Right)
                  Positioned(
                    bottom: 24,
                    right: 24,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.surface.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: AppColors.accentPrimary.withValues(alpha: 0.4),
                          width: 0.8,
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.add,
                                color: AppColors.accentPrimary, size: 20),
                            tooltip: "Zoom In",
                            onPressed: () {
                              fullController.value =
                                  fullController.value.scaled(1.25, 1.25, 1.0);
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.remove,
                                color: AppColors.accentPrimary, size: 20),
                            tooltip: "Zoom Out",
                            onPressed: () {
                              fullController.value =
                                  fullController.value.scaled(0.8, 0.8, 1.0);
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.center_focus_strong_rounded,
                                color: AppColors.accentPrimary, size: 20),
                            tooltip: "Reset View",
                            onPressed: () {
                              fullController.value = Matrix4.identity();
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildFallbackCodeBlock() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white10),
      ),
      child: Text(
        widget.code,
        style: GoogleFonts.jetBrainsMono(
          color: AppColors.markdownPrimaryLight,
          fontSize: 12,
        ),
      ),
    );
  }
}

class NeoMermaidGraphPainter extends CustomPainter {
  final MermaidGraph graph;

  NeoMermaidGraphPainter({required this.graph});

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Draw Edges & Arrows
    for (var edge in graph.edges) {
      final fromNode = graph.nodes[edge.fromId];
      final toNode = graph.nodes[edge.toId];
      if (fromNode == null || toNode == null) continue;

      _drawEdge(canvas, fromNode, toNode, edge);
    }

    // 2. Draw Nodes
    for (var node in graph.nodes.values) {
      _drawNode(canvas, node);
    }
  }

  void _drawNode(Canvas canvas, MermaidNode node) {
    final rect = Rect.fromLTWH(
      node.position.dx,
      node.position.dy,
      node.size.width,
      node.size.height,
    );

    final bgPaint = Paint()
      ..color = AppColors.background.withValues(alpha: 0.95)
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = AppColors.accentPrimary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    final glowPaint = Paint()
      ..color = AppColors.accentPrimary.withValues(alpha: 0.15)
      ..style = PaintingStyle.fill;

    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(6));

    if (node.type == MermaidNodeType.rounded) {
      final roundRRect = RRect.fromRectAndRadius(rect, const Radius.circular(20));
      canvas.drawRRect(roundRRect, glowPaint);
      canvas.drawRRect(roundRRect, bgPaint);
      canvas.drawRRect(roundRRect, borderPaint);
    } else if (node.type == MermaidNodeType.diamond) {
      final path = Path()
        ..moveTo(rect.centerLeft.dx, rect.centerLeft.dy)
        ..lineTo(rect.topCenter.dx, rect.topCenter.dy)
        ..lineTo(rect.centerRight.dx, rect.centerRight.dy)
        ..lineTo(rect.bottomCenter.dx, rect.bottomCenter.dy)
        ..close();
      canvas.drawPath(path, glowPaint);
      canvas.drawPath(path, bgPaint);
      canvas.drawPath(path, borderPaint);
    } else {
      canvas.drawRRect(rrect, glowPaint);
      canvas.drawRRect(rrect, bgPaint);
      canvas.drawRRect(rrect, borderPaint);
    }

    // Node Label
    final textPainter = TextPainter(
      text: TextSpan(
        text: node.label,
        style: GoogleFonts.jetBrainsMono(
          color: AppColors.accentPrimary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 2,
      ellipsis: '...',
      textAlign: TextAlign.center,
    );

    textPainter.layout(maxWidth: node.size.width - 12);
    textPainter.paint(
      canvas,
      Offset(
        rect.center.dx - (textPainter.width / 2),
        rect.center.dy - (textPainter.height / 2),
      ),
    );
  }

  void _drawEdge(
    Canvas canvas,
    MermaidNode from,
    MermaidNode to,
    MermaidEdge edge,
  ) {
    final fromCenter = Offset(
      from.position.dx + from.size.width / 2,
      from.position.dy + from.size.height / 2,
    );
    final toCenter = Offset(
      to.position.dx + to.size.width / 2,
      to.position.dy + to.size.height / 2,
    );

    final start = _getIntersection(from, toCenter);
    final end = _getIntersection(to, fromCenter);

    final edgePaint = Paint()
      ..color = AppColors.accentSecondary.withValues(alpha: 0.8)
      ..strokeWidth = edge.style == MermaidEdgeStyle.thick ? 2.5 : 1.5
      ..style = PaintingStyle.stroke;

    if (edge.style == MermaidEdgeStyle.dashed) {
      _drawDashedLine(canvas, start, end, edgePaint);
    } else {
      canvas.drawLine(start, end, edgePaint);
    }

    // Draw Arrowhead
    _drawArrowHead(canvas, start, end, edgePaint.color);

    // Draw Edge Label if present
    if (edge.label != null && edge.label!.isNotEmpty) {
      final midPoint = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
      final textPainter = TextPainter(
        text: TextSpan(
          text: edge.label,
          style: GoogleFonts.jetBrainsMono(
            color: Colors.white70,
            fontSize: 9,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();

      final labelBgRect = Rect.fromCenter(
        center: midPoint,
        width: textPainter.width + 8,
        height: textPainter.height + 4,
      );

      canvas.drawRRect(
        RRect.fromRectAndRadius(labelBgRect, const Radius.circular(3)),
        Paint()..color = AppColors.background,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(labelBgRect, const Radius.circular(3)),
        Paint()
          ..color = AppColors.accentSecondary.withValues(alpha: 0.4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5,
      );

      textPainter.paint(
        canvas,
        Offset(
          midPoint.dx - (textPainter.width / 2),
          midPoint.dy - (textPainter.height / 2),
        ),
      );
    }
  }

  Offset _getIntersection(MermaidNode node, Offset target) {
    final rect = Rect.fromLTWH(
      node.position.dx,
      node.position.dy,
      node.size.width,
      node.size.height,
    );
    final center = rect.center;
    final angle = atan2(target.dy - center.dy, target.dx - center.dx);

    final halfW = rect.width / 2;
    final halfH = rect.height / 2;

    final cosA = cos(angle);
    final sinA = sin(angle);

    double x = center.dx;
    double y = center.dy;

    if (cosA.abs() * halfH > sinA.abs() * halfW) {
      x += cosA > 0 ? halfW : -halfW;
      y += (cosA > 0 ? halfW : -halfW) * tan(angle);
    } else {
      y += sinA > 0 ? halfH : -halfH;
      x += (sinA > 0 ? halfH : -halfH) / tan(angle);
    }

    return Offset(x, y);
  }

  void _drawArrowHead(Canvas canvas, Offset start, Offset end, Color color) {
    final angle = atan2(end.dy - start.dy, end.dx - start.dx);
    const arrowSize = 8.0;

    final path = Path()
      ..moveTo(end.dx, end.dy)
      ..lineTo(
        end.dx - arrowSize * cos(angle - pi / 6),
        end.dy - arrowSize * sin(angle - pi / 6),
      )
      ..lineTo(
        end.dx - arrowSize * cos(angle + pi / 6),
        end.dy - arrowSize * sin(angle + pi / 6),
      )
      ..close();

    canvas.drawPath(path, Paint()..color = color);
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    const dashWidth = 5.0;
    const dashSpace = 4.0;
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final distance = sqrt(dx * dx + dy * dy);
    final count = (distance / (dashWidth + dashSpace)).floor();

    final cosA = dx / distance;
    final sinA = dy / distance;

    for (int i = 0; i < count; i++) {
      final startDash = Offset(
        start.dx + (i * (dashWidth + dashSpace)) * cosA,
        start.dy + (i * (dashWidth + dashSpace)) * sinA,
      );
      final endDash = Offset(
        startDash.dx + dashWidth * cosA,
        startDash.dy + dashWidth * sinA,
      );
      canvas.drawLine(startDash, endDash, paint);
    }
  }

  @override
  bool shouldRepaint(covariant NeoMermaidGraphPainter oldDelegate) =>
      oldDelegate.graph != graph;
}
