import 'package:flutter/material.dart';

enum MermaidNodeType {
  rectangle,
  rounded,
  diamond,
  database,
  circle,
}

enum MermaidEdgeStyle {
  solid,
  dashed,
  thick,
}

class MermaidNode {
  final String id;
  final String label;
  final MermaidNodeType type;
  Offset position = Offset.zero;
  Size size = Size.zero;
  int level = 0;

  MermaidNode({
    required this.id,
    required this.label,
    this.type = MermaidNodeType.rectangle,
  });
}

class MermaidEdge {
  final String fromId;
  final String toId;
  final String? label;
  final MermaidEdgeStyle style;

  MermaidEdge({
    required this.fromId,
    required this.toId,
    this.label,
    this.style = MermaidEdgeStyle.solid,
  });
}

class MermaidGraph {
  final String direction; // 'TD', 'TB', 'LR', 'RL'
  final Map<String, MermaidNode> nodes = {};
  final List<MermaidEdge> edges = [];

  MermaidGraph({this.direction = 'TD'});

  bool get isHorizontal => direction == 'LR' || direction == 'RL';

  static MermaidGraph parse(String source) {
    final lines = source
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && !l.startsWith('%%'))
        .toList();

    String direction = 'TD';
    if (lines.isNotEmpty) {
      final firstLine = lines.first.toUpperCase();
      if (firstLine.startsWith('GRAPH') || firstLine.startsWith('FLOWCHART')) {
        final parts = firstLine.split(RegExp(r'\s+'));
        if (parts.length > 1) {
          direction = parts[1];
        }
      }
    }

    final graph = MermaidGraph(direction: direction);

    for (var line in lines) {
      if (line.toUpperCase().startsWith('GRAPH') ||
          line.toUpperCase().startsWith('FLOWCHART')) {
        continue;
      }
      _parseLine(line, graph);
    }

