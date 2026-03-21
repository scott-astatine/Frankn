part of 'rtc.dart';

mixin RtcMessageHandler on RtcClientBase {
  // Transfer ID -> IOSink for direct-to-disk writing
  final Map<String, IOSink> _activeSinks = {};
  final Map<String, String> _tempPaths = {};
  final Map<String, String> _expectedHashes = {};

  @override
  void handleHostMessage(dynamic rawData) {
    try {
      if (rawData is Uint8List) {
        // 1. Check for high-speed binary framing (Magic Byte 0x01 + 36-byte UUID)
        if (rawData.length >= 37 && rawData[0] == 0x01) {
          final idBytes = rawData.sublist(1, 37);
          final id = utf8.decode(
            idBytes.where((b) => b != 0).toList(),
            allowMalformed: true,
          );

          if (_activeSinks.containsKey(id)) {
            _handleBinaryChunk(id, rawData.sublist(37));
            return;
          }
        }

        // 2. If not a binary chunk, attempt JSON decode
        try {
          final text = utf8.decode(rawData);
          if (text.startsWith('{')) {
            _handleJsonMessage(jsonDecode(text));
            return;
          }
        } catch (_) {}
      } else if (rawData is String) {
        _handleJsonMessage(jsonDecode(rawData));
      }
    } catch (e) {
      log("Neural Link Error: Failed to parse incoming frame: $e");
    }
  }

  void _handleJsonMessage(Map<String, dynamic> data) async {
    final type = data['type'];

    switch (type) {
      case DcMsg.StreamStart:
        final String transferId = data['id'];
        final fileName = data['file_name'];
        final tempDir = await getTemporaryDirectory();
        final tempFile = File('${tempDir.path}/$transferId.part');

        if (await tempFile.exists()) await tempFile.delete();

        _activeSinks[transferId] = tempFile.openWrite();
        _tempPaths[transferId] = tempFile.path;
        activeFileNames[transferId] = fileName;

        if (data.containsKey('hash') && data['hash'] != null) {
          _expectedHashes[transferId] = data['hash'];
        }
        commandResponseController.add(data);
        break;

      case DcMsg.StreamEnd:
        final String transferId = data['id'];
        final sink = _activeSinks.remove(transferId);
        final tempPath = _tempPaths.remove(transferId);

        if (sink != null && tempPath != null) {
          await sink.flush();
          await sink.close();

          final fileName = activeFileNames.remove(transferId)!;
          final file = File(tempPath);

          String? expectedHash = _expectedHashes.remove(transferId);
          if (data.containsKey('hash') && data['hash'] != null) {
            expectedHash = data['hash'];
          }

          if (expectedHash != null) {
            // Verify hash without loading full file into RAM
            final stream = file.openRead();
            final actualHash = (await sha256.bind(stream).single).toString().toLowerCase();

            if (actualHash != expectedHash.toLowerCase()) {
              log("CRITICAL: Integrity failure for $fileName! Expected: $expectedHash, Got: $actualHash");
            } else {
              log("Integrity verified for $fileName.");
            }
          }

          commandResponseController.add({
            'type': DcMsg.StreamEnd,
            'file_name': fileName,
            'temp_path': tempPath,
            'id': transferId,
            'completed': true,
          });
        }
        break;

      case DcMsg.Challenge:
        _handleChallenge(data);
        break;

      case DcMsg.AuthSuccess:
        _handleAuthSuccess(data);
        break;

      case DcMsg.AuthFailed:
        _handleAuthFailed(data);
        break;

      case MediaDCMessage.MediaUpdate:
        _handleMediaUpdate(data);
        break;

      case MediaDCMessage.MediaPositionUpdate:
        commandResponseController.add(data);
        break;

      case DcMsg.Notification:
        notificationController.add(data);
        break;

      case DcMsg.HostResponse:
        _handleHostResponse(data);
        break;

      case DcMsg.Telemetry:
        commandResponseController.add(data);
        break;

      default:
        log("Unknown host message type: $type");
    }
  }

  void _handleBinaryChunk(String id, Uint8List chunk) {
    final sink = _activeSinks[id];
    if (sink != null) {
      sink.add(chunk);
      // Notifications handled by FileTransferMixin via current_total tracking
      commandResponseController.add({
        'type': DcMsg.FileChunk,
        'id': id,
        'chunk_size': chunk.length,
      });
    }
  }

  void _handleChallenge(Map<String, dynamic> data) async {
    final challenge = data['challenge'];
    final salt = data['salt'];
    if (currentPassword != null) {
      log("Computing Auth Response...");
      final argon2Hash = await AuthService().computeArgon2Hash(
        currentPassword!,
        salt,
      );
      final response = AuthService().computeResponse(argon2Hash, challenge);

      sendHostMessage({
        'type': 'auth_response',
        'response': response,
        'timestamp': getTimestamp(),
      });
    }
  }

  void _handleAuthSuccess(Map<String, dynamic> data) {
    final token = data['token'];
    AuthService().setToken(token);
    log("AUTH SUCCESS. Session Token acquired.");
    updateHostState(HostConnectionState.authenticated);
    sendDcMsg({DcMsg.Key: DcMsg.StartMediaSync});
  }

  void _handleAuthFailed(Map<String, dynamic> data) {
    log("AUTH FAILED: ${data['error']}");
    authFailed = true;
    updateHostState(HostConnectionState.disconnected);
  }

  void _handleHostResponse(Map<String, dynamic> data) {
    commandResponseController.add(data);

    if (data['data'] != null) {
      if (data['data']['response'] != DcMsg.Pong) {
        log("CMD RESPONSE: $data");
      }
      final d = data['data'];
      if (d['media_status'] != null || d['metadata'] != null) {
        _handleMediaUpdate(d);
      }
    }
  }

  void _handleMediaUpdate(Map<String, dynamic> data) {
    String? status = data['media_status'] ?? data['status'];
    String? metadata = data['metadata'];
    String? playerName = data['player_name'];
    double? volume = data['volume'] != null
        ? (data['volume'] as num).toDouble()
        : null;
    Duration? position;
    Duration? length;
    Uri? artUri;

        if (status != null) {

          mediaStatusController.add(status);

        }

        if (data['position'] != null) {

          position = Duration(microseconds: (data['position'] as num).toInt());

        }

        if (data['length'] != null) {

          length = Duration(microseconds: (data['length'] as num).toInt());

        }

    if (data['art_data'] != null) {
      final artStr = data['art_data'] as String;
      if (artStr.startsWith('http')) {
        artUri = Uri.parse(artStr);
      } else {
        compute(base64Decode, artStr).then((bytes) async {
          final tempDir = await getTemporaryDirectory();
          final file = File('${tempDir.path}/album_art.jpg');
          await file.writeAsBytes(bytes);
        });
      }
    }

    commandResponseController.add(data);

    String? title;
    String? artist;
    if (metadata != null && metadata.isNotEmpty) {
      if (metadata.contains(" - ")) {
        final parts = metadata.split(" - ");
        title = parts[0];
        artist = parts.length > 1 ? parts[1] : "Unknown Artist";
      } else {
        title = metadata;
        artist = "Unknown Artist";
      }
    }

    if (audioHandler is FranknAudioHandler) {
      (audioHandler as FranknAudioHandler).updateMediaState(
        status: status,
        title: title,
        artist: artist,
        playerName: playerName,
        position: position,
        duration: length,
        artUri: artUri,
        volume: volume,
      );
    }
  }
}
