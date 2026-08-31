import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:uuid/uuid.dart';
import 'package:frankn/services/client_rtc/rtc.dart';
import 'package:frankn/services/rtc_thin_client.dart';

class MicrophoneCapabilityController extends ChangeNotifier {
  final String capabilityId;

  NodePeerSession? _session;
  String? _currentProviderId;
  MediaStreamTrack? _audioTrack;
  bool _isInitializing = false;
  bool _isMuted = false;

  NodePeerSession? get session => _session;
  String? get currentProviderId => _currentProviderId;
  NodeSessionState get state => _session?.state ?? NodeSessionState.idle;
  String? get error => _session?.error;
  MediaStream? get stream => _session?.mediaStream;
  MediaStreamTrack? get audioTrack => _audioTrack;
  bool get isMuted => _isMuted;

  MicrophoneCapabilityController({
    this.capabilityId = 'microphone',
  });

  Future<void> startSession(String providerId) async {
    if (_isInitializing) return;
    _isInitializing = true;

    try {
      await stopSession();

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
      RtcThinClient().log('[MIC_CONTROLLER] Error starting session for provider [$providerId]: $e');
    } finally {
      _isInitializing = false;
      notifyListeners();
    }
  }

  void _onSessionUpdated() {
    if (_session != null && _session!.mediaStream != null) {
      final audioTracks = _session!.mediaStream!.getAudioTracks();
      if (audioTracks.isNotEmpty) {
        _audioTrack = audioTracks.first;
      }
    }
    notifyListeners();
  }

  void toggleMute() {
    if (_audioTrack != null) {
      _isMuted = !_isMuted;
      _audioTrack!.enabled = !_isMuted;
      notifyListeners();
    }
  }

  Future<void> stopSession() async {
    if (_session != null) {
      _session!.removeListener(_onSessionUpdated);
      final sid = _session!.sessionId;
      _session = null;
      _audioTrack = null;
      await RtcClient().capabilitySessionManager.closeSession(sid);
      notifyListeners();
    }
  }

  @override
  void dispose() {
    stopSession();
    super.dispose();
  }
}
