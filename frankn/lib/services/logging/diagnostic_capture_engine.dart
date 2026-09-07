import 'dart:convert';
import 'package:frankn/services/logging/frankn_log_frame.dart';
import 'package:frankn/services/logging/frankn_state_snapshot.dart';

/// Bounded stateful diagnostic capture session object.
/// Temporarily records detailed telemetry frames and runtime state snapshots
/// at capture START and END for bug diagnostics without unbounded memory growth.
class DiagnosticCaptureSession {
  final String captureId;
  final int maxFrameLimit;
  final int startTimeMs;

  FranknStateSnapshot? startSnapshot;
  FranknStateSnapshot? endSnapshot;
  final List<FranknLogFrame> capturedFrames = [];

  bool isActive = false;
  int? stopTimeMs;

  DiagnosticCaptureSession({
    required this.captureId,
    this.maxFrameLimit = 10000,
  }) : startTimeMs = DateTime.now().millisecondsSinceEpoch;

  void start(FranknStateSnapshot initialSnapshot) {
    startSnapshot = initialSnapshot;
    capturedFrames.clear();
    isActive = true;
  }

  void captureFrame(FranknLogFrame frame) {
    if (!isActive) return;
    if (capturedFrames.length < maxFrameLimit) {
      capturedFrames.add(frame);
    }
  }

  void stop(FranknStateSnapshot finalSnapshot) {
    endSnapshot = finalSnapshot;
    stopTimeMs = DateTime.now().millisecondsSinceEpoch;
    isActive = false;
  }

  int get durationMs {
    final end = stopTimeMs ?? DateTime.now().millisecondsSinceEpoch;
    return end - startTimeMs;
  }

  Map<String, dynamic> toJson() => {
        'capture_id': captureId,
        'start_time_ms': startTimeMs,
        'stop_time_ms': stopTimeMs,
        'duration_ms': durationMs,
        'start_snapshot': startSnapshot?.toJson(),
        'end_snapshot': endSnapshot?.toJson(),
        'frame_count': capturedFrames.length,
        'frames': capturedFrames.map((f) => f.toJson()).toList(),
      };

  String generateMarkdownReport({
    required String clientVersion,
    required String osInfo,
  }) {
    final buffer = StringBuffer();
    buffer.writeln("# Frankn Diagnostic Capture Report");
    buffer.writeln("- **Capture ID**: $captureId");
    buffer.writeln("- **Timestamp**: ${DateTime.fromMillisecondsSinceEpoch(startTimeMs).toIso8601String()}");
    buffer.writeln("- **Duration**: ${(durationMs / 1000).toStringAsFixed(1)}s");
    buffer.writeln("- **Captured Frames**: ${capturedFrames.length} / $maxFrameLimit");
    buffer.writeln("- **Client Version**: $clientVersion");
    buffer.writeln("- **OS Info**: $osInfo\n");

    if (startSnapshot != null) {
      buffer.writeln("## 1. Initial State Snapshot (CAPTURE_START)");
      buffer.writeln("```json");
      buffer.writeln(const JsonEncoder.withIndent('  ').convert(startSnapshot!.toJson()));
      buffer.writeln("```\n");
    }

    buffer.writeln("## 2. Captured Telemetry Stream");
    buffer.writeln("```text");
    for (final f in capturedFrames) {
      final timeStr = DateTime.fromMillisecondsSinceEpoch(f.timestampMs)
          .toIso8601String()
          .substring(11, 19);
      final gen = f.generationId != null ? "[${f.generationId}]" : "";
      final hsid = f.hostSessionId != null ? "[S:${f.hostSessionId}]" : "";
      final csid = f.capabilitySessionId != null ? "[C:${f.capabilitySessionId}]" : "";
      final nid = f.nodeId != null ? "[N:${f.nodeId}]" : "";
      buffer.writeln("[$timeStr][${f.category.code}][${f.level.name.toUpperCase()}]$gen$hsid$csid$nid[${f.subsystem}] ${f.message}");
    }
    buffer.writeln("```\n");

    if (endSnapshot != null) {
      buffer.writeln("## 3. Final State Snapshot (CAPTURE_END)");
      buffer.writeln("```json");
      buffer.writeln(const JsonEncoder.withIndent('  ').convert(endSnapshot!.toJson()));
      buffer.writeln("```\n");
    }

    return buffer.toString();
  }
}
