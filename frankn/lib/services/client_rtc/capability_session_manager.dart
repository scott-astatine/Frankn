part of 'rtc.dart';

/// Callback for sending ClientSignal messages to Host (to be forwarded to Node).
typedef SendClientSignalFn = Future<void> Function({
  required String sessionId,
  required Map<String, dynamic> signal,
});

/// Callback for sending ActivateCapability / DeactivateCapability to Host.
typedef HostCapabilityCmdFn = Future<void> Function(
  String action, // 'activate' or 'deactivate'
  Map<String, dynamic> payload,
);

/// Manages active Client ↔ Node capability sessions on the client.
class CapabilitySessionManager extends ChangeNotifier {
  final Map<String, NodePeerSession> _sessions = {};
  final SendClientSignalFn _sendClientSignal;
  final HostCapabilityCmdFn _sendHostCmd;

  Map<String, NodePeerSession> get sessions => Map.unmodifiable(_sessions);

  CapabilitySessionManager({
    required SendClientSignalFn onSendClientSignal,
    required HostCapabilityCmdFn onSendHostCmd,
  })  : _sendClientSignal = onSendClientSignal,
        _sendHostCmd = onSendHostCmd;

  /// Creates and registers a new NodePeerSession in Requesting state.
  NodePeerSession createSession({
    required String sessionId,
    required String nodeId,
    required String capabilityId,
  }) {
    if (_sessions.containsKey(sessionId)) {
      return _sessions[sessionId]!;
    }

    final session = NodePeerSession(
      sessionId: sessionId,
      nodeId: nodeId,
      capabilityId: capabilityId,
      onSendSignal: ({required sessionId, required signal}) =>
          _sendClientSignal(sessionId: sessionId, signal: signal),
    );

    session.updateState(NodeSessionState.requesting);
    _sessions[sessionId] = session;
    notifyListeners();
    return session;
  }

  /// Retrieves an existing session by ID.
  NodePeerSession? getSession(String sessionId) => _sessions[sessionId];

  /// Handles incoming `HostSignal` forwarded from Host.
  Future<void> handleHostSignal({
    required String sessionId,
    required Map<String, dynamic> signal,
  }) async {
    RtcThinClient().log('[CAPABILITY_MGR] Routing HostSignal [$sessionId] to target NodePeerSession...');
    final session = _sessions[sessionId];
    if (session != null) {
      await session.handleSignal(signal);
    } else {
      RtcThinClient().log('[CAPABILITY_MGR] Warning: No active NodePeerSession found for ID [$sessionId]');
    }
  }

  /// Handles incoming `CapabilityActivationStatus` from Host.
  void handleActivationStatus({
    required String sessionId,
    required String statusStr,
    String? error,
  }) {
    RtcThinClient().log('[CAPABILITY_MGR] CapabilityActivationStatus [$sessionId]: status=$statusStr${error != null ? ", error=$error" : ""}');
    final session = _sessions[sessionId];
    if (session == null) {
      RtcThinClient().log('[CAPABILITY_MGR] Warning: Activation status received for unknown session [$sessionId]');
      return;
    }

    switch (statusStr.toLowerCase()) {
      case 'active':
        if (session.state == NodeSessionState.requesting ||
            session.state == NodeSessionState.pending) {
          session.updateState(NodeSessionState.pending);
        }
        break;
      case 'failed':
        session.updateState(NodeSessionState.failed, error ?? 'Activation failed');
        break;
      case 'closed':
        session.updateState(NodeSessionState.closed);
        removeSession(sessionId);
        break;
      default:
        break;
    }
  }

  /// Requests the Host to activate a capability session on a Node.
  Future<NodePeerSession> requestCapabilitySession({
    required String sessionId,
    required String capabilityId,
    String? providerId,
    Map<String, dynamic>? properties,
  }) async {
    RtcThinClient().log('[CAPABILITY_MGR] Requesting capability session [$sessionId]: capability=$capabilityId, provider=$providerId');
    final session = createSession(
      sessionId: sessionId,
      nodeId: providerId ?? 'unknown',
      capabilityId: capabilityId,
    );

    await _sendHostCmd('activate', {
      'capability_id': capabilityId,
      'session_id': sessionId,
      if (providerId != null) 'provider_id': providerId,
      if (properties != null) 'properties': properties,
    });

    return session;
  }

  /// Requests the Host to deactivate a capability session, and disposes the session locally.
  Future<void> closeSession(String sessionId) async {
    final session = _sessions[sessionId];
    if (session != null) {
      await _sendHostCmd('deactivate', {
        'capability_id': session.capabilityId,
        'session_id': sessionId,
      });

      await session.dispose();
      removeSession(sessionId);
    }
  }

  /// Removes session from registry without calling dispose.
  void removeSession(String sessionId) {
    if (_sessions.containsKey(sessionId)) {
      _sessions.remove(sessionId);
      notifyListeners();
    }
  }

  /// Closes all active Node capability sessions (e.g. on Host disconnect).
  Future<void> closeAllSessions() async {
    final list = _sessions.values.toList();
    _sessions.clear();
    for (final session in list) {
      await session.dispose();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    closeAllSessions();
    super.dispose();
  }
}
