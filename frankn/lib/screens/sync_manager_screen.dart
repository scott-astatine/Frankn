import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:frankn/services/isolate_protocol.dart';
import 'package:frankn/services/permission_service.dart';
import 'package:frankn/services/rtc_thin_client.dart';
import 'package:frankn/services/settings_service.dart';
import 'package:frankn/utils/utils.dart';
import 'package:frankn/utils/dc_msg_util.dart';
import 'package:frankn/widgets/cyber_alert_dialog.dart';
import 'package:frankn/widgets/settings/remote_dir_selector.dart';
import 'package:frankn/generated/l10n/app_localizations.dart';
import 'package:google_fonts/google_fonts.dart';

class SyncManagerScreen extends StatefulWidget {
  const SyncManagerScreen({super.key});

  @override
  State<SyncManagerScreen> createState() => _SyncManagerScreenState();
}

class _SyncManagerScreenState extends State<SyncManagerScreen> {
  final _settings = SettingsService();
  final _client = RtcThinClient();

  List<SyncPair> _pairs = [];
  final Map<String, SyncStatusEvent> _syncStatus = {};
  bool _isSyncing = false;
  String _currentSyncFile = "";
  int _syncTotal = 0;
  int _syncCurrent = 0;

  @override
  void initState() {
    super.initState();
    _pairs = _settings.syncPairs;
    _checkPermissions();

    _client.syncStatusStream.listen((event) {
      if (!mounted) return;
      setState(() {
        _syncStatus[event.localPath] = event;
      });
    });

    _client.syncBatchProgressStream.listen((event) async {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      setState(() {
        _isSyncing =
            event.currentFile != 'COMPLETE' &&
            event.currentFile != 'COMPLETE_NO_CHANGES' &&
            !event.currentFile.startsWith('ERROR');
        _syncCurrent = event.completed;
        _syncTotal = event.total;
        _currentSyncFile = event.currentFile;
      });

      if (event.currentFile == 'COMPLETE' ||
          event.currentFile == 'COMPLETE_NO_CHANGES') {
        // Reload settings to get updated lastSynced timestamp from background isolate
        await _settings.reload();
        if (!mounted) return;
        setState(() {
          _pairs = _settings.syncPairs;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              event.currentFile == 'COMPLETE'
                  ? l10n.folderSyncComplete
                  : l10n.folderSyncCompleteNoChanges,
            ),
            backgroundColor: AppColors.matrixGreen,
          ),
        );
      } else if (event.currentFile.startsWith('ERROR')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(event.currentFile),
            backgroundColor: AppColors.errorRed,
          ),
        );
      }
    });
  }

  Future<void> _checkPermissions() async {
    final granted = await PermissionService().requestStoragePermissions();
    if (!granted && mounted) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.fullStorageAccessRequired),
          backgroundColor: AppColors.errorRed,
        ),
      );
    }
  }

  Future<void> _showPairDialog({SyncPair? initialPair}) async {
    final l10n = AppLocalizations.of(context)!;
    String? localPath = initialPair?.localPath;
    String? remotePath = initialPair?.remotePath;
    SyncMode mode = initialPair?.mode ?? SyncMode.singleSourceOfTruth;
    bool clientIsSource = initialPair?.clientIsSource ?? true;
    int intervalMinutes = initialPair?.intervalMinutes ?? 60;

    final result = await showDialog<SyncPair>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return CyberAlertDialog(
              title: initialPair == null ? l10n.establishNewLink : l10n.modifyLink,
              borderColor: AppColors.neonCyan,
              titleColor: Colors.white,
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Local Path
                    _buildDialogField(
                      label: l10n.localDir,
                      icon: Icons.smartphone_rounded,
                      value: localPath ?? l10n.notSelected,
                      actionIcon: Icons.create_new_folder_outlined,
                      onTap: () async {
                        String? selected =
                            await FilePicker.platform.getDirectoryPath();
                        if (selected != null) {
                          setDialogState(() => localPath = selected);
                        }
                      },
                    ),
                    const SizedBox(height: 20),

                    // Remote Path
                    _buildDialogField(
                      label: l10n.remoteDir,
                      icon: Icons.dns_outlined,
                      value: remotePath ?? l10n.notSelected,
                      actionIcon: Icons.terminal_rounded,
                      onTap: () async {
                        final selected = await showModalBottomSheet<String>(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder:
                              (context) => RemoteDirSelector(client: _client),
                        );
                        if (selected != null) {
                          setDialogState(() => remotePath = selected);
                        }
                      },
                    ),
                    const SizedBox(height: 20),

                    // Strategy Dropdown
                    _buildSyncStrategyDropdown(
                      mode,
                      (v) => setDialogState(() => mode = v!),
                    ),

                    if (mode == SyncMode.singleSourceOfTruth) ...[
                      const SizedBox(height: 16),
                      _buildClientSourceToggle(
                        clientIsSource,
                        (v) => setDialogState(() => clientIsSource = v),
                      ),
                    ],
                    const SizedBox(height: 20),

                    // Interval Dropdown
                    _buildIntervalDropdown(
                      intervalMinutes,
                      (v) => setDialogState(() => intervalMinutes = v!),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    l10n.abort,
                    style: GoogleFonts.inter(
                      color: Colors.white54,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: () {
                    if (localPath != null && remotePath != null) {
                      Navigator.pop(
                        context,
                        SyncPair(
                          localPath: localPath!,
                          remotePath: remotePath!,
                          mode: mode,
                          clientIsSource: clientIsSource,
                          intervalMinutes: intervalMinutes,
                          lastSynced: initialPair?.lastSynced,
                        ),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.neonCyan,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.bolt_rounded, size: 18),
                  label: Text(
                    initialPair == null ? l10n.establish : l10n.update,
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null) {
      setState(() {
        if (initialPair != null) {
          final index = _pairs.indexOf(initialPair);
          if (index != -1) _pairs[index] = result;
        } else {
          _pairs.add(result);
        }
        _settings.setSyncPairs(_pairs);
      });
      
      // Trigger a status check for the new/updated pair if connected
      if (_client.currentHostState == HostConnectionState.authenticated) {
         _client.sendIntent(IsolateAction.triggerBackgroundSync, result.toJson());
      }
    }
  }

  Widget _buildSyncStrategyDropdown(SyncMode value, ValueChanged<SyncMode?> onChanged) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.syncStrategy,
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
              value: value,
              isExpanded: true,
              dropdownColor: AppColors.voidBlack,
              icon: const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Colors.white38,
                size: 20,
              ),
              items: [
                SyncMode.singleSourceOfTruth,
                SyncMode.mirroring,
              ].map((m) {
                return DropdownMenuItem(
                  value: m,
                  child: Text(
                    m == SyncMode.mirroring
                        ? l10n.bidirectionalMirror
                        : l10n.singleSourceBackup,
                    style: GoogleFonts.jetBrainsMono(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                );
              }).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildClientSourceToggle(bool value, ValueChanged<bool> onChanged) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: SwitchListTile(
        title: Text(
          l10n.clientIsSourceLabel,
          style: GoogleFonts.jetBrainsMono(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        value: value,
        activeThumbColor: AppColors.neonCyan,
        activeTrackColor: AppColors.neonCyan.withValues(alpha: 0.3),
        inactiveThumbColor: Colors.grey,
        inactiveTrackColor: Colors.white10,
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildIntervalDropdown(int value, ValueChanged<int?> onChanged) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.syncInterval,
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
            child: DropdownButton<int>(
              value: value,
              isExpanded: true,
              dropdownColor: AppColors.voidBlack,
              icon: const Icon(
                Icons.timer_outlined,
                color: Colors.white38,
                size: 20,
              ),
              items: [5, 15, 30, 60, 360, 1440].map((m) {
                String label;
                if (m < 60) {
                  label = l10n.everyNMinutes(m);
                } else if (m == 60) {
                  label = l10n.everyHour;
                } else if (m == 360) {
                  label = l10n.every6Hours;
                } else {
                  label = l10n.onceADay;
                }
                return DropdownMenuItem(
                  value: m,
                  child: Text(
                    label,
                    style: GoogleFonts.jetBrainsMono(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                );
              }).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
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
                      color: value == "NOT_SELECTED"
                          ? Colors.white38
                          : Colors.white,
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

    _client.log("SYNC: Triggering background sync for ${pair.localPath}");

    setState(() {
      _isSyncing = true;
      _syncCurrent = 0;
      _syncTotal = 0;
      _currentSyncFile = "HANDING_OFF_TO_BACKGROUND...";
    });

    _client.sendIntent(IsolateAction.triggerBackgroundSync, pair.toJson());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: const Color(0xFF09090B), // Zinc-950
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          l10n.folderSynchronization,
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 24,
                    ),
                    itemCount: _pairs.length,
                    itemBuilder: (context, index) =>
                        _buildPairCard(_pairs[index]),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _isSyncing ? null : () => _showPairDialog(),
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
    final l10n = AppLocalizations.of(context)!;
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
                  "${l10n.syncing} $_currentSyncFile",
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
              const SizedBox(width: 12),
              IconButton(
                icon: const Icon(
                  Icons.stop_circle_outlined,
                  color: AppColors.errorRed,
                  size: 20,
                ),
                onPressed: () {
                   _client.sendIntent(IsolateAction.stopSync);
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
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
    final l10n = AppLocalizations.of(context)!;
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
            l10n.noSyncPairsEstablished,
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
    final l10n = AppLocalizations.of(context)!;
    final isMirror = pair.mode == SyncMode.mirroring;

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0x4D18181B), // Zinc-900 at 30% opacity
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xCC27272A),
          ), // Zinc-800 at 80% opacity
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
                    isMirror
                        ? Icons.sync_alt_rounded
                        : Icons.cloud_upload_outlined,
                    color: isMirror ? AppColors.neonCyan : AppColors.neonCyan,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      isMirror
                          ? l10n.bidirectionalMirror
                          : l10n.singleSourceBackup,
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
                      Icons.edit_outlined,
                      color: Colors.white38,
                      size: 20,
                    ),
                    onPressed: () => _showPairDialog(initialPair: pair),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 12),
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
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.05),
                  ),
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildPathRow(
                      Icons.smartphone_rounded,
                      l10n.localEndpoint,
                      pair.localPath,
                    ),

                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Divider(
                              color: Colors.white.withValues(alpha: 0.1),
                              thickness: 1,
                              height: 1,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.neonCyan.withValues(
                                  alpha: 0.1,
                                ),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    isMirror
                                        ? Icons.swap_vert_rounded
                                        : Icons.arrow_upward_rounded,
                                    color: AppColors.neonCyan,
                                    size: 10,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    isMirror ? l10n.mirror : l10n.backup,
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
                            child: Divider(
                              color: Colors.white.withValues(alpha: 0.1),
                              thickness: 1,
                              height: 1,
                            ),
                          ),
                        ],
                      ),
                    ),

                    _buildPathRow(
                      Icons.dns_outlined,
                      l10n.remoteEndpoint,
                      pair.remotePath,
                    ),

                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        if (pair.lastSynced != null)
                          Row(
                            children: [
                              const Icon(
                                Icons.history_rounded,
                                size: 12,
                                color: Colors.white38,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                l10n.lastSyncedLabel(
                                  DateTime.fromMillisecondsSinceEpoch(
                                    pair.lastSynced! * 1000,
                                  ).toIso8601String().substring(11, 16),
                                ),
                                style: GoogleFonts.jetBrainsMono(
                                  color: AppColors.matrixGreen.withValues(
                                    alpha: 0.7,
                                  ),
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          )
                        else
                          const SizedBox(),
                        
                        // Status Badge
                        if (_syncStatus.containsKey(pair.localPath))
                          _buildStatusBadge(_syncStatus[pair.localPath]!)
                        else if (_client.currentHostState == HostConnectionState.authenticated)
                          Text(
                            l10n.verifying,
                            style: GoogleFonts.jetBrainsMono(
                              color: Colors.white24,
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                      ],
                    ),
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
                      side: BorderSide(
                        color: AppColors.neonCyan.withValues(alpha: 0.3),
                      ),
                    ),
                    elevation: 0,
                  ),
                  icon: const Icon(Icons.play_arrow_outlined, size: 18),
                  label: Text(
                    l10n.triggerSyncNow,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(SyncStatusEvent status) {
    final l10n = AppLocalizations.of(context)!;
    final int pending = status.pendingChanges;
    final bool inSync = pending == 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: (inSync ? AppColors.matrixGreen : AppColors.neonPink).withValues(
          alpha: 0.1,
        ),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: (inSync ? AppColors.matrixGreen : AppColors.neonPink)
              .withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            inSync ? Icons.check_circle_outline : Icons.pending_outlined,
            color: inSync ? AppColors.matrixGreen : AppColors.neonPink,
            size: 10,
          ),
          const SizedBox(width: 4),
          Text(
            inSync ? l10n.inSync : l10n.changesPending(pending),
            style: GoogleFonts.jetBrainsMono(
              color: inSync ? AppColors.matrixGreen : AppColors.neonPink,
              fontSize: 8,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
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
          style: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 11),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
