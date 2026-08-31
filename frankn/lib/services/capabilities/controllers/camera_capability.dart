import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:uuid/uuid.dart';
import 'package:frankn/services/client_rtc/rtc.dart';
import 'package:frankn/services/rtc_thin_client.dart';

class CameraCapabilityController extends ChangeNotifier {
  final String capabilityId;
  final RTCVideoRenderer renderer = RTCVideoRenderer();

  NodePeerSession? _session;
  String? _currentProviderId;
  bool _isRendererInitialized = false;
  bool _isInitializing = false;

  NodePeerSession? get session => _session;
  String? get currentProviderId => _currentProviderId;
  bool get isRendererInitialized => _isRendererInitialized;
  NodeSessionState get state => _session?.state ?? NodeSessionState.idle;
  String? get error => _session?.error;
  MediaStream? get stream => _session?.mediaStream;

  CameraCapabilityController({
    this.capabilityId = 'camera',
  });

  Future<void> initializeRenderer() async {
    if (_isRendererInitialized) return;
    await renderer.initialize();
    _isRendererInitialized = true;
    notifyListeners();
  }

  Future<void> startSession(String providerId) async {
    if (_isInitializing) return;
    _isInitializing = true;

    try {
      await stopSession();

      if (!_isRendererInitialized) {
        await initializeRenderer();
      }

      _currentProviderId = providerId;
      final sessionId = const Uuid().v4();
      final sessionManager = RtcThinClient().capabilitySessionManager;

      _session = await sessionManager.requestCapabilitySession(
        sessionId: sessionId,
        capabilityId: capabilityId,
        providerId: providerId,
      );

      _session!.addListener(_onSessionUpdated);
      _onSessionUpdated();
    } catch (e) {
      RtcThinClient().log('[CAMERA_CONTROLLER] Error starting session for provider [$providerId]: $e');
    } finally {
      _isInitializing = false;
      notifyListeners();
    }
  }

  void _onSessionUpdated() {
    if (_session != null && _session!.mediaStream != null) {
      if (renderer.srcObject != _session!.mediaStream) {
        renderer.srcObject = _session!.mediaStream;
      }
    }
    notifyListeners();
  }

  Future<void> stopSession() async {
    if (_session != null) {
      _session!.removeListener(_onSessionUpdated);
      final sid = _session!.sessionId;
      _session = null;
      await RtcClient().capabilitySessionManager.closeSession(sid);
      renderer.srcObject = null;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    stopSession();
    renderer.dispose();
    super.dispose();
  }
}
