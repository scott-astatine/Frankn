import 'package:audio_service/audio_service.dart';
import 'package:frankn/services/rtc_thin_client.dart';
import 'package:frankn/utils/utils.dart';
import 'package:frankn/utils/dc_msg_util.dart';
import 'package:volume_controller/volume_controller.dart';

late AudioHandler audioHandler;
FranknAudioHandler? _franknAudioHandler;

FranknAudioHandler? get franknAudioHandlerInstance => _franknAudioHandler;

Future<void> initAudioService() async {
  audioHandler = await AudioService.init(
    builder: () {
      _franknAudioHandler = FranknAudioHandler();
      print("Initializing Audio Service.");
      return _franknAudioHandler!;
    },
    config: AudioServiceConfig(
      androidNotificationChannelId: 'com.astatine.frankn.channel.audio',
      androidNotificationChannelName: 'Frankn Media',
      androidNotificationOngoing: true,
      androidNotificationIcon: 'drawable/ic_notification',
      androidStopForegroundOnPause: true,
      preloadArtwork: true,
    ),
  );
}

class FranknAudioHandler extends BaseAudioHandler {
  final RtcThinClient _client = RtcThinClient();
  double _currentHostVolume = 0.5;
  double _lastPhoneVolume = 0.0;

  FranknAudioHandler() {
    _initVolumeListener();

    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          MediaControl.rewind,
          MediaControl.play,
          MediaControl.fastForward,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.fastForward,
          MediaAction.rewind,
          MediaAction.play,
          MediaAction.pause,
          MediaAction.playPause,
          MediaAction.skipToNext,
          MediaAction.skipToPrevious,
        },
        processingState: AudioProcessingState.ready,
        playing: false,
      ),
    );
  }

  void _initVolumeListener() {
    VolumeController.instance.showSystemUI = true;
    VolumeController.instance.getVolume().then((v) => _lastPhoneVolume = v);

    VolumeController.instance.addListener((newPhoneVolume) {
      if (_client.currentHostState != HostConnectionState.authenticated) return;

      if (newPhoneVolume > _lastPhoneVolume) {
        // Volume Up knob
        _currentHostVolume = (_currentHostVolume + 0.05).clamp(0.0, 1.5);
        _client.sendDcMsg(DcMsgSetVolume(
          level: _currentHostVolume,
        ));
      } else if (newPhoneVolume < _lastPhoneVolume) {
        // Volume Down knob
        _currentHostVolume = (_currentHostVolume - 0.05).clamp(0.0, 1.5);
        _client.sendDcMsg(DcMsgSetVolume(
          level: _currentHostVolume,
        ));
      }
      _lastPhoneVolume = newPhoneVolume;
    });
  }

  void updateMediaState({
    required bool isPlaying,
    String? title,
    String? artist,
    String? playerName,
    Duration? duration,
    Duration? position,
    Uri? artUri,
    double? volume,
  }) {
    if (volume != null) {
      _currentHostVolume = volume;
    }
    final currentItem = mediaItem.value;

    if (title != null ||
        artist != null ||
        duration != null ||
        artUri != null ||
        playerName != null) {
      final hostLabel = _client.currentHostName ?? 'Remote PC';
      mediaItem.add(
        MediaItem(
          id: 'frankn_remote_media',
          album: hostLabel,
          title: title ?? currentItem?.title ?? 'No Media',
          artist: artist ?? currentItem?.artist ?? 'Frankn Host',
          duration: duration ?? currentItem?.duration,
          artUri: artUri ?? currentItem?.artUri,
        ),
      );
    }

    playbackState.add(
      playbackState.value.copyWith(
        playing: isPlaying,
        updatePosition: position ?? playbackState.value.position,
        bufferedPosition: position ?? Duration.zero,
        controls: [
          MediaControl.skipToPrevious,
          MediaControl.rewind,
          isPlaying ? MediaControl.pause : MediaControl.play,
          MediaControl.fastForward,
          MediaControl.skipToNext,
        ],
      ),
    );
  }

  @override
  Future<void> play() async {
    if (_client.currentHostState == HostConnectionState.authenticated) {
      _client.sendDcMsg(const DcMsgTogglePlayPause());
    }
  }

  @override
  Future<void> pause() async {
    if (_client.currentHostState == HostConnectionState.authenticated) {
      _client.sendDcMsg(const DcMsgTogglePlayPause());
    }
  }

  @override
  Future<void> skipToNext() async {
    if (_client.currentHostState == HostConnectionState.authenticated) {
      _client.sendDcMsg(const DcMsgPlayNextTrack());
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_client.currentHostState == HostConnectionState.authenticated) {
      _client.sendDcMsg(const DcMsgPlayPreviousTrack());
    }
  }

  @override
  Future<void> fastForward() async {
    if (_client.currentHostState == HostConnectionState.authenticated) {
      final newPos = playbackState.value.position.inMicroseconds + 10000000;
      _client.sendDcMsg(DcMsgSeek(position: newPos));
    }
  }

  @override
  Future<void> rewind() async {
    if (_client.currentHostState == HostConnectionState.authenticated) {
      final newPos = playbackState.value.position.inMicroseconds - 10000000;
      _client.sendDcMsg(DcMsgSeek(
        position: newPos < 0 ? 0 : newPos,
      ));
    }
  }

  @override
  Future<void> seek(Duration position) async {
    if (_client.currentHostState == HostConnectionState.authenticated) {
      _client.sendDcMsg(DcMsgSeek(
        position: position.inMicroseconds,
      ));
    }
  }
}
