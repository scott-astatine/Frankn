import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'dart:typed_data';
import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:frankn/services/rtc_thin_client.dart';
import 'package:frankn/utils/utils.dart';
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
    _client.sendDcMsg({DcMsg.Key: DcMsg.SyncRequest, "path": remotePath});
  }
}
