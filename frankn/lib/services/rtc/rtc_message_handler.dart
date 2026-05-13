part of 'rtc.dart';

mixin RtcMessageHandler on RtcClientBase {
  // Transfer ID -> IOSink for direct-to-disk writing
  final Map<String, IOSink> _activeSinks = {};
  final Map<String, String> _tempPaths = {};
  final Map<String, String> _expectedHashes = {};
  final Map<String, String> _downloadTargetDirs = {};
  final Map<String, int> _totalSizes = {};
  final Map<String, int> _receivedSizes = {};
  final Map<String, bool> _showNotificationMap = {};

  Future<void> _moveFile(File source, String destPath) async {
    try {
      await source.rename(destPath);
    } catch (e) {
      if (e is FileSystemException && e.osError?.errorCode == 18) {
        // Cross-device link (e.g., temp to SD card). Copy and delete.
        await source.copy(destPath);
        await source.delete();
      } else {
        rethrow;
      }
    }
  }

  @override
  void handleHostMessage(dynamic rawData) {
    try {
      if (rawData is Uint8List) {
        // Check for high-speed binary framing (Magic Byte 0x01)
        if (rawData.length >= 50 && rawData[0] == 0x01) {
          // New extended format: [magic][36-byte ID][8-byte offset][4-byte seq][1-byte flags][data]
          final idBytes = rawData.sublist(1, 37);
          final id = utf8.decode(
            idBytes.where((b) => b != 0).toList(),
            allowMalformed: true,
          );

          // Parse offset and seq for resume-aware downloads
          final offsetBytes = rawData.sublist(37, 45);
          final offset = ByteData.view(offsetBytes.buffer).getUint64(0);

          final seqBytes = rawData.sublist(45, 49);
          final seq = ByteData.view(seqBytes.buffer).getUint32(0);

          final flags = rawData[49];

          if (_activeSinks.containsKey(id)) {
            _handleBinaryChunk(id, rawData.sublist(50), offset, seq, flags);
            return;
          }
          // If sink not ready yet, chunk will be dropped (shouldn't happen with ordered DCs)
          return;
        } else if (rawData.length >= 37 && rawData[0] == 0x01) {
          // Legacy format: [magic][36-byte ID][data]
          final idBytes = rawData.sublist(1, 37);
          final id = utf8.decode(
            idBytes.where((b) => b != 0).toList(),
            allowMalformed: true,
          );

          if (_activeSinks.containsKey(id)) {
            _handleBinaryChunkLegacy(id, rawData.sublist(37));
            return;
          }
          return;
        }

        // If not a binary chunk, attempt JSON decode
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
      case 'download_start':
        final String transferId = data['id'];
        final fileName = data['file_name'];
        final tempDir = globalTempDir;
        final tempFile = File('${tempDir.path}/$transferId.part');

        // Initialize tracking
        _totalSizes[transferId] = data['total_size'] ?? 0;
        _receivedSizes[transferId] = data['offset'] as int? ?? 0;

        // Show initial notification if requested
        if (_showNotificationMap[transferId] ?? true) {
          NotificationService().showProgressNotification(
            transferId.hashCode.abs() % 100000,
            "Downloading '$fileName'...",
            "0.0%",
            0.0,
          );
        }

        // For resume-aware downloads, the host tells us what offset it started from.
        // We open the file in append mode if resuming, or create fresh.
        final hostOffset = data['offset'] as int? ?? 0;
        if (hostOffset > 0 && tempFile.existsSync()) {
          // Resuming — append to existing partial file
          _activeSinks[transferId] = tempFile.openWrite(mode: FileMode.append);
        } else {
          // Fresh start — create/truncate
          if (tempFile.existsSync()) tempFile.deleteSync();
          _activeSinks[transferId] = tempFile.openWrite();
        }

        _tempPaths[transferId] = tempFile.path;
        activeFileNames[transferId] = fileName;

        if (data.containsKey('hash') && data['hash'] != null) {
          _expectedHashes[transferId] = data['hash'];
        }
        commandResponseController.add(data);
        break;

      case DcMsg.StreamEnd:
      case 'download_end':
        final String transferId = data['id'];
        final sink = _activeSinks.remove(transferId);
        final tempPath = _tempPaths.remove(transferId);
        final bool showNotif = _showNotificationMap.remove(transferId) ?? true;
        _totalSizes.remove(transferId);
        _receivedSizes.remove(transferId);

        if (sink == null || tempPath == null) {
          log(
            "WARN: StreamEnd for unknown transfer ID $transferId — ignoring.",
          );
          break;
        }

        await sink.flush();
        await sink.close();

        final fileName = activeFileNames.remove(transferId);
        if (fileName == null) {
          log("WARN: StreamEnd for $transferId has no registered file name.");
          break;
        }
        final file = File(tempPath);

        String? expectedHash = _expectedHashes.remove(transferId);
        if (data.containsKey('hash') && data['hash'] != null) {
          expectedHash = data['hash'];
        }

        if (expectedHash != null) {
          // Verify hash without loading full file into RAM
          final stream = file.openRead();
          final actualHash = (await sha256.bind(stream).single)
              .toString()
              .toLowerCase();

          if (actualHash != expectedHash.toLowerCase()) {
            log(
              "CRITICAL: Integrity failure for $fileName! Expected: $expectedHash, Got: $actualHash",
            );
          } else {
            log("Integrity verified for $fileName.");
          }
        } else {
          log(
            "WARN: StreamEnd for $fileName has no hash — skipping integrity check.",
          );
        }

        // Relocate the file to its final destination
        String? finalPath;
        try {
          final targetDir = _downloadTargetDirs.remove(transferId);
          if (targetDir != null && targetDir.isNotEmpty) {
            finalPath = "$targetDir/$fileName";
            await _moveFile(file, finalPath);
            log("FS: File relocated to $finalPath");
          } else {
            // Default to app documents if no target dir specified
            final appDocDir = await getApplicationDocumentsDirectory();
            finalPath = "${appDocDir.path}/$fileName";
            await _moveFile(file, finalPath);
            log("FS: File relocated to default path: $finalPath");
          }
        } catch (e) {
          log("FS ERROR: Failed to relocate $fileName: $e");
        }

        if (showNotif && finalPath != null) {
          final notifId = transferId.hashCode.abs() % 100000;
          await NotificationService().showDownloadComplete(
            notifId,
            fileName,
            finalPath,
          );
        }

        commandResponseController.add({
          'type': DcMsg.StreamEnd,
          'file_name': fileName,
          'temp_path': tempPath,
          'final_path': finalPath,
          'id': transferId,
          'completed': expectedHash != null,
        });
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

      case DcMsg.LlmToken:
        commandResponseController.add(data);
        break;

      case DcMsg.Telemetry:
        final cpu = data['cpu_load']?.toStringAsFixed(1);
        final usedMem = ((data['used_mem'] ?? 0) / 1024 / 1024 / 1024)
            .toStringAsFixed(1);
        final cpuTemp = data['cpu_temp']?.toStringAsFixed(1) ?? '0.0';

        // Use standard Unicode emojis for the notification body
        final cpuVal = data['cpu_load'] as double? ?? 0.0;
        final statusIcon = cpuVal > 80 ? '🔥' : '🟢';

        updateBackgroundService(
          text: "$statusIcon: $cpu% | 💾 : $usedMem GB | 🌡️ $cpuTemp°C",
        );
        commandResponseController.add(data);
        break;

      default:
        log("Unknown host message type: $type");
    }
  }

  void _handleBinaryChunk(
    String id,
    Uint8List chunk,
    int offset,
    int seq,
    int flags,
  ) {
    final sink = _activeSinks[id];
    if (sink != null) {
      sink.add(chunk);

      // Track progress for resume-aware transfers
      final currentTotal = (offset + chunk.length);
      _receivedSizes[id] = currentTotal;

      final totalSize = _totalSizes[id] ?? 1;
      final progress = (currentTotal / totalSize).clamp(0.0, 1.0);

      // Update notification every 1MB or on completion
      if ((_showNotificationMap[id] ?? true) &&
          (currentTotal % (1024 * 1024) < chunk.length ||
              currentTotal == totalSize)) {
        final fileName = activeFileNames[id] ?? "File";
        NotificationService().showProgressNotification(
          id.hashCode.abs() % 100000,
          "Downloading '$fileName'...",
          "${(progress * 100).toStringAsFixed(1)}%",
          progress * 100,
        );
      }

      commandResponseController.add({
        'type': DcMsg.FileChunk,
        'id': id,
        'chunk_size': chunk.length,
        'offset': offset,
        'seq': seq,
        'total_received': currentTotal,
        'is_final': (flags & 0x02) != 0,
      });
    }
  }

  void _handleBinaryChunkLegacy(String id, Uint8List chunk) {
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

      sendHostMessage({'type': 'auth_response', 'response': response});
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
        log("Host Response: $data");
      }
    }
  }

  void _handleMediaUpdate(Map<String, dynamic> data) async {
    MediaUpdate media = MediaUpdate.fromJson(data);
    log("Loggggginnnnnnnnnnnnnnnnnnnnnnnnnnnnnn MediaUpdate: IsPlaying: $data");

    final artStr = media.artData;
    if (artStr != null && !artStr.startsWith('http')) {
      try {
        final tempDir = globalTempDir;
        final file = File('${tempDir.path}/album_art.jpg');
        if (await file.exists()) await file.delete();
        await file.writeAsBytes(base64Decode(artStr));
        // Replace large base64 string with local file path to avoid IPC crash
        data['art_data'] = 'file://${file.path}';
      } catch (e) {
        log("Failed to parse album art in background isolate: $e");
        data.remove('art_data');
      }
    }

    commandResponseController.add(data);
  }
}
