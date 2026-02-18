part of 'rtc.dart';

mixin RtcMessageHandler on RtcClientBase {
  final Map<String, BytesBuilder> _transferBuilders = {};
  final Map<String, String> _expectedHashes = {};

  @override
  void handleHostMessage(dynamic rawData) {
    try {
      String? jsonText;
      bool isProbablyBinaryChunk = false;

      // Handle bytes
      if (rawData is Uint8List) {
        try {
          final decoded = utf8.decode(rawData);
          final trimmed = decoded.trim();
          if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
            jsonText = decoded;
          } else {
            isProbablyBinaryChunk = true;
          }
        } catch (_) {
          isProbablyBinaryChunk = true;
        }
      } else if (rawData is String) {
        jsonText = rawData;
      }

      /// Handles data channel messages
      if (jsonText != null) {
        final data = jsonDecode(jsonText) as Map<String, dynamic>;
        final type = data['type'];

        switch (type) {
          case DcMsg.FileTransferStart:
            final String transferId = data['id'];
            _transferBuilders[transferId] = BytesBuilder(copy: false);
            activeFileNames[transferId] = data['file_name'];
            if (data.containsKey('hash') && data['hash'] != null) {
              _expectedHashes[transferId] = data['hash'];
            }
            commandResponseController.add(data);
            break;

          case DcMsg.FileTransferEnd:
            final String transferId = data['id'];
            final builder = _transferBuilders.remove(transferId);
            if (builder != null) {
              final bytes = builder.takeBytes();
              final fileName = activeFileNames.remove(transferId)!;
              
              // Check hash from Start OR End message
              String? expectedHash = _expectedHashes.remove(transferId);
              if (data.containsKey('hash') && data['hash'] != null) {
                expectedHash = data['hash'];
              }

              if (expectedHash != null) {
                final actualHash = HEX
                    .encode(sha256.convert(bytes).bytes)
                    .toLowerCase();
                if (actualHash != expectedHash.toLowerCase()) {
                  log("CRITICAL: Integrity failure for $fileName!");
                } else {
                  log("Integrity verified for $fileName.");
                }
              }

              commandResponseController.add({
                'type': DcMsg.FileTransferEnd,
                'file_name': fileName,
                'bytes': bytes,
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

          default:
            log("Unknown host message type: $type");
        }
      } else if (isProbablyBinaryChunk && rawData is Uint8List) {
        _handleBinaryMessage(rawData);
      }
    } catch (e) {
      log("Error parsing host message: $e");
    }
  }

  void _handleBinaryMessage(Uint8List frame) {
    if (frame.length < 36) return;

    final idBytes = frame.sublist(0, 36);
    final transferId = utf8.decode(idBytes.where((b) => b != 0).toList());
    final rawData = frame.sublist(36);

    final builder = _transferBuilders[transferId];
    if (builder != null) {
      // ASSEMBLY: Add data to the builder
      builder.add(rawData);

      // Progress notification
      if (builder.length % (1024 * 512) == 0 || builder.length == rawData.length) {
        commandResponseController.add({
          'type': DcMsg.FileChunk,
          'id': transferId,
          'chunk_size': rawData.length,
          'current_total': builder.length,
        });
      }
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
    log("CMD RESPONSE: ${data['status']} for ID: ${data['id']}");
    commandResponseController.add(data);

    if (data['data'] != null) {
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
