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
    isAuthFailed = false; // Clear previous failure state
    currentPassword = password;
    log("Requesting Authentication...");
    sendHostMessage(const ClientMsgAuthRequest().toJson());
  }

  /// Starts an SSH terminal session on the connected host.
  ///
  /// The host will allocate a PTY and begin forwarding terminal data
  /// through the SSH data channel for remote shell access.
  void startSsh() {
    sendDcMsg(const DcMsgStartSsh());
  }

  /// Terminates the active SSH terminal session on the host.
  ///
  /// Cleans up the PTY allocation and stops terminal data forwarding.
  void stopSsh() {
    sendDcMsg(const DcMsgStopSsh());
  }

  @override
  void sendInputMsg(Map<String, dynamic> msg) {
    final client = this as RtcClient;
    final token = AuthService().sessionToken;
    if (token == null) return;

    final jsonMsg = jsonEncode(msg);
    sendToChannel(client.currentHost?.inputDC, jsonMsg, "INPUT");
  }

  void sendUploadChunkRaw({
    required String id,
    required Uint8List data,
    required int offset,
    required int seq,
    required int flags,
  }) {
    final client = this as RtcClient;
    final fsDC = client.currentHost?.fsDC;
    if (fsDC?.state != RTCDataChannelState.RTCDataChannelOpen) return;

    final idBytes = utf8.encode(id);
    final header = Uint8List(36);
    header.setRange(0, idBytes.length.clamp(0, 36), idBytes);

    // Build full frame
    const headerSize = 1 + 36 + 8 + 4 + 1;
    final frame = Uint8List(headerSize + data.length);

    // Magic
    frame[0] = 0x01;
    // ID
    frame.setRange(1, 37, header);
    // Offset (8 bytes, big-endian)
    final offsetBytes = ByteData(8)..setUint64(0, offset);
    frame.setRange(37, 45, offsetBytes.buffer.asUint8List());
    // Seq (4 bytes, big-endian)
    final seqBytes = ByteData(4)..setUint32(0, seq);
    frame.setRange(45, 49, seqBytes.buffer.asUint8List());
    // Flags
    frame[49] = flags;
    // Data
    frame.setRange(50, 50 + data.length, data);

    fsDC?.send(RTCDataChannelMessage.fromBinary(frame));
  }

  /// Initialize a resume-aware upload transfer.
  void sendTransferInit({
    required String id,
    required String path,
    required int totalSize,
    String? hash,
    int resumeOffset = 0,
  }) {
    final client = this as RtcClient;
    sendToChannel(
      client.currentHost?.fsDC,
      jsonEncode(
        ClientMsgTransferInit(
          id: id,
          path: path,
          totalSize: totalSize,
          hash: hash,
          resumeOffset: resumeOffset,
        ).toJson(),
      ),
      "FS",
    );
  }

  /// Cancel a transfer.
  void sendTransferCancel(String id) {
    final client = this as RtcClient;
    sendToChannel(
      client.currentHost?.fsDC,
      jsonEncode(ClientMsgTransferCancel(id: id).toJson()),
      "FS",
    );
  }

  /// Initialize a resume-aware download.
  void sendDownloadInit({
    required String id,
    required String path,
    int resumeOffset = 0,
  }) {
    final client = this as RtcClient;
    sendToChannel(
      client.currentHost?.fsDC,
      jsonEncode(
        ClientMsgDownloadInit(
          id: id,
          path: path,
          resumeOffset: resumeOffset,
        ).toJson(),
      ),
      "FS",
    );
  }

  @override
  void sendDcMsg(DcMsg command) {
    final client = this as RtcClient;
    final token = AuthService().sessionToken;
    if (token == null) {
      log("Command Error: Not authenticated.");
      return;
    }

    final msgId = const Uuid().v4();

    final clientMsg = ClientMsgXDcMsg(
      id: msgId,
      command: command,
      authToken: token,
    );

    final jsonMsg = jsonEncode(clientMsg.toJson());

    final host = client.currentHost;
    switch (command) {
      // File system operations routed to dedicated FS channel
      case DcMsgLs() || DcMsgDeleteFile() || DcMsgMkdir() || DcMsgSyncRequest():
        sendToChannel(host?.fsDC, jsonMsg, "FS");
        break;

      // Media control operations routed to dedicated media channel
      case DcMsgSetVolume() ||
          DcMsgSetDeviceVolume() ||
          DcMsgTogglePlayPause() ||
          DcMsgPlayNextTrack() ||
          DcMsgPlayPreviousTrack() ||
          DcMsgGetMediaStatus() ||
          DcMsgSeek() ||
          DcMsgSetActivePlayer() ||
          DcMsgListPlayers() ||
          DcMsgGetAudioDevices() ||
          DcMsgSetDefaultAudioDevice():
        sendToChannel(host?.mediaDC, jsonMsg, "MEDIA");
        break;

      case DcMsgLlmStart() ||
          DcMsgLlmChat() ||
          DcMsgLlmStop() ||
          DcMsgListModels() ||
          DcMsgLlmLoadChat() ||
          DcMsgLlmDeleteChat() ||
          DcMsgLlmListChats():
        sendToChannel(host?.aiDC, jsonMsg, "AI");
        break;

      // All other commands use the general command channel
      default:
        sendToChannel(host?.genDC, jsonMsg, "CMD");
        break;
    }
  }
}
