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
import 'package:permission_handler/permission_handler.dart';

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
  String? _activeTransferId;

  /// Cancels any in-progress sync operation.
  void stopSync() {
    _isSyncCancelled = true;
    if (_activeTransferId != null) {
      _client.sendIntent(IsolateAction.cancelTransfer, {'id': _activeTransferId});
    }
    _client.log("SYNC: Termination signal received.");
  }

  /// Scans a local directory recursively and generates a snapshot.
  Future<Map<String, SyncFileInfo>> generateLocalSnapshot(String rootPath) async {
    print("==================================================");
    print("SYNC_SCAN: Starting local scan of $rootPath");
    
    // Check permission status directly using raw print for visibility
    final manageStatus = await Permission.manageExternalStorage.status;
    print("SYNC_SCAN: All-Files Permission Status: $manageStatus");

    final Map<String, SyncFileInfo> snapshot = {};

    // Normalize path upfront
    final normalizedRoot = p.normalize(rootPath).replaceAll(RegExp(r'/+$'), '');
    final dir = Directory(normalizedRoot);

    if (!dir.existsSync()) {
      print("SYNC_SCAN ERROR: Local path does not exist according to OS: $normalizedRoot");
      return snapshot;
    }

    try {
      // Manual stack-based recursion (Proven to work in your debugDirectory func)
      final List<Directory> stack = [dir];
      int fileCount = 0;
      int dirCount = 0;

      while (stack.isNotEmpty) {
        final currentDir = stack.removeLast();
        print("SYNC_SCAN: Entering: ${currentDir.path}");
        dirCount++;

        final List<FileSystemEntity> entities = currentDir.listSync(recursive: false, followLinks: true);
        print("SYNC_SCAN: Found ${entities.length} items in ${currentDir.path}");
        
        for (final entity in entities) {
          if (entity is Directory) {
            stack.add(entity);
          } else if (entity is File) {
            try {
              final stat = entity.statSync();
              final relativePath = p.relative(entity.path, from: normalizedRoot);
              
              final hash = await _generateQuickHash(entity);

              snapshot[relativePath] = SyncFileInfo(
                path: relativePath,
                size: stat.size,
                mtime: stat.modified.millisecondsSinceEpoch ~/ 1000,
                hash: hash,
              );
              fileCount++;
              print("SYNC_SCAN: [+] Found: $relativePath");
            } catch (e) {
              print("SYNC_SCAN ERROR: Failed to read file ${entity.path}: $e");
            }
          }
        }
      }
      print("SYNC_SCAN COMPLETE: Found $fileCount files in $dirCount directories.");
    } catch (e) {
      print("SYNC_SCAN FATAL EXCEPTION: $e");
    }
    print("==================================================");

    return snapshot;
  }

  /// Calculates the delta between local and remote snapshots based on the sync mode.
  List<SyncOperation> calculateDelta({
    required Map<String, SyncFileInfo> local,
    required Map<String, SyncFileInfo> remote,
    required SyncMode mode,
    bool clientIsSource = true,
  }) {
    _client.log("SYNC: Calculating delta (Mode: $mode)");
    final List<SyncOperation> ops = [];

    if (mode == SyncMode.mirroring) {
      for (final path in local.keys) {
        if (!remote.containsKey(path)) {
          _client.log("SYNC: [MIRROR] Queue Upload: $path");
          ops.add(SyncOperation(SyncOpType.upload, path));
        } else {
          final localFile = local[path]!;
          final remoteFile = remote[path]!;
          if (localFile.hash != remoteFile.hash || localFile.hash == null) {
            if (localFile.mtime > remoteFile.mtime) {
              _client.log("SYNC: [MIRROR] Update Local -> Remote: $path");
              ops.add(SyncOperation(SyncOpType.upload, path));
            } else if (remoteFile.mtime > localFile.mtime) {
              _client.log("SYNC: [MIRROR] Update Remote -> Local: $path");
              ops.add(SyncOperation(SyncOpType.download, path));
            }
          }
        }
      }
      for (final path in remote.keys) {
        if (!local.containsKey(path)) {
          _client.log("SYNC: [MIRROR] Queue Download: $path");
          ops.add(SyncOperation(SyncOpType.download, path));
        }
      }
    } else if (mode == SyncMode.singleSourceOfTruth) {
      if (clientIsSource) {
        for (final path in local.keys) {
          final localFile = local[path]!;
          final remoteFile = remote[path];
          if (remoteFile == null || localFile.hash != remoteFile.hash || localFile.hash == null) {
            _client.log("SYNC: [BACKUP] Queue Upload: $path");
            ops.add(SyncOperation(SyncOpType.upload, path));
          }
        }
        for (final path in remote.keys) {
          if (!local.containsKey(path)) {
            _client.log("SYNC: [BACKUP] Queue Remote Delete: $path");
            ops.add(SyncOperation(SyncOpType.deleteRemote, path));
          }
        }
      } else {
        for (final path in remote.keys) {
          final remoteFile = remote[path]!;
          final localFile = local[path];
          if (localFile == null || remoteFile.hash != localFile.hash || remoteFile.hash == null) {
            _client.log("SYNC: [DIST] Queue Download: $path");
            ops.add(SyncOperation(SyncOpType.download, path));
          }
        }
        for (final path in local.keys) {
          if (!remote.containsKey(path)) {
            _client.log("SYNC: [DIST] Queue Local Delete: $path");
            ops.add(SyncOperation(SyncOpType.deleteLocal, path));
          }
        }
      }
    }

    _client.log("SYNC: Delta calc finished. Total ops: ${ops.length}");
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
    _client.log("SYNC_DEBUG[$myId]: Starting FULL_SYNC. RtcThinClient ID: $clientId");

    try {
      // 1. Generate local snapshot
      final local = await generateLocalSnapshot(pair.localPath);

      // 2. Request remote snapshot
      final List<dynamic> accumulatedFiles = [];
      final completer = Completer<List<dynamic>>();
      StreamSubscription? sub;

      final normRemote = pair.remotePath.replaceAll(RegExp(r'/+$'), '');
      _client.log("SYNC_DEBUG[$myId]: Registering snapshot listener for $normRemote");

      sub = _client.syncSnapshotStream.listen((msg) {
        final String respPath = msg.rootPath;
        final normResp = respPath.replaceAll(RegExp(r'/+$'), '');
        _client.log("SYNC_DEBUG[$myId]: Received snapshot chunk for $normResp (Final: ${msg.isFinal})");

        if (normResp == normRemote) {
          accumulatedFiles.addAll(msg.files);
          if (msg.isFinal) {
            _client.log("SYNC_DEBUG[$myId]: Completing snapshot future with ${accumulatedFiles.length} files.");
            sub?.cancel();
            if (!completer.isCompleted) completer.complete(accumulatedFiles);
          }
        }
      });

      await requestRemoteSnapshot(pair.remotePath);
      _client.log("SYNC_DEBUG[$myId]: Snapshot request sent. Waiting for response...");

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
      
      // 4. Update lastSynced timestamp
      final settings = SettingsService();
      final pairs = settings.syncPairs;
      final index = pairs.indexWhere((p) => p.localPath == pair.localPath && p.remotePath == pair.remotePath);
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
      }

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
      _client.log("SYNC: Folder is already up to date.");
      _client.sendEvent(IsolateAction.syncBatchProgress, {
        'completed': 0,
        'total': 0,
        'current_file': 'COMPLETE_NO_CHANGES',
      });
      return;
    }

    final totalItems = deltas.length;
    int completedItems = 0;
    
    // Calculate total bytes for the batch (uploads only for now, downloads are harder to estimate total size without another round-trip)
    int totalBytes = 0;
    for (var op in deltas) {
       if (op.type == SyncOpType.upload) {
          totalBytes += local[op.path]?.size ?? 0;
       }
    }
    
    int completedBytes = 0;
    int activeFileBytesTransferred = 0;
    final folderName = pair.localPath.split('/').last;
    final syncNotificationId = pair.localPath.hashCode.abs() % 10000;

    _client.log("SYNC: Commencing sequential execution of $totalItems operations...");
    _isSyncCancelled = false;

    try {
      for (final op in deltas) {
        if (_isSyncCancelled) {
          _client.log("SYNC: Operation aborted by user.");
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
          progress: totalBytes > 0 ? (completedBytes / totalBytes) : ((completedItems - 1) / totalItems),
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
                      ? ((completedBytes + activeFileBytesTransferred) / totalBytes) 
                      : ((completedItems - 1 + event.progress) / totalItems),
                );
            } else if (event is TransferProgressComplete) {
              statusSub?.cancel();
              completedBytes += (op.type == SyncOpType.upload ? (local[op.path]?.size ?? 0) : 0);
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
              _client.log("SYNC: [$completedItems/$totalItems] Uploading ${op.path}...");
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
              _client.log("SYNC: [$completedItems/$totalItems] Downloading ${op.path}...");
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
              _client.sendDcMsg(DcMsgDeleteFile(
                path: "${pair.remotePath}/${op.path}",
              ));
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
      final remoteList = await completer.future.timeout(const Duration(seconds: 30));
      
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
}
