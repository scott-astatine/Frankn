import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:frankn/services/isolate_protocol.dart';
import 'package:frankn/services/permission_service.dart';
import 'package:frankn/services/rtc_thin_client.dart';
import 'package:frankn/services/settings_service.dart';
import 'package:frankn/services/sync_service.dart';
import 'package:frankn/utils/utils.dart';
import 'package:frankn/widgets/settings/remote_dir_selector.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';

class SyncManagerScreen extends StatefulWidget {
  const SyncManagerScreen({super.key});

  @override
  State<SyncManagerScreen> createState() => _SyncManagerScreenState();
}

class _SyncManagerScreenState extends State<SyncManagerScreen> {
  final _settings = SettingsService();
  final _syncService = SyncService();
  final _client = RtcThinClient();

  List<SyncPair> _pairs = [];
  bool _isSyncing = false;
  String _currentSyncFile = "";
  int _syncTotal = 0;
  int _syncCurrent = 0;

  @override
  void initState() {
    super.initState();
    _pairs = _settings.syncPairs;
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    final granted = await PermissionService().requestStoragePermissions();
    if (!granted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("FULL_STORAGE_ACCESS_REQUIRED_FOR_SYNC"),
          backgroundColor: AppColors.errorRed,
        ),
      );
    }
  }

  Future<void> _addPair() async {
    String? localPath;
    String? remotePath;
    SyncMode mode = SyncMode.mirroring;
    bool clientIsSource = true;

    final result = await showDialog<SyncPair>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.neonCyan.withValues(alpha: 0.5),
                    width: 1.0,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black54,
                      blurRadius: 20,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 8),
                          child: const SizedBox(height: 1),
                        ),
                      ),
                      Positioned.fill(
                        child: Container(
                          color: AppColors.voidBlack.withValues(alpha: 0.8),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.link_rounded, color: AppColors.neonCyan, size: 20),
                                      const SizedBox(width: 12),
                                      Text(
                                        "ESTABLISH_NEW_LINK",
                                        style: GoogleFonts.jetBrainsMono(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 14,
                                          letterSpacing: 1,
                                        ),
                                      ),
                                    ],
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.close, color: Colors.white38, size: 20),
                                    onPressed: () => Navigator.pop(context),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Divider(color: Colors.white.withValues(alpha: 0.1), height: 1),
                              const SizedBox(height: 24),
                              
                              // Local Path
                              _buildDialogField(
                                label: "LOCAL_DIR",
                                icon: Icons.smartphone_rounded,
                                value: localPath ?? "NOT_SELECTED",
                                actionIcon: Icons.create_new_folder_outlined,
                                onTap: () async {
                                  String? selected = await FilePicker.platform.getDirectoryPath();
                                  if (selected != null) {
                                    setDialogState(() => localPath = selected);
                                  }
                                },
                              ),
                              const SizedBox(height: 20),
                              
                              // Remote Path
                              _buildDialogField(
                                label: "REMOTE_DIR",
                                icon: Icons.dns_outlined,
                                value: remotePath ?? "NOT_SELECTED",
                                actionIcon: Icons.terminal_rounded,
                                onTap: () async {
                                  final selected = await showModalBottomSheet<String>(
                                    context: context,
                                    isScrollControlled: true,
                                    backgroundColor: Colors.transparent,
                                    builder: (context) => RemoteDirSelector(client: _client),
                                  );
                                  if (selected != null) {
                                    setDialogState(() => remotePath = selected);
                                  }
                                },
                              ),
                              const SizedBox(height: 20),

                              // Sync Strategy
                              Text(
                                "SYNC_STRATEGY",
                                style: GoogleFonts.inter(
                                  color: Colors.white38,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                                ),
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<SyncMode>(
                                    value: mode,
                                    isExpanded: true,
                                    dropdownColor: AppColors.voidBlack,
                                    icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white38, size: 20),
                                    items: SyncMode.values.map((m) {
                                      return DropdownMenuItem(
                                        value: m,
                                        child: Text(
                                          m == SyncMode.mirroring
                                              ? "BIDIRECTIONAL_MIRROR"
                                              : "SINGLE_SOURCE_BACKUP",
                                          style: GoogleFonts.jetBrainsMono(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                    onChanged: (v) {
                                      if (v != null) setDialogState(() => mode = v);
                                    },
                                  ),
                                ),
                              ),
                              if (mode == SyncMode.singleSourceOfTruth) ...[
                                const SizedBox(height: 16),
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.3),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                                  ),
                                  child: SwitchListTile(
                                    title: Text(
                                      "CLIENT IS SOURCE",
                                      style: GoogleFonts.jetBrainsMono(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    value: clientIsSource,
                                    activeThumbColor: AppColors.neonCyan,
                                    activeTrackColor: AppColors.neonCyan.withValues(alpha: 0.3),
                                    inactiveThumbColor: Colors.grey,
                                    inactiveTrackColor: Colors.white10,
                                    onChanged: (v) => setDialogState(() => clientIsSource = v),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 32),

                              // Actions
                              Row(
                                children: [
                                  Expanded(
                                    child: TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(vertical: 16),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                                        ),
                                      ),
                                      child: Text(
                                        "ABORT",
                                        style: GoogleFonts.inter(
                                          color: Colors.white54,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: () {
                                        if (localPath != null && remotePath != null) {
                                          Navigator.pop(
                                            context,
                                            SyncPair(
                                              localPath: localPath!,
                                              remotePath: remotePath!,
                                              mode: mode,
                                              clientIsSource: clientIsSource,
                                            ),
                                          );
                                        }
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.neonCyan,
                                        foregroundColor: Colors.black,
                                        padding: const EdgeInsets.symmetric(vertical: 16),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                      ),
                                      icon: const Icon(Icons.bolt_rounded, size: 18),
                                      label: Text(
                                        "ESTABLISH",
                                        style: GoogleFonts.inter(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (result != null) {
      setState(() {
        _pairs.add(result);
        _settings.setSyncPairs(_pairs);
      });
    }
  }

  Widget _buildDialogField({
    required String label,
    required IconData icon,
    required String value,
    required IconData actionIcon,
    required VoidCallback onTap,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: Colors.white38),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.inter(
                color: Colors.white38,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value,
                    style: GoogleFonts.jetBrainsMono(
                      color: value == "NOT_SELECTED" ? Colors.white38 : Colors.white,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(actionIcon, color: AppColors.neonCyan, size: 18),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _triggerSync(SyncPair pair) async {
    if (_isSyncing) return;

    _client.log("SYNC: Triggered for ${pair.localPath} <-> ${pair.remotePath}");

    setState(() {
      _isSyncing = true;
      _syncCurrent = 0;
      _syncTotal = 0;
      _currentSyncFile = "INITIALIZING...";
    });

    try {
      // 1. Generate local snapshot
      _client.log("SYNC: Scanning local folder ${pair.localPath}...");
      final local = await _syncService.generateLocalSnapshot(pair.localPath);
      _client.log("SYNC: Local scan finished. Found ${local.length} files.");

      // 2. Request remote snapshot
      _client.log("SYNC: Requesting remote snapshot for ${pair.remotePath}...");

      final List<dynamic> accumulatedFiles = [];
      StreamSubscription? sub;

      // Path normalization for comparison: strip all trailing slashes
      final normRemote = pair.remotePath.replaceAll(RegExp(r'/+$'), '');

      sub = _client.syncSnapshotStream.listen((data) {
        print("RAW_SYNC_UI: ${jsonEncode(data)}");
        final String respPath = data['root_path'];
        final normResp = respPath.replaceAll(RegExp(r'/+$'), '');

        print("SYNC: Comparing [$normResp] == [$normRemote]");

        if (normResp == normRemote) {
          accumulatedFiles.addAll(data['files']);

          if (data['is_final'] == true) {
            _client.log(
              "SYNC: Received FINAL remote snapshot. Processing batch...",
            );
            sub!.cancel();
            _executeSyncBatch(pair, local, accumulatedFiles);
          } else {
            _client.log(
              "SYNC: Received chunk... (${accumulatedFiles.length} files accumulated)",
            );
            if (mounted) {
              setState(
                () => _currentSyncFile =
                    "FETCHING_REMOTE_STATE: ${accumulatedFiles.length}",
              );
            }
          }
        } else {
          _client.log(
            "SYNC WARN: Received snapshot for non-matching path: $respPath",
          );
        }
      });

      await _syncService.requestRemoteSnapshot(pair.remotePath);

      // Auto-cancel listener after timeout if no response
      Future.delayed(const Duration(seconds: 30), () {
        if (sub != null && accumulatedFiles.isEmpty) {
          _client.log("SYNC ERROR: Remote snapshot request timed out.");
          sub.cancel();
          if (mounted) setState(() => _isSyncing = false);
        }
      });
    } catch (e) {
      _client.log("SYNC ERROR: Trigger failed: $e");
      setState(() => _isSyncing = false);
    }
  }

  Future<void> _executeSyncBatch(
    SyncPair pair,
    Map<String, SyncFileInfo> local,
    List<dynamic> remoteList,
  ) async {
    final Map<String, SyncFileInfo> remote = {};
    for (var f in remoteList) {
      final info = SyncFileInfo.fromJson(f);
      remote[info.path] = info;
    }

    final deltas = _syncService.calculateDelta(
      local: local,
      remote: remote,
      mode: pair.mode,
      clientIsSource: pair.clientIsSource,
    );

    if (deltas.isEmpty) {
      _client.log("SYNC: Folder is already up to date.");
      if (mounted) {
        setState(() => _isSyncing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("FOLDER_SYNC_COMPLETE: NO_CHANGES"),
            backgroundColor: AppColors.matrixGreen,
          ),
        );
      }
      return;
    }

    setState(() {
      _syncTotal = deltas.length;
      _syncCurrent = 0;
    });

    _client.log(
      "SYNC: Commencing sequential execution of ${deltas.length} operations...",
    );

    for (final op in deltas) {
      if (!mounted) break;

      setState(() {
        _syncCurrent++;
        _currentSyncFile = op.path;
      });

      final completer = Completer<bool>();
      final transferId = const Uuid().v4();

      // Listen for the specific transfer completion
      StreamSubscription? statusSub;
      statusSub = _client.transferProgressStream.listen((data) {
        if (data['id'] == transferId) {
          if (data['type'] == 'complete') {
            statusSub!.cancel();
            completer.complete(true);
          } else if (data['type'] == 'failed') {
            statusSub!.cancel();
            completer.complete(false);
          }
        }
      });

      try {
        switch (op.type) {
          case SyncOpType.upload:
            _client.log(
              "SYNC: [$_syncCurrent/$_syncTotal] Uploading ${op.path}...",
            );
            _client.sendIntent(IsolateAction.uploadInit, {
              'id': transferId,
              'local_path': "${pair.localPath}/${op.path}",
              'remote_path': "${pair.remotePath}/${op.path}",
              'file_name': op.path.split('/').last,
              'hash': local[op.path]!.hash,
            });
            await completer.future.timeout(const Duration(minutes: 5));
            break;

          case SyncOpType.download:
            _client.log(
              "SYNC: [$_syncCurrent/$_syncTotal] Downloading ${op.path}...",
            );
            _client.sendIntent(IsolateAction.downloadInit, {
              'id': transferId,
              'path': "${pair.remotePath}/${op.path}",
              'target_dir': pair.localPath,
              'show_notification': false,
            });
            await completer.future.timeout(const Duration(minutes: 5));
            break;

          case SyncOpType.deleteRemote:
            _client.log("SYNC: Deleting remote ${op.path}...");
            _client.sendDcMsg({
              DcMsg.Key: DcMsg.DeleteFile,
              "path": "${pair.remotePath}/${op.path}",
            });
            await Future.delayed(const Duration(milliseconds: 100));
            break;

          case SyncOpType.deleteLocal:
            _client.log("SYNC: Deleting local ${op.path}...");
            final file = File("${pair.localPath}/${op.path}");
            if (await file.exists()) await file.delete();
            await Future.delayed(const Duration(milliseconds: 100));
            break;
        }
      } catch (e) {
        _client.log("SYNC ERROR: Failed op for ${op.path}: $e");
        statusSub.cancel();
      }
    }

    _client.log("SYNC: Batch processing finished.");
    if (mounted) {
      setState(() => _isSyncing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("FOLDER_SYNC_COMPLETE"),
          backgroundColor: AppColors.matrixGreen,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF09090B), // Zinc-950
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "FOLDER_SYNCHRONIZATION",
          style: GoogleFonts.jetBrainsMono(
            fontWeight: FontWeight.w900,
            fontSize: 14,
            letterSpacing: 1,
            color: Colors.white,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(
            color: Colors.white.withValues(alpha: 0.1),
            height: 1.0,
          ),
        ),
      ),
      body: Column(
        children: [
          if (_isSyncing) _buildSyncProgressHeader(),
          Expanded(
            child: _pairs.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                    itemCount: _pairs.length,
                    itemBuilder: (context, index) =>
                        _buildPairCard(_pairs[index]),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _isSyncing ? null : _addPair,
        backgroundColor: _isSyncing
            ? Colors.white10
            : const Color(0xFF083344), // Very dark cyan
        foregroundColor: _isSyncing ? Colors.white24 : AppColors.neonCyan,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: _isSyncing ? Colors.white10 : AppColors.neonCyan,
            width: 1.5,
          ),
        ),
        elevation: 0,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildSyncProgressHeader() {
    final progress = _syncTotal > 0 ? _syncCurrent / _syncTotal : 0.0;
    return Container(
      width: double.infinity,
      color: const Color(0xFF18181B), // Zinc-900
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.neonCyan,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  "SYNCING: $_currentSyncFile",
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                "$_syncCurrent / $_syncTotal",
                style: GoogleFonts.jetBrainsMono(
                  color: AppColors.neonCyan,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.white10,
              color: AppColors.neonCyan,
              minHeight: 3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.folder_off_outlined,
            size: 64,
            color: Colors.white.withValues(alpha: 0.1),
          ),
          const SizedBox(height: 16),
          Text(
            "NO_SYNC_PAIRS_ESTABLISHED",
            style: GoogleFonts.jetBrainsMono(
              color: Colors.white38,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPairCard(SyncPair pair) {
    final isMirror = pair.mode == SyncMode.mirroring;
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0x4D18181B), // Zinc-900 at 30% opacity
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xCC27272A)), // Zinc-800 at 80% opacity
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Row(
                children: [
                  Icon(
                    isMirror ? Icons.sync_alt_rounded : Icons.cloud_upload_outlined,
                    color: isMirror ? AppColors.neonCyan : AppColors.neonCyan,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      isMirror ? "BIDIRECTIONAL_MIRROR" : "PRIVATE_CLOUD_BACKUP",
                      style: GoogleFonts.jetBrainsMono(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      color: Colors.white38,
                      size: 20,
                    ),
                    onPressed: () {
                      setState(() {
                        _pairs.remove(pair);
                        _settings.setSyncPairs(_pairs);
                      });
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            
            // Path Info Box
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildPathRow(Icons.smartphone_rounded, "LOCAL_ENDPOINT", pair.localPath),
                    
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Divider(color: Colors.white.withValues(alpha: 0.1), thickness: 1, height: 1),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.neonCyan.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    isMirror ? Icons.swap_vert_rounded : Icons.arrow_upward_rounded,
                                    color: AppColors.neonCyan,
                                    size: 10,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    isMirror ? "MIRROR" : "BACKUP",
                                    style: GoogleFonts.jetBrainsMono(
                                      color: AppColors.neonCyan,
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Expanded(
                            child: Divider(color: Colors.white.withValues(alpha: 0.1), thickness: 1, height: 1),
                          ),
                        ],
                      ),
                    ),
                    
                    _buildPathRow(Icons.dns_outlined, "REMOTE_ENDPOINT", pair.remotePath),
                  ],
                ),
              ),
            ),
            
            // Trigger Button
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isSyncing ? null : () => _triggerSync(pair),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF083344), // Very dark cyan
                    foregroundColor: AppColors.neonCyan,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: AppColors.neonCyan.withValues(alpha: 0.3)),
                    ),
                    elevation: 0,
                  ),
                  icon: const Icon(Icons.play_arrow_outlined, size: 18),
                  label: Text(
                    "TRIGGER_SYNC_NOW",
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPathRow(IconData icon, String label, String path) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 12, color: Colors.white38),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.inter(
                color: Colors.white54,
                fontSize: 9,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          path,
          style: GoogleFonts.jetBrainsMono(
            color: Colors.white,
            fontSize: 11,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
