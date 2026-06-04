import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'dart:typed_data';
import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:frankn/services/rtc_thin_client.dart';
import 'package:frankn/services/isolate_protocol.dart';
import 'package:frankn/services/notification_service.dart';
import 'package:frankn/services/settings_service.dart';
import 'package:frankn/utils/utils.dart';
import 'package:frankn/utils/dc_msg_util.dart';

/// Metadata for a single file in a sync snapshot.
class SyncFileInfo {
  final String path;
  final int size;
  final int mtime;
  final String? hash;

  SyncFileInfo({
    required this.path,
    required this.size,
    required this.mtime,
    this.hash,
  });

  Map<String, dynamic> toJson() => {
    'path': path,
    'size': size,
    'mtime': mtime,
    'hash': hash,
  };

  factory SyncFileInfo.fromJson(Map<String, dynamic> json) => SyncFileInfo(
    path: json['path'],
    size: json['size'],
    mtime: json['mtime'],
    hash: json['hash'],
  );
}

enum SyncOpType { upload, download, deleteRemote, deleteLocal }

class SyncOperation {
  final SyncOpType type;
  final String path;

  SyncOperation(this.type, this.path);
}

/// Service for managing folder synchronization and delta calculation.
class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  final RtcThinClient _client = RtcThinClient();
  bool _isSyncCancelled = false;
  final Set<String> _cancelledSyncPairs = {};
  String? _activeTransferId;

  /// Cancels any in-progress sync operation.
  void stopSync([String? folderPath]) {
    if (folderPath != null) {
      _cancelledSyncPairs.add(folderPath);
      _client.log("SYNC: Termination signal received for folder: $folderPath");
    } else {
      _isSyncCancelled = true;
      _client.log("SYNC: Termination signal received globally.");
    }
    if (_activeTransferId != null) {
      _client.sendIntent(IsolateAction.cancelTransfer, {
        'id': _activeTransferId,
      });
    }
  }

  /// Scans a local directory recursively and generates a snapshot.
  Future<Map<String, SyncFileInfo>> generateLocalSnapshot(
    String rootPath,
  ) async {
    final Map<String, SyncFileInfo> snapshot = {};

    // Normalize path upfront
    final normalizedRoot = p.normalize(rootPath).replaceAll(RegExp(r'/+$'), '');
    final dir = Directory(normalizedRoot);

    if (!dir.existsSync()) {
      _client.log(
        "SYNC_SCAN ERROR: Local path does not exist: $normalizedRoot",
      );
      return snapshot;
    }

    _client.log("SYNC_SCAN: Scanning local path: $normalizedRoot...");

    try {
      // Manual stack-based recursion
      final List<Directory> stack = [dir];
      int fileCount = 0;
      int dirCount = 0;

      while (stack.isNotEmpty) {
        final currentDir = stack.removeLast();
        dirCount++;

        final List<FileSystemEntity> entities = currentDir.listSync(
          recursive: false,
          followLinks: true,
        );

        for (final entity in entities) {
          if (entity is Directory) {
            stack.add(entity);
          } else if (entity is File) {
            try {
              final stat = entity.statSync();
              final relativePath = p.relative(
                entity.path,
                from: normalizedRoot,
              );

              final hash = await _generateQuickHash(entity);

              snapshot[relativePath] = SyncFileInfo(
                path: relativePath,
                size: stat.size,
                mtime: stat.modified.millisecondsSinceEpoch ~/ 1000,
                hash: hash,
              );
              fileCount++;
            } catch (e) {
              _client.log(
                "SYNC_SCAN ERROR: Failed to read file ${entity.path}: $e",
              );
            }
          }
        }
      }
      _client.log(
        "SYNC_SCAN COMPLETE: Scanned $fileCount files across $dirCount directories.",
      );
    } catch (e) {
      _client.log("SYNC_SCAN FATAL EXCEPTION: $e");
    }

    return snapshot;
  }

  /// Calculates the delta between local and remote snapshots based on the sync mode.
  List<SyncOperation> calculateDelta({
    required Map<String, SyncFileInfo> local,
    required Map<String, SyncFileInfo> remote,
    required SyncMode mode,
    bool clientIsSource = true,
  }) {
    final List<SyncOperation> ops = [];

    if (mode == SyncMode.mirroring) {
      for (final path in local.keys) {
        if (!remote.containsKey(path)) {
          ops.add(SyncOperation(SyncOpType.upload, path));
        } else {
          final localFile = local[path]!;
          final remoteFile = remote[path]!;
          if (localFile.hash != remoteFile.hash || localFile.hash == null) {
            if (localFile.mtime > remoteFile.mtime) {
              ops.add(SyncOperation(SyncOpType.upload, path));
            } else if (remoteFile.mtime > localFile.mtime) {
              ops.add(SyncOperation(SyncOpType.download, path));
            }
          }
        }
      }
      for (final path in remote.keys) {
        if (!local.containsKey(path)) {
          ops.add(SyncOperation(SyncOpType.download, path));
        }
      }
    } else if (mode == SyncMode.singleSourceOfTruth) {
      if (clientIsSource) {
        for (final path in local.keys) {
          final localFile = local[path]!;
          final remoteFile = remote[path];
          if (remoteFile == null ||
              localFile.hash != remoteFile.hash ||
              localFile.hash == null) {
            ops.add(SyncOperation(SyncOpType.upload, path));
          }
        }
        for (final path in remote.keys) {
          if (!local.containsKey(path)) {
            ops.add(SyncOperation(SyncOpType.deleteRemote, path));
          }
        }
      } else {
        for (final path in remote.keys) {
          final remoteFile = remote[path]!;
          final localFile = local[path];
          if (localFile == null ||
              remoteFile.hash != localFile.hash ||
              remoteFile.hash == null) {
            ops.add(SyncOperation(SyncOpType.download, path));
          }
        }
        for (final path in local.keys) {
          if (!remote.containsKey(path)) {
            ops.add(SyncOperation(SyncOpType.deleteLocal, path));
          }
        }
      }
    }

    return ops;
  }

  /// Generates a quick SHA-256 hash (first 1024 bytes + file size).
  Future<String> _generateQuickHash(File file) async {
    try {
      final size = await file.length();

      final raf = await file.open(mode: FileMode.read);
      final bytes = await raf.read(1024);
      await raf.close();

      if (bytes.isEmpty) return "empty";

      final innerHasher = AccumulatorSink<Digest>();
      final sha = sha256.startChunkedConversion(innerHasher);

      sha.add(bytes);
      final sizeBytes = ByteData(8)..setUint64(0, size, Endian.big);
      sha.add(sizeBytes.buffer.asUint8List());

      sha.close();
      return innerHasher.events.single.toString();
    } catch (e) {
      _client.log("SYNC ERROR: Hashing failed for ${file.path}: $e");
      return "error";
    }
  }

  /// Requests a snapshot from the host.
  Future<void> requestRemoteSnapshot(String remotePath) async {
    _client.log("SYNC: Sending SyncRequest for $remotePath");
    _client.sendDcMsg(DcMsgSyncRequest(path: remotePath));
  }

  /// Orchestrates a full sync cycle: Scan -> Remote Snapshot -> Delta -> Execute.
  Future<void> performFullSync(SyncPair pair) async {
    final myId = identityHashCode(this);
    final clientId = identityHashCode(_client);
    _client.log(
      "SYNC_DEBUG[$myId]: Starting FULL_SYNC. RtcThinClient ID: $clientId",
    );

    try {
      // 1. Generate local snapshot
      final local = await generateLocalSnapshot(pair.localPath);

      // 2. Request remote snapshot
      final List<dynamic> accumulatedFiles = [];
      final completer = Completer<List<dynamic>>();
      StreamSubscription? sub;

      final normRemote = pair.remotePath.replaceAll(RegExp(r'/+$'), '');
      _client.log(
        "SYNC_DEBUG[$myId]: Registering snapshot listener for $normRemote",
      );

      sub = _client.syncSnapshotStream.listen((msg) {
        final String respPath = msg.rootPath;
        final normResp = respPath.replaceAll(RegExp(r'/+$'), '');
        _client.log(
          "SYNC_DEBUG[$myId]: Received snapshot chunk for $normResp (Final: ${msg.isFinal})",
        );

        if (normResp == normRemote) {
          accumulatedFiles.addAll(msg.files);
          if (msg.isFinal) {
            _client.log(
              "SYNC_DEBUG[$myId]: Completing snapshot future with ${accumulatedFiles.length} files.",
            );
            sub?.cancel();
            if (!completer.isCompleted) completer.complete(accumulatedFiles);
          }
        }
      });

      await requestRemoteSnapshot(pair.remotePath);
      _client.log(
        "SYNC_DEBUG[$myId]: Snapshot request sent. Waiting for response...",
      );

      final remoteList = await completer.future.timeout(
        const Duration(seconds: 45),
        onTimeout: () {
          _client.log("SYNC_DEBUG[$myId]: TIMEOUT WAITING FOR SNAPSHOT");
          sub?.cancel();
          throw TimeoutException("Remote snapshot request timed out.");
        },
      );

      // 3. Execute Batch
      await executeSyncBatch(pair, local, remoteList);

      _client.log("SYNC: FULL_SYNC SUCCESS for ${pair.localPath}");
    } catch (e) {
      _client.log("SYNC ERROR: performFullSync failed: $e");
      _client.sendEvent(IsolateAction.syncBatchProgress, {
        'completed': 0,
        'total': 0,
        'current_file': 'ERROR: $e',
      });
    }
  }

  /// Executes the synchronization batch operations sequentially.
  /// Needs to be run inside the Background Isolate.
  Future<void> executeSyncBatch(
    SyncPair pair,
    Map<String, SyncFileInfo> local,
    List<dynamic> remoteList,
  ) async {
    final Map<String, SyncFileInfo> remote = {};
    for (var f in remoteList) {
      final info = SyncFileInfo.fromJson(f);
      remote[info.path] = info;
    }

    final deltas = calculateDelta(
      local: local,
      remote: remote,
      mode: pair.mode,
      clientIsSource: pair.clientIsSource,
    );

    if (deltas.isEmpty) {
      _client.log("SYNC: ==================================================");
      _client.log("SYNC: Sync status for: ${pair.localPath}");
      _client.log("SYNC: Status: Working tree clean (already in sync).");
      _client.log("SYNC: ==================================================");
      await _updateLastSynced(pair);
      _client.sendEvent(IsolateAction.syncBatchProgress, {
        'completed': 0,
        'total': 0,
        'current_file': 'COMPLETE_NO_CHANGES',
      });
      return;
    }

    final totalItems = deltas.length;
    int completedItems = 0;

    // Calculate total bytes and compile Git-status style sync plan
    int totalBytes = 0;
    int uploadCount = 0;
    int downloadCount = 0;
    int delRemoteCount = 0;
    int delLocalCount = 0;
    final List<String> planLines = [];

    for (var op in deltas) {
      String statusStr = "";
      if (op.type == SyncOpType.upload) {
        uploadCount++;
        totalBytes += local[op.path]?.size ?? 0;
        final isNew = !remote.containsKey(op.path);
        statusStr = isNew ? "new file (upload)" : "modified (upload)";
      } else if (op.type == SyncOpType.download) {
        downloadCount++;
        totalBytes += remote[op.path]?.size ?? 0;
        final isNew = !local.containsKey(op.path);
        statusStr = isNew ? "new file (download)" : "modified (download)";
      } else if (op.type == SyncOpType.deleteRemote) {
        delRemoteCount++;
        statusStr = "deleted (remote)";
      } else if (op.type == SyncOpType.deleteLocal) {
        delLocalCount++;
        statusStr = "deleted (local)";
      }

      final paddedStatus = statusStr.padRight(22);
      planLines.add("SYNC: \t$paddedStatus: ${op.path}");
    }

    _client.log("SYNC: ==================================================");
    _client.log("SYNC: Sync plan for folder: ${pair.localPath}");
    _client.log("SYNC: Changes to be synchronized:");
    _client.log("SYNC:   (use in-app controls to cancel or monitor)");
    _client.log("SYNC: ");
    for (var line in planLines) {
      _client.log(line);
    }
    _client.log("SYNC: ");

    final List<String> summaryParts = [];
    if (uploadCount > 0) summaryParts.add("$uploadCount uploads");
    if (downloadCount > 0) summaryParts.add("$downloadCount downloads");
    if (delRemoteCount > 0) summaryParts.add("$delRemoteCount remote deletions");
    if (delLocalCount > 0) summaryParts.add("$delLocalCount local deletions");

    final summaryStr = summaryParts.join(", ");
    _client.log(
      "SYNC: Summary: ${deltas.length} changes ($summaryStr). "
      "Total transfer size: ${FileUtils.formatSize(totalBytes)}",
    );
    _client.log("SYNC: ==================================================");

    int completedBytes = 0;
    int activeFileBytesTransferred = 0;
    final folderName = pair.localPath.split('/').last;
    final syncNotificationId = pair.localPath.hashCode.abs() % 10000;

    _isSyncCancelled = false;
    _cancelledSyncPairs.remove(pair.localPath);

    try {
      for (final op in deltas) {
        if (_isSyncCancelled || _cancelledSyncPairs.contains(pair.localPath)) {
          _client.log(
            "SYNC: Operation aborted by user for folder: ${pair.localPath}.",
          );
          break;
        }
        completedItems++;
        activeFileBytesTransferred = 0;

        _client.sendEvent(IsolateAction.syncBatchProgress, {
          'completed': completedItems,
          'total': totalItems,
          'current_file': op.path,
        });

        final completer = Completer<bool>();
        final transferId = FileUtils.generateStableTransferId(
          op.path,
          op.type == SyncOpType.upload
              ? (local[op.path]?.size ?? 0)
              : (remote[op.path]?.size ?? 0),
        );
        _activeTransferId = transferId;

        // Update notification at the start of each file
        NotificationService().showSyncNotification(
          id: syncNotificationId,
          folderName: folderName,
          folderPath: pair.localPath,
          completedItems: completedItems - 1,
          totalItems: totalItems,
          totalSize: FileUtils.formatSize(totalBytes),
          currentFile: op.path.split('/').last,
          progress: totalBytes > 0
              ? (completedBytes / totalBytes)
              : ((completedItems - 1) / totalItems),
        );

        // Listen for the specific transfer completion from the local intent stream or transferProgressStream.
        // Since this is running in the background isolate, it can listen to `transferProgressStream`.
        StreamSubscription? statusSub;
        statusSub = _client.transferProgressStream.listen((event) {
          if (event.id == transferId) {
            if (event is TransferProgressUpdate) {
              activeFileBytesTransferred = event.bytesSent;
              // Update notification with partial progress
              NotificationService().showSyncNotification(
                id: syncNotificationId,
                folderName: folderName,
                folderPath: pair.localPath,
                completedItems: completedItems - 1,
                totalItems: totalItems,
                totalSize: FileUtils.formatSize(totalBytes),
                currentFile: op.path.split('/').last,
                progress: totalBytes > 0
                    ? ((completedBytes + activeFileBytesTransferred) /
                          totalBytes)
                    : ((completedItems - 1 + event.progress) / totalItems),
              );
            } else if (event is TransferProgressComplete) {
              statusSub?.cancel();
              if (op.type == SyncOpType.upload) {
                completedBytes += local[op.path]?.size ?? 0;
              } else if (op.type == SyncOpType.download) {
                completedBytes += remote[op.path]?.size ?? 0;
              }
              completer.complete(true);
            } else if (event is TransferProgressFailed) {
              statusSub?.cancel();
              completer.complete(false);
            }
          }
        });

        try {
          switch (op.type) {
            case SyncOpType.upload:
              _client.log(
                "SYNC: [$completedItems/$totalItems] Uploading ${op.path}...",
              );
              _client.sendIntent(IsolateAction.uploadInit, {
                'id': transferId,
                'local_path': "${pair.localPath}/${op.path}",
                'remote_path': "${pair.remotePath}/${op.path}",
                'file_name': op.path.split('/').last,
                'hash': local[op.path]?.hash ?? '', // safely handle null hash
                'show_notification': false,
              });
              await completer.future.timeout(const Duration(minutes: 5));
              break;

            case SyncOpType.download:
              _client.log(
                "SYNC: [$completedItems/$totalItems] Downloading ${op.path}...",
              );
              // Ensure local directory exists before download
              final targetFile = File("${pair.localPath}/${op.path}");
              if (!targetFile.parent.existsSync()) {
                targetFile.parent.createSync(recursive: true);
              }

              _client.sendIntent(IsolateAction.downloadInit, {
                'id': transferId,
                'path': "${pair.remotePath}/${op.path}",
                'target_dir': targetFile.parent.path,
                'show_notification': false,
              });
              await completer.future.timeout(const Duration(minutes: 5));
              break;

            case SyncOpType.deleteRemote:
              _client.log("SYNC: Deleting remote ${op.path}...");
              _client.sendDcMsg(
                DcMsgDeleteFile(path: "${pair.remotePath}/${op.path}"),
              );
              await Future.delayed(const Duration(milliseconds: 100));
              statusSub.cancel(); // Cancel unused sub
              break;

            case SyncOpType.deleteLocal:
              _client.log("SYNC: Deleting local ${op.path}...");
              final file = File("${pair.localPath}/${op.path}");
              if (await file.exists()) await file.delete();
              await Future.delayed(const Duration(milliseconds: 100));
              statusSub.cancel(); // Cancel unused sub
              break;
          }
        } catch (e) {
          _client.log("SYNC ERROR: Failed op for ${op.path}: $e");
          statusSub.cancel();
        }
      }
    } finally {
      _activeTransferId = null;
    }

    _client.log("SYNC: Batch processing finished.");

    await _updateLastSynced(pair);

    // Final notification update
    NotificationService().showSyncNotification(
      id: syncNotificationId,
      folderName: folderName,
      folderPath: pair.localPath,
      completedItems: totalItems,
      totalItems: totalItems,
      totalSize: FileUtils.formatSize(totalBytes),
      currentFile: 'COMPLETE',
      progress: 1.0,
      isComplete: true,
    );

    _client.sendEvent(IsolateAction.syncBatchProgress, {
      'completed': totalItems,
      'total': totalItems,
      'current_file': 'COMPLETE',
    });
  }

  /// Verifies the sync status of a pair without executing transfers.
  Future<void> checkSyncStatus(SyncPair pair) async {
    try {
      // 1. Local scan
      final local = await generateLocalSnapshot(pair.localPath);

      // 2. Request remote snapshot
      final List<dynamic> accumulatedFiles = [];
      final completer = Completer<List<dynamic>>();
      StreamSubscription? sub;

      final normRemote = pair.remotePath.replaceAll(RegExp(r'/+$'), '');
      sub = _client.syncSnapshotStream.listen((msg) {
        final String respPath = msg.rootPath;
        final normResp = respPath.replaceAll(RegExp(r'/+$'), '');
        if (normResp == normRemote) {
          accumulatedFiles.addAll(msg.files);
          if (msg.isFinal) {
            sub?.cancel();
            if (!completer.isCompleted) completer.complete(accumulatedFiles);
          }
        }
      });

      await requestRemoteSnapshot(pair.remotePath);
      final remoteList = await completer.future.timeout(
        const Duration(seconds: 30),
      );

      final Map<String, SyncFileInfo> remote = {};
      for (var f in remoteList) {
        remote[f['path']] = SyncFileInfo.fromJson(f);
      }

      // 3. Calculate delta
      final deltas = calculateDelta(
        local: local,
        remote: remote,
        mode: pair.mode,
        clientIsSource: pair.clientIsSource,
      );

      // 4. Report status
      _client.sendEvent(IsolateAction.syncStatusUpdate, {
        'local_path': pair.localPath,
        'remote_path': pair.remotePath,
        'pending_changes': deltas.length,
        'status': deltas.isEmpty ? 'IN_SYNC' : 'NEEDS_SYNC',
      });
    } catch (e) {
      _client.log("SYNC_VERIFIER ERROR: $e");
    }
  }

  /// Updates the lastSynced timestamp of a sync pair in SettingsService.
  Future<void> _updateLastSynced(SyncPair pair) async {
    try {
      final settings = SettingsService();
      await settings.reload();
      final pairs = settings.syncPairs;
      final index = pairs.indexWhere(
        (p) => p.localPath == pair.localPath && p.remotePath == pair.remotePath,
      );
      if (index != -1) {
        pairs[index] = SyncPair(
          localPath: pair.localPath,
          remotePath: pair.remotePath,
          mode: pair.mode,
          clientIsSource: pair.clientIsSource,
          intervalMinutes: pair.intervalMinutes,
          lastSynced: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        );
        await settings.setSyncPairs(pairs);
        _client.log(
          "SYNC: Updated lastSynced to ${pairs[index].lastSynced} for ${pair.localPath}",
        );
      }
    } catch (e) {
      _client.log("SYNC ERROR: Failed to update lastSynced: $e");
    }
  }
}
