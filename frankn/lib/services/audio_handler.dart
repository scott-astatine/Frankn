import 'package:audio_service/audio_service.dart';
import 'package:frankn/services/rtc/rtc.dart';
import 'package:frankn/utils/utils.dart';
import 'package:volume_controller/volume_controller.dart';

late AudioHandler audioHandler;

Future<void> initAudioService() async {
  audioHandler = await AudioService.init(
    builder: () => FranknAudioHandler(),
    config: AudioServiceConfig(
      androidNotificationChannelId: 'com.astatine.frankn.channel.audio',
      androidNotificationChannelName: 'Frankn Media',
      androidNotificationOngoing: true,
      androidNotificationIcon: 'mipmap/ic_launcher',
      androidStopForegroundOnPause: true,
      preloadArtwork: true,
    ),
  );
}

class FranknAudioHandler extends BaseAudioHandler {
  final RtcClient _client = RtcClient();

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
        },
        processingState: AudioProcessingState.ready,
        playing: false,
      ),
    );
  }

  void _initVolumeListener() {
    VolumeController.instance.showSystemUI = true;
    VolumeController.instance.addListener((volume) {
      // ONLY send if we are actually connected and authenticated
      // This prevents the "Not authenticated" error on startup
      if (_client.currentHostState == HostConnectionState.authenticated) {
        _client.sendDcMsg({DcMsg.Key: DcMsg.SetVolume, "level": volume});
      }
    });
  }

  void updateMediaState({
    String? status,
    String? title,
    String? artist,
    String? playerName,
    Duration? duration,
    Duration? position,
    Uri? artUri,
    double? volume,
  }) {
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
          title: "[$hostLabel] ${title ?? currentItem?.title ?? 'No Media'}",
          artist: artist ?? currentItem?.artist ?? 'Frankn Host',
          duration: duration ?? currentItem?.duration,
          artUri: artUri ?? currentItem?.artUri,
        ),
      );
    }

    if (status != null || position != null) {
      bool isPlaying =
          (status ?? "").toLowerCase().contains("playing") ||
          (status == null && playbackState.value.playing);

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
  }

  @override
  Future<void> play() async {
    if (_client.currentHostState == HostConnectionState.authenticated) {
      _client.sendDcMsg({DcMsg.Key: DcMsg.TogglePlayPause});
    }
  }

  @override
  Future<void> pause() async {
    if (_client.currentHostState == HostConnectionState.authenticated) {
      _client.sendDcMsg({DcMsg.Key: DcMsg.TogglePlayPause});
    }
  }

  @override
  Future<void> skipToNext() async {
    if (_client.currentHostState == HostConnectionState.authenticated) {
      _client.sendDcMsg({DcMsg.Key: DcMsg.PlayNextTrack});
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_client.currentHostState == HostConnectionState.authenticated) {
      _client.sendDcMsg({DcMsg.Key: DcMsg.PlayPreviousTrack});
    }
  }

  @override
  Future<void> fastForward() async {
    if (_client.currentHostState == HostConnectionState.authenticated) {
      final newPos = playbackState.value.position.inMicroseconds + 10000000;
      _client.sendDcMsg({DcMsg.Key: DcMsg.Seek, "position": newPos});
    }
  }

  @override
  Future<void> rewind() async {
    if (_client.currentHostState == HostConnectionState.authenticated) {
      final newPos = playbackState.value.position.inMicroseconds - 10000000;
      _client.sendDcMsg({
        DcMsg.Key: DcMsg.Seek,
        "position": newPos < 0 ? 0 : newPos,
      });
    }
  }

  @override
  Future<void> seek(Duration position) async {
    if (_client.currentHostState == HostConnectionState.authenticated) {
      _client.sendDcMsg({
        DcMsg.Key: DcMsg.Seek,
        "position": position.inMicroseconds,
      });
    }
  }
}