    _layoutGraph(graph);
    return graph;
  }

  static void _parseLine(String line, MermaidGraph graph) {
    // Edge pattern: A -->|text| B or A --> B or A -.-> B or A ==> B
    final edgeRegex = RegExp(
      r'([A-Za-z0-9_\-\.]+)(?:\[(.*?)\]|\((.*?)\)|\{(.*?)\}|\[\((.*?)\)\]|\(\((.*?)\)\))?\s*(==>|---\>|-->|-\.\->|---)\s*(?:\|([^|]+)\|)?\s*([A-Za-z0-9_\-\.]+)(?:\[(.*?)\]|\((.*?)\)|\{(.*?)\}|\[\((.*?)\)\]|\(\((.*?)\)\))?',
    );

    final match = edgeRegex.firstMatch(line);
    if (match != null) {
      final fromId = match.group(1)!;
      final fromLabelRect = match.group(2);
      final fromLabelRound = match.group(3);
      final fromLabelDiamond = match.group(4);
      final fromLabelDb = match.group(5);
      final fromLabelCircle = match.group(6);

      final arrowType = match.group(7)!;
      final edgeLabel = match.group(8);

      final toId = match.group(9)!;
      final toLabelRect = match.group(10);
      final toLabelRound = match.group(11);
      final toLabelDiamond = match.group(12);
      final toLabelDb = match.group(13);
      final toLabelCircle = match.group(14);

      _getOrAddNode(
        graph,
        fromId,
        fromLabelRect ??
            fromLabelRound ??
            fromLabelDiamond ??
            fromLabelDb ??
            fromLabelCircle,
        _getNodeType(
          fromLabelRect,
          fromLabelRound,
          fromLabelDiamond,
          fromLabelDb,
          fromLabelCircle,
        ),
      );

      _getOrAddNode(
        graph,
        toId,
        toLabelRect ??
            toLabelRound ??
            toLabelDiamond ??
            toLabelDb ??
            toLabelCircle,
        _getNodeType(
          toLabelRect,
          toLabelRound,
          toLabelDiamond,
          toLabelDb,
          toLabelCircle,
        ),
      );

      MermaidEdgeStyle style = MermaidEdgeStyle.solid;
      if (arrowType.contains('-.')) {
        style = MermaidEdgeStyle.dashed;
      } else if (arrowType.contains('==')) {
        style = MermaidEdgeStyle.thick;
      }

      graph.edges.add(MermaidEdge(
        fromId: fromId,
        toId: toId,
        label: edgeLabel?.trim(),
        style: style,
      ));
      return;
    }

    // Single node pattern: A[Label] or A
    final nodeRegex = RegExp(
      r'([A-Za-z0-9_\-\.]+)(?:\[(.*?)\]|\((.*?)\)|\{(.*?)\}|\[\((.*?)\)\]|\(\((.*?)\)\))?',
    );
    final nodeMatch = nodeRegex.firstMatch(line);
    if (nodeMatch != null) {
      final id = nodeMatch.group(1)!;
      final labelRect = nodeMatch.group(2);
      final labelRound = nodeMatch.group(3);
      final labelDiamond = nodeMatch.group(4);
      final labelDb = nodeMatch.group(5);
      final labelCircle = nodeMatch.group(6);

      _getOrAddNode(
        graph,
        id,
        labelRect ??
            labelRound ??
            labelDiamond ??
            labelDb ??
            labelCircle,
        _getNodeType(
          labelRect,
          labelRound,
          labelDiamond,
          labelDb,
          labelCircle,
        ),
      );
    }
  }

  static MermaidNodeType _getNodeType(
    String? rect,
    String? round,
    String? diamond,
    String? db,
    String? circle,
  ) {
    if (db != null) return MermaidNodeType.database;
    if (circle != null) return MermaidNodeType.circle;
    if (diamond != null) return MermaidNodeType.diamond;
    if (round != null) return MermaidNodeType.rounded;
    return MermaidNodeType.rectangle;
  }

  static void _getOrAddNode(
    MermaidGraph graph,
    String id,
    String? label,
    MermaidNodeType type,
  ) {
    if (!graph.nodes.containsKey(id)) {
      graph.nodes[id] = MermaidNode(
        id: id,
        label: label ?? id,
        type: type,
      );
    } else if (label != null && label.isNotEmpty) {
      final existing = graph.nodes[id]!;
      graph.nodes[id] = MermaidNode(
        id: id,
        label: label,
        type: type != MermaidNodeType.rectangle ? type : existing.type,
      );
    }
  }

  static void _layoutGraph(MermaidGraph graph) {
    if (graph.nodes.isEmpty) return;

    // Calculate topological level per node
    final inDegree = <String, int>{};
    for (var id in graph.nodes.keys) {
      inDegree[id] = 0;
    }

    final outEdges = <String, List<String>>{};
    for (var edge in graph.edges) {
      inDegree[edge.toId] = (inDegree[edge.toId] ?? 0) + 1;
      outEdges.putIfAbsent(edge.fromId, () => []).add(edge.toId);
    }

    final queue = <String>[];
    for (var entry in inDegree.entries) {
      if (entry.value == 0) {
        queue.add(entry.key);
      }
    }

    if (queue.isEmpty && graph.nodes.isNotEmpty) {
      queue.add(graph.nodes.keys.first);
    }

    final levels = <int, List<String>>{};
    final visited = <String>{};

    for (var id in queue) {
      visited.add(id);
      graph.nodes[id]!.level = 0;
      levels.putIfAbsent(0, () => []).add(id);
    }

    int currentIdx = 0;
    while (currentIdx < queue.length) {
      final currId = queue[currentIdx++];
      final currNode = graph.nodes[currId]!;
      final children = outEdges[currId] ?? [];

      for (var childId in children) {
        final childNode = graph.nodes[childId]!;
        final newLevel = currNode.level + 1;
        if (newLevel > childNode.level) {
          if (visited.contains(childId)) {
            levels[childNode.level]?.remove(childId);
          }
          childNode.level = newLevel;
          levels.putIfAbsent(newLevel, () => []).add(childId);
          if (!visited.contains(childId)) {
            visited.add(childId);
            queue.add(childId);
          }
        }
      }
    }

    // Add unvisited isolated nodes
    for (var id in graph.nodes.keys) {
      if (!visited.contains(id)) {
        graph.nodes[id]!.level = 0;
        levels.putIfAbsent(0, () => []).add(id);
      }
    }

    // Assign positions based on layout direction
    const double nodeWidth = 140;
    const double nodeHeight = 50;
    const double hGap = 60;
    const double vGap = 80;

    final isHoriz = graph.isHorizontal;

    final sortedLevels = levels.keys.toList()..sort();
    for (var lvl in sortedLevels) {
      final nodeList = levels[lvl]!;
      for (int i = 0; i < nodeList.length; i++) {
        final id = nodeList[i];
        final node = graph.nodes[id]!;
        node.size = const Size(nodeWidth, nodeHeight);

        if (isHoriz) {
          node.position = Offset(
            lvl * (nodeWidth + hGap) + 40,
            i * (nodeHeight + vGap) + 40,
          );
        } else {
          node.position = Offset(
            i * (nodeWidth + hGap) + 40,
            lvl * (nodeHeight + vGap) + 40,
          );
        }
      }
    }
  }
}
