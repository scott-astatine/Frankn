part of 'rtc.dart';

/// Mixin for RtcClient that handles incoming messages and routes them.
mixin RtcMessageHandler on RtcClientBase {
  // Transfer tracking
  final Map<String, int> _totalSizes = {};
  final Map<String, int> _receivedSizes = {};
  final Map<String, IOSink> _activeSinks = {};
  final Map<String, String> _tempPaths = {};
  final Map<String, String> _expectedHashes = {};

  final Map<String, String> _downloadTargetDirs = {};
  final Map<String, bool> _showNotificationMap = {};

  // Album art tracking
  String? _lastArtSig;
  String? _lastArtLocalPath;
  String? _currentArtTransferId;

  void _handleChallenge(HostMsgChallenge msg) async {
    log("Computing Auth Response...");
    final argon2Hash =
        await AuthService().computeArgon2Hash(currentPassword ?? "", msg.salt);
    final response = AuthService().computeResponse(argon2Hash, msg.challenge);
    sendHostMessage(ClientMsgAuthResponse(response: response).toJson());
  }

  void _handleAuthSuccess(HostMsgAuthSuccess msg) {
    isAuthFailed = false;
    AuthService().setToken(msg.token);
    updateHostState(HostConnectionState.authenticated);
    log("AUTH SUCCESS. Session Token acquired.");
  }

  void _handleAuthFailed(HostMsgAuthFailed msg) {
    isAuthFailed = true;
    updateHostState(HostConnectionState.failed);
    log("AUTH FAILED: ${msg.error}");
  }

  void _handleBinaryChunk(Uint8List chunk) async {
    final magic = chunk[0];
    if (magic != 0x01) return;

    // Fixed 50-byte header format:
    // [magic:1][id:36][offset:8][seq:4][flags:1][data:...]
    if (chunk.length < 50) return;

    final idBytes = chunk.sublist(1, 37);
    final id = ascii.decode(idBytes);

    // Parse absolute offset and sequence for progress tracking
    final offsetBytes = chunk.sublist(37, 45);
    final offset = ByteData.view(offsetBytes.buffer).getUint64(0);

    // final seqBytes = chunk.sublist(45, 49);
    // final seq = ByteData.view(seqBytes.buffer).getUint32(0);

    // final flags = chunk[49];
    final data = chunk.sublist(50);

    final sink = _activeSinks[id];
    if (sink != null) {
      sink.add(data);
      _receivedSizes[id] = offset + data.length;

      final currentTotal = _receivedSizes[id]!;
      final totalSize = _totalSizes[id] ?? 1;
      final progress = (currentTotal / totalSize).clamp(0.0, 1.0);

      // Throttled UI Update: Only emit progress every 1MB or on completion
      if (currentTotal % (1024 * 1024) < chunk.length ||
          currentTotal == totalSize) {
        transferProgressController.add(TransferProgressUpdate(
          id: id,
          progress: progress,
          bytesSent: currentTotal,
          totalBytes: totalSize,
        ));
      }

      // Update notification every 1MB or on completion
      if ((_showNotificationMap[id] ?? true) &&
          (currentTotal % (1024 * 1024) < chunk.length ||
              currentTotal == totalSize)) {
        final String sizeInfo =
            "${FileUtils.formatSize(currentTotal)} / ${FileUtils.formatSize(totalSize)}";
        NotificationService().showProgressNotification(
          id.hashCode.abs() % 100000,
          "Downloading '${activeFileNames[id] ?? 'File'}'...",
          "$sizeInfo (${(progress * 100).toStringAsFixed(1)}%)",
          progress * 100,
          transferId: id,
        );
      }
    }
  }

  void _handleDownloadEnd(HostMsgDownloadEnd msg) async {
    final transferId = msg.id;
    final sink = _activeSinks.remove(transferId);
    final tempPath = _tempPaths.remove(transferId);

    if (sink == null || tempPath == null) {
      log("WARN: DownloadEnd for unknown transfer ID $transferId — ignoring.");
      return;
    }

    await sink.flush();
    await sink.close();

    final fileName = activeFileNames.remove(transferId);
    if (fileName == null) {
      log("WARN: DownloadEnd for $transferId has no registered file name.");
      transferProgressController.add(TransferProgressFailed(
        id: transferId,
        error: 'No file name registered',
      ));
      return;
    }

    // Emit completion event
    transferProgressController.add(TransferProgressComplete(
      id: transferId,
      finalPath: tempPath,
      fileName: fileName,
    ));

    final file = File(tempPath);

    String? expectedHash = _expectedHashes.remove(transferId);
    if (msg.hash.isNotEmpty) {
      expectedHash = msg.hash;
    }

    if (expectedHash != null && expectedHash.isNotEmpty) {
      final bytes = await file.readAsBytes();
      final digest = sha256.convert(bytes).toString();

      if (digest != expectedHash) {
        log("FS ERROR: Hash mismatch for $fileName (Got: $digest, Expected: $expectedHash)");
        NotificationService().showDownloadComplete(
          transferId.hashCode.abs() % 100000,
          "Download Failed",
          "Integrity check failed for $fileName",
        );
        return;
      }
    }

    // Success! Relocate to final destination if a target directory was provided
    final targetDir = _downloadTargetDirs.remove(transferId);
    String finalPath = tempPath;

    if (targetDir != null && targetDir.isNotEmpty) {
      final destPath = "$targetDir/$fileName";
      try {
        await _moveFile(file, destPath);
        finalPath = destPath;
        log("FS: Download Complete. File saved to: $finalPath");
      } catch (e) {
        log("FS ERROR: Failed to relocate $fileName to $destPath: $e");
      }
    } else {
      log("FS: Temporary Download Complete. File kept at: $finalPath");
    }

    if (_showNotificationMap.remove(transferId) ?? true) {
      NotificationService().showDownloadComplete(
        transferId.hashCode.abs() % 100000,
        fileName,
        finalPath,
      );
    } else {
      // Internal system download (e.g. album art)
      if (transferId == _currentArtTransferId) {
        _lastArtLocalPath = "file://$finalPath";
        log("FS: Album Art cached: $finalPath");

        // Force a UI refresh by re-broadcasting the last media update with the local path
        // We don't need to force a sync! The Host's media loop polls every
        // second and broadcasts a MediaUpdate whenever the position changes.
      }
    }

    genDcMsgController.add(HostMsgDownloadEnd.fromJson({
      'type': 'download_end',
      'file_name': fileName,
      'temp_path': tempPath,
      'final_path': finalPath,
      'id': transferId,
      'completed': expectedHash != null,
    } as Map<String, dynamic>));
  }

  void _handleDownloadStart(HostMsgDownloadStart msg) {
    final String transferId = msg.id;
    final fileName = msg.fileName;
    final tempDir = globalTempDir;
    final tempFile = File('${tempDir.path}/$transferId.part');

    // Initialize tracking
    _totalSizes[transferId] = msg.totalSize;
    _receivedSizes[transferId] = msg.offset;

    // Show initial notification if requested
    if (_showNotificationMap[transferId] ?? true) {
      final String sizeInfo =
          "${FileUtils.formatSize(_receivedSizes[transferId] ?? 0)} / ${FileUtils.formatSize(_totalSizes[transferId] ?? 0)}";
      NotificationService().showProgressNotification(
        transferId.hashCode.abs() % 100000,
        "Downloading '$fileName'...",
        "$sizeInfo (0.0%)",
        0.0,
        transferId: transferId,
      );
    }

    // For resume-aware downloads, the host tells us what offset it started from.
    // We open the file in append mode if resuming, or create fresh.
    final hostOffset = msg.offset;
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

    if (msg.hash != null) {
      _expectedHashes[transferId] = msg.hash!;
    }
    genDcMsgController.add(msg);
  }

  void _handleHostResponse(HostMsgResponse msg) {
    genDcMsgController.add(msg);

    if (msg.data != null) {
      if (msg.data is Map && msg.data['response'] != 'Pong') {
        log("Host Response: ${msg.data}");
      }
    }
  }

  void _handleMediaUpdate(HostMsgMediaUpdate msg) async {
    final artStr = msg.artData;
    String? localArtPath;

    if (artStr != null && artStr.startsWith('frankn-fs://')) {
      if (artStr == _lastArtSig) {
        // Signature matches. It's the same song.
        if (_lastArtLocalPath != null) {
          // Download finished previously
          localArtPath = _lastArtLocalPath;
        }
      } else {
        // New signature detected (song changed).

        // 1. Delete the previous album art file from the cache
        if (_lastArtLocalPath != null) {
          try {
            final oldPath = _lastArtLocalPath!.replaceAll('file://', '');
            final oldFile = File(oldPath);
            if (oldFile.existsSync()) oldFile.deleteSync();
          } catch (e) {
            log("FS: Failed to delete old album art: $e");
          }
        }

        // 2. Update state
        _lastArtSig = artStr;
        _lastArtLocalPath = null;

        final remotePath = artStr.replaceAll('frankn-fs://', '');
        final uuid = const Uuid().v4();
        _currentArtTransferId = uuid;

        // 3. Setup the Transfer Engine mapping
        // We pass the actual cache directory so DownloadEnd relocates it properly
        _downloadTargetDirs[uuid] = globalTempDir.path;
        _expectedHashes[uuid] = ''; // Ignore hash verification
        _showNotificationMap[uuid] = false; // Silent download

        // 4. Initiate download
        sendToChannel(
          fsDC,
          jsonEncode(ClientMsgDownloadInit(
            id: uuid,
            path: remotePath,
            resumeOffset: 0,
          ).toJson()),
          "FS",
        );
      }
    }

    final media = msg;

    franknAudioHandlerInstance?.updateMediaState(
      isPlaying: media.playing,
      title: media.metadata.contains(" - ")
          ? media.metadata.split(" - ")[0]
          : media.metadata,
      artist: media.metadata.contains(" - ")
          ? media.metadata.split(" - ").sublist(1).join(" - ")
          : "Unknown Artist",
      playerName: media.playerName,
      position: Duration(microseconds: media.position.toInt()),
      duration: Duration(microseconds: media.length.toInt()),
      artUri: localArtPath != null
          ? Uri.parse(localArtPath)
          : (media.artData != null && media.artData!.startsWith('http'))
              ? Uri.parse(media.artData!)
              : null,
      volume: media.volume,
    );

    genDcMsgController.add(media);
  }

  void _handleJsonMessage(Map<String, dynamic> data) async {
    try {
      final strD = data.toString();
      if (!(strD.contains('telemetry') ||
          strD.contains('art_data') ||
          strD.contains('toggle_play_pause') ||
          strD.contains('Pong'))) {
        log("RAW_RX: ${jsonEncode(data)}");
      }

      final msg = HostMessage.fromJson(data);

      switch (msg) {
        case HostMsgDownloadStart():
          _handleDownloadStart(msg);
        case HostMsgDownloadEnd():
          _handleDownloadEnd(msg);
        case HostMsgChallenge():
          _handleChallenge(msg);
        case HostMsgAuthSuccess():
          _handleAuthSuccess(msg);
        case HostMsgAuthFailed():
          _handleAuthFailed(msg);
        case HostMsgMediaUpdate():
          _handleMediaUpdate(msg);
        case HostMsgNotification():
          notificationController.add(msg);
        case HostMsgResponse():
          _handleHostResponse(msg);
        case HostMsgLlmToken():
          genDcMsgController.add(msg);
        case HostMsgTelemetry():
          final cpu = msg.cpuLoad.toStringAsFixed(1);
          final usedMem = (msg.usedMem / 1024 / 1024 / 1024).toStringAsFixed(1);
          final cpuTemp = msg.cpuTemp.toStringAsFixed(1);

          final statusIcon = msg.cpuLoad > 80 ? '🔥' : '🟢';

          updateBackgroundService(
            text: "$statusIcon: $cpu% | 💾 : $usedMem GB | 🌡️ $cpuTemp°C",
          );
          genDcMsgController.add(msg);
        case HostMsgSyncSnapshot():
          log("FS_SYNC: Received snapshot for ${msg.rootPath}");
          syncSnapshotController.add(msg);
        case HostMsgTransferAck():
        case HostMsgTransferComplete():
          genDcMsgController.add(msg);
        case HostMsgTransferCancel():
          final id = msg.id;
          final sink = _activeSinks.remove(id);

          // Safe async cleanup
          if (sink != null) {
            try {
              await sink.flush();
              await sink.close();
            } catch (e) {
              log("FS: Error closing sink for $id during cancel: $e");
            }
          }

          final path = _tempPaths.remove(id);
          if (path != null) {
            try {
              final file = File(path);
              if (await file.exists()) {
                await file.delete();
                log("FS: Partial file for $id cleaned up.");
              }
            } catch (e) {
              log("FS: Failed to delete partial file $path: $e");
            }
          }

          // Emit a failed event so the UI stops loading
          transferProgressController.add(
            TransferProgressFailed(id: id, error: 'Transfer cancelled by host'),
          );
          genDcMsgController.add(msg);        case HostMsgUnknown():
          log("Unknown host message type: ${msg.type}");
      }
    } catch (e, stack) {
      log("PARSE ERROR: $e\n$stack");
    }
  }

  @override
  void handleHostMessage(dynamic rawData) {
    if (rawData is String) {
      try {
        final data = jsonDecode(rawData);
        if (data is Map) {
          _handleJsonMessage(Map<String, dynamic>.from(data));
        } else {
          log("RX Warn: Decoded JSON is not a Map: $data");
        }
      } catch (e) {
        log("RX Error (JSON): $e");
      }
    } else if (rawData is Uint8List) {
      // 1. Check for file transfer magic byte
      if (rawData.isNotEmpty && rawData[0] == 0x01) {
        _handleBinaryChunk(rawData);
        return;
      }

      // 2. Fallback: Attempt to decode as UTF-8 JSON
      try {
        final text = utf8.decode(rawData);
        if (text.startsWith('{')) {
          final data = jsonDecode(text);
          if (data is Map) {
            _handleJsonMessage(Map<String, dynamic>.from(data));
          }
        }
      } catch (_) {
        // If not UTF-8 or not JSON, ignore (legacy/malformed)
      }
    }
  }

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
}
