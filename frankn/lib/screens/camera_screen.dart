import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:uuid/uuid.dart';
import 'package:frankn/services/client_rtc/rtc.dart';
import 'package:frankn/services/rtc_thin_client.dart';

class CameraScreen extends StatefulWidget {
  final String nodeName;
  final String nodeId;
  final String capabilityId;

  const CameraScreen({
    super.key,
    required this.nodeName,
    required this.nodeId,
    this.capabilityId = 'camera',
  });

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  final RTCVideoRenderer _renderer = RTCVideoRenderer();
  NodePeerSession? _session;
  bool _isRendererInitialized = false;

  @override
  void initState() {
    super.initState();
    _initCameraSession();
  }

  Future<void> _initCameraSession() async {
    await _renderer.initialize();
    if (!mounted) return;
    setState(() {
      _isRendererInitialized = true;
    });

    final sessionId = const Uuid().v4();
    final sessionManager = RtcThinClient().capabilitySessionManager;

    _session = await sessionManager.requestCapabilitySession(
      sessionId: sessionId,
      capabilityId: widget.capabilityId,
      providerId: widget.nodeId,
    );

    _session!.addListener(_onSessionUpdate);
  }

  void _onSessionUpdate() {
    if (!mounted || _session == null) return;

    if (_session!.mediaStream != null && _renderer.srcObject != _session!.mediaStream) {
      setState(() {
        _renderer.srcObject = _session!.mediaStream;
      });
    } else {
      setState(() {});
    }
  }

  @override
  void dispose() {
    if (_session != null) {
      _session!.removeListener(_onSessionUpdate);
      final sessionId = _session!.sessionId;
      RtcClient().capabilitySessionManager.closeSession(sessionId);
    }
    _renderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = _session?.state ?? NodeSessionState.idle;
    final error = _session?.error;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.cyanAccent),
        title: Text(
          "📹 ${widget.nodeName} // CAMERA",
          style: const TextStyle(
            color: Colors.cyanAccent,
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.cyanAccent),
            onPressed: () {
              if (_session != null) {
                final sid = _session!.sessionId;
                RtcClient().capabilitySessionManager.closeSession(sid);
              }
              _initCameraSession();
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          Center(
            child: _isRendererInitialized && _renderer.srcObject != null
                ? RTCVideoView(
                    _renderer,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(color: Colors.cyanAccent),
                      const SizedBox(height: 16),
                      Text(
                        "Connecting P2P stream... (${state.name})",
                        style: const TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                    ],
                  ),
          ),
          Positioned(
            top: 16,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: state == NodeSessionState.connected
                          ? Colors.greenAccent
                          : (state == NodeSessionState.failed
                              ? Colors.redAccent
                              : Colors.orangeAccent),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    state.name.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (error != null)
            Positioned(
              bottom: 20,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade900.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.redAccent),
                ),
                child: Text(
                  "ERROR: $error",
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
