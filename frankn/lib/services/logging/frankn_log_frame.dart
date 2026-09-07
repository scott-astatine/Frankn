import 'dart:convert';

/// Severity levels for Frankn telemetry events.
enum LogLevel {
  trace(0),
  debug(1),
  info(2),
  warn(3),
  error(4),
  fatal(5);

  final int value;
  const LogLevel(this.value);
}

/// Domain categories for telemetry events.
/// Transport-agnostic & domain-agnostic taxonomy.
enum LogCategory {
  signaling("SIG"),
  webrtc("RTC"),
  capabilities("CAP"),
  fileTransfer("FS"),
  media("MEDIA"),
  security("AUTH"),
  system("SYS");

  final String code;
  const LogCategory(this.code);
}

/// Strongly-typed, immutable telemetry event frame.
/// Preformatted debug strings are prohibited in favor of structured data.
class FranknLogFrame {
  final int timestampMs;
  final LogLevel level;
  final LogCategory category;
  final String subsystem; // Sub-component tag (e.g. "ICE", "FSM", "DC_DIAG")
  final String message;

  // Correlation Hierarchical Identifiers
  // Hierarchy: generationId -> hostSessionId -> capabilitySessionId
  final String? generationId; // Level 1: Connection Attempt Scope
  final String? hostSessionId; // Level 2: Authenticated Host Session Scope
  final String? capabilitySessionId; // Level 3: Active Capability Stream Scope

  // Entity Identity Identifier (Public Key Hash / Peer Hardware Identity)
  final String? nodeId; // Provider Node ID / Hardware Identity

  // Optional Structured Metadata Map
  final Map<String, dynamic>? metadata;

  const FranknLogFrame({
    required this.timestampMs,
    required this.level,
    required this.category,
    required this.subsystem,
    required this.message,
    this.generationId,
    this.hostSessionId,
    this.capabilitySessionId,
    this.nodeId,
    this.metadata,
  });

  Map<String, dynamic> toJson() => {
        'ts': timestampMs,
        'lvl': level.index,
        'cat': category.index,
        'sub': subsystem,
        'msg': message,
        if (generationId != null) 'gen': generationId,
        if (hostSessionId != null) 'hsid': hostSessionId,
        if (capabilitySessionId != null) 'csid': capabilitySessionId,
        if (nodeId != null) 'nid': nodeId,
        if (metadata != null) 'meta': metadata,
      };

  factory FranknLogFrame.fromJson(Map<String, dynamic> map) => FranknLogFrame(
        timestampMs: map['ts'] as int,
        level: LogLevel.values[map['lvl'] as int],
        category: LogCategory.values[map['cat'] as int],
        subsystem: map['sub'] as String,
        message: map['msg'] as String,
        generationId: map['gen'] as String?,
        hostSessionId: map['hsid'] as String?,
        capabilitySessionId: map['csid'] as String?,
        nodeId: map['nid'] as String?,
        metadata: map['meta'] is Map<String, dynamic>
            ? map['meta'] as Map<String, dynamic>
            : null,
      );

  String toEncodedJson() => jsonEncode(toJson());

  factory FranknLogFrame.fromEncodedJson(String source) =>
      FranknLogFrame.fromJson(jsonDecode(source) as Map<String, dynamic>);
}
