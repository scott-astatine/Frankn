import 'package:frankn/services/logging/diagnostic_capture_engine.dart';
import 'package:frankn/services/logging/frankn_log_frame.dart';
import 'package:frankn/services/logging/frankn_state_snapshot.dart';
import 'package:frankn/services/logging/ipc_transport_engine.dart';
import 'package:frankn/services/logging/redaction_engine.dart';

/// Authoritative Background Isolate Telemetry & Logging Engine.
///
/// Invariants:
/// - Authoritative logger lives entirely in the background isolate.
/// - Fully transport-agnostic, domain-agnostic, and UI-agnostic.
/// - Executes zero-allocation producer-side level checks BEFORE payload or message construction.
/// - Unsubscribing UI IPC never mutates background logger storage policy.
class FranknLogger {
  static final FranknLogger instance = FranknLogger._internal();
  factory FranknLogger() => instance;
  FranknLogger._internal();

  // Category Level Overrides
  final Map<LogCategory, LogLevel> _categoryLevels = {};

  // Redaction Security Boundary
  RedactionEngineContract redactionEngine = RedactionEngine();

  // IPC Transport & Rate Limiter Engine
  final IpcTransportEngine ipcEngine = IpcTransportEngine();

  // Lossless Bounded Ring Buffer (2,000 frames)
  final List<FranknLogFrame> _ringBuffer = [];
  static const int maxBufferSize = 2000;

  // Active Diagnostic Capture Session (Optional)
  DiagnosticCaptureSession? _activeCapture;

  /// Fast Producer-Side Level Check:
  /// Evaluated BEFORE expensive string formatting or metadata map construction.
  bool shouldLog(LogCategory category, LogLevel level) {
    final minLevel = _categoryLevels[category] ?? LogLevel.debug;
    return level.value >= minLevel.value;
  }

  /// Configures custom log level override for a specific category.
  void setCategoryLogLevel(LogCategory category, LogLevel level) {
    _categoryLevels[category] = level;
  }

  /// Authoritative Log Entry Point:
  /// Sanitizes secrets, pushes to ring buffer, writes to stdout, and dispatches IPC if subscribed.
  void log({
    required LogLevel level,
    required LogCategory category,
    required String subsystem,
    required String message,
    String? generationId,
    String? hostSessionId,
    String? capabilitySessionId,
    String? nodeId,
    Map<String, dynamic>? metadata,
  }) {
    if (!shouldLog(category, level)) return;

    // 1. Mandatory Secret Redaction Boundary
    final safeMessage = redactionEngine.sanitizeMessage(message);
    final safeMetadata = redactionEngine.sanitizeMetadata(metadata);

    final frame = FranknLogFrame(
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      level: level,
      category: category,
      subsystem: subsystem,
      message: safeMessage,
      generationId: generationId,
      hostSessionId: hostSessionId,
      capabilitySessionId: capabilitySessionId,
      nodeId: nodeId,
      metadata: safeMetadata,
    );

    // 2. Add to Ring Buffer
    _ringBuffer.add(frame);
    if (_ringBuffer.length > maxBufferSize) {
      _ringBuffer.removeAt(0);
    }

    // 3. Record in Diagnostic Capture Session if active
    if (_activeCapture != null && _activeCapture!.isActive) {
      _activeCapture!.captureFrame(frame);
    }

    // 4. Independent stdout / logcat Sink (Isolated from UI IPC)
    _writeToStdout(frame);

    // 5. IPC Delivery Gate (Subscribed & Bounded)
    if (ipcEngine.shouldDispatch(frame)) {
      final payload = ipcEngine.preparePayload(frame);
      if (payload != null) {
        _dispatchIpcPayload(payload);
      }
    }
  }

  /// Formats and outputs log frame to stdout for terminal/logcat debugging.
  void _writeToStdout(FranknLogFrame frame) {
    final timeStr = DateTime.fromMillisecondsSinceEpoch(frame.timestampMs)
        .toIso8601String()
        .substring(11, 19);
    final gen = frame.generationId != null ? "[${frame.generationId}]" : "";
    final hsid = frame.hostSessionId != null ? "[S:${frame.hostSessionId}]" : "";
    final csid = frame.capabilitySessionId != null ? "[C:${frame.capabilitySessionId}]" : "";
    final nid = frame.nodeId != null ? "[N:${frame.nodeId}]" : "";
    print("[$timeStr][${frame.category.code}][${frame.level.name.toUpperCase()}]$gen$hsid$csid$nid[${frame.subsystem}] ${frame.message}");
  }

  /// Hook for sending serialized IPC payload to main isolate.
  /// Subclassed or wired by IPC bridge in background isolate handler.
  void Function(Map<String, dynamic> payload)? ipcSink;

  void _dispatchIpcPayload(Map<String, dynamic> payload) {
    ipcSink?.call(payload);
  }

  // ===========================================================================
  // SUBSCRIPTION LIFECYCLE API
  // ===========================================================================

  /// UI Subscribes to Live IPC Log Stream.
  /// NOTE: Enables IPC delivery only. Does NOT mutate global category thresholds.
  List<FranknLogFrame> subscribeUiLogs({
    required Set<LogCategory> categories,
    required LogLevel minLevel,
    String? generationFilter,
    IpcPolicy policy = IpcPolicy.live,
  }) {
    ipcEngine.subscriptionConfig = IpcSubscriptionConfig(
      isUiSubscribed: true,
      subscribedCategories: categories,
      minSubscribedLevel: minLevel,
      generationFilter: generationFilter,
    );
    ipcEngine.policy = policy;

    return getRingBufferSnapshot(
      categories: categories,
      minLevel: minLevel,
      generationFilter: generationFilter,
    );
  }

  /// UI Unsubscribes from Live IPC Log Stream when log screen closes.
  /// NOTE: Disables UI IPC streaming ONLY. Background logger configuration & stdout UNTOUCHED.
  void unsubscribeUiLogs() {
    ipcEngine.subscriptionConfig = const IpcSubscriptionConfig(isUiSubscribed: false);
    // Keep logger's internal policy intact; only set subscriber state to inactive
  }

  /// Queries snapshot of historical ring buffer frames.
  List<FranknLogFrame> getRingBufferSnapshot({
    Set<LogCategory>? categories,
    LogLevel? minLevel,
    String? generationFilter,
    String? hostSessionFilter,
  }) {
    return _ringBuffer.where((f) {
      if (categories != null && !categories.contains(f.category)) return false;
      if (minLevel != null && f.level.value < minLevel.value) return false;
      if (generationFilter != null &&
          generationFilter.isNotEmpty &&
          f.generationId != generationFilter) {
        return false;
      }
      if (hostSessionFilter != null &&
          hostSessionFilter.isNotEmpty &&
          f.hostSessionId != hostSessionFilter) {
        return false;
      }
      return true;
    }).toList();
  }

  // ===========================================================================
  // DIAGNOSTIC CAPTURE API
  // ===========================================================================

  DiagnosticCaptureSession startDiagnosticCapture({
    required String captureId,
    required FranknStateSnapshot startSnapshot,
    int maxFrameLimit = 10000,
  }) {
    final session = DiagnosticCaptureSession(
      captureId: captureId,
      maxFrameLimit: maxFrameLimit,
    );
    session.start(startSnapshot);
    _activeCapture = session;
    return session;
  }

  DiagnosticCaptureSession? stopDiagnosticCapture(FranknStateSnapshot endSnapshot) {
    if (_activeCapture == null) return null;
    final session = _activeCapture!;
    session.stop(endSnapshot);
    _activeCapture = null;
    return session;
  }
}
