/// This mixin handles the formatting and routing of commands to the appropriate
/// WebRTC data channels. It manages authentication tokens, message IDs, and
/// channel selection based on command type.
///
/// Commands are automatically routed to:
/// - fsChannel: File system operations (ls, get_file, delete_file, uploads)
/// - mediaChannel: Media control (volume, playback, sync)
/// - dataChannel: Everything else (power, processes, SSH, etc.)
part of 'rtc.dart';

mixin RtcCommands on RtcClientBase {
  /// Initiates the Argon2id challenge-response authentication process.
  ///
  /// Stores the password for later use in the challenge response and sends
  /// an authentication request to the host to begin the security handshake.
  @override
  void authenticate(String password) {
    currentPassword = password;
    log("Requesting Authentication...");
    sendHostMessage({'type': DcMsg.AuthRequest, 'timestamp': getTimestamp()});
  }

  /// Starts an SSH terminal session on the connected host.
  ///
  /// The host will allocate a PTY and begin forwarding terminal data
  /// through the SSH data channel for remote shell access.
  void startSsh() {
    sendDcMsg({DcMsg.Key: DcMsg.StartSsh});
  }

  /// Terminates the active SSH terminal session on the host.
  ///
  /// Cleans up the PTY allocation and stops terminal data forwarding.
  void stopSsh() {
    sendDcMsg({DcMsg.Key: DcMsg.StopSsh});
  }

  /// Initiates a file upload session to the host.
  ///
  /// Parameters:
  /// - id: Unique identifier for this upload session
  /// - path: Target path on the host filesystem
  /// - totalSize: Total size of the file in bytes
  /// - hash: Optional SHA256 hash for integrity verification
  ///
  /// The host will prepare to receive chunks and validate the upload.
  void sendUploadStart({
    required String id,
    required String path,
    required int totalSize,
    String? hash,
  }) {
    final msg = {
      'type': DcMsg.UploadStart,
      'id': id,
      'path': path,
      'total_size': totalSize,
      'hash': hash,
      'timestamp': getTimestamp(),
    };
    sendToChannel(fsDC, jsonEncode(msg), "FS");
  }

  /// Sends a chunk of file data as part of an active upload session.
  ///
  /// Parameters:
  /// - id: Upload session identifier
  /// - data: Base64-encoded chunk of file data
  ///
  /// Chunks are assembled on the host in the correct order.
  void sendUploadChunk({required String id, required String data}) {
    final msg = {
      'type': DcMsg.UploadChunk,
      'id': id,
      'data': data,
      'timestamp': getTimestamp(),
    };
    sendToChannel(fsDC, jsonEncode(msg), "FS");
  }

  /// Completes an active file upload session.
  ///
  /// Parameters:
  /// - id: Upload session identifier
  ///
  /// The host will finalize the file, validate integrity if hash provided,
  /// and clean up the upload session resources.
  void sendUploadEnd({required String id}) {
    final msg = {
      'type': DcMsg.UploadEnd,
      'id': id,
      'timestamp': getTimestamp(),
    };
    sendToChannel(fsDC, jsonEncode(msg), "FS");
  }

  /// Sends a data channel command to the host with authentication.
  ///
  /// This is the main command dispatch method that:
  /// 1. Validates authentication (session token required)
  /// 2. Generates unique message ID for tracking
  /// 3. Routes to appropriate WebRTC channel based on command type
  /// 4. Includes timestamp for security and ordering
  ///
  /// Command routing:
  /// - File operations → fsChannel (frankn_fs)
  /// - Media operations → mediaChannel (frankn_media)
  /// - All others → dataChannel (frankn_cmd)
  @override
  void sendDcMsg(Map<String, dynamic> msg) {
    final token = AuthService().sessionToken;
    if (token == null) {
      log("Command Error: Not authenticated.");
      return;
    }

    final msgId = const Uuid().v4();

    final finalMsg = {
      'type': 'dc_msg',
      'id': msgId,
      'auth_token': token,
      'timestamp': getTimestamp(),
      ...msg,
    };

    final type = msg[DcMsg.Key];
    final jsonMsg = jsonEncode(finalMsg);
    // log("DEBUG: dc_msg type=$type id=$msgId");

    switch (type) {
      // File system operations routed to dedicated FS channel
      case DcMsg.Ls:
      case DcMsg.GetFile:
      case DcMsg.DeleteFile:
        sendToChannel(fsDC, jsonMsg, "FS");
        break;

      // Media control operations routed to dedicated media channel
      case DcMsg.SetVolume:
      case DcMsg.SetDeviceVolume:
      case DcMsg.TogglePlayPause:
      case DcMsg.PlayNextTrack:
      case DcMsg.PlayPreviousTrack:
      case DcMsg.StartMediaSync:
      case DcMsg.GetMediaStatus:
      case DcMsg.Seek:
        sendToChannel(mediaDC, jsonMsg, "MEDIA");
        break;

      // All other commands use the general command channel
      default:
        sendToChannel(genDC, jsonMsg, "CMD");
        break;
    }
  }
}
