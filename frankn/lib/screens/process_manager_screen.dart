import 'dart:async';
import 'package:flutter/material.dart';
import 'package:frankn/services/rtc_thin_client.dart';
import 'package:frankn/utils/utils.dart';
import 'package:frankn/utils/cyber_card.dart';
import 'package:frankn/utils/cyber_button.dart';
import 'package:frankn/generated/l10n/app_localizations.dart';
import 'package:google_fonts/google_fonts.dart';

class ProcessManagerScreen extends StatefulWidget {
  final RtcThinClient client;
  const ProcessManagerScreen({super.key, required this.client});

  @override
  State<ProcessManagerScreen> createState() => _ProcessManagerScreenState();
}

class _ProcessManagerScreenState extends State<ProcessManagerScreen> {
  List<dynamic> _processes = [];
  Map<String, dynamic>? _stats;
  bool _isLoading = true;
  String _searchQuery = "";
  String _sortBy = "cpu"; // cpu, memory, name
  String? _expandedPid;
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  StreamSubscription? _telemetrySub;

  @override
  void initState() {
    super.initState();
    _fetchProcesses();

    // 1. Listen for process list responses
    widget.client.commandResponseStream.listen((resp) {
      if (!mounted) return;
      final data = resp['type'] == 'response' ? resp['data'] : resp;
      if (data != null && data is Map && data.containsKey('processes')) {
        setState(() {
          _processes = data['processes'];
          // Only update stats if we don't have a live telemetry feed yet
          _stats ??= data['stats'];
          _isLoading = false;
        });
      }
    });

    // 2. Hook into LIVE telemetry heartbeat for the top bars
    _telemetrySub = widget.client.commandResponseStream.listen((resp) {
      if (!mounted) return;
      if (resp['type'] == 'telemetry') {
        setState(() {
          _stats = resp;
        });
      }
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _telemetrySub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _fetchProcesses() {
    setState(() => _isLoading = true);
    widget.client.sendDcMsg({
      DcMsg.Key: DcMsg.ListProcesses,
      "sort_by": _sortBy,
      "filter": _searchQuery.isEmpty ? null : _searchQuery,
    });
  }

  void _onSearchChanged(String value) {
    _searchQuery = value;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 500), () {
      _fetchProcesses();
    });
  }

  void _confirmKill(String pid, String name) {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0F0F0F),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.errorRed),
        ),
        title: Text(
          "${l10n.terminateIntent.toUpperCase()} // ${name.toUpperCase()}",
          style: const TextStyle(
            color: AppColors.errorRed,
            fontSize: 14,
            fontWeight: FontWeight.w900,
          ),
        ),
        content: Text(
          l10n.killProcessConfirm(pid),
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              l10n.abort.toUpperCase(),
              style: const TextStyle(color: AppColors.textGrey),
            ),
          ),
          CyberButton(
            text: l10n.confirm.toUpperCase(),
            variant: CyberButtonVariant.destructive,
            isSmall: true,
            onPressed: () {
              Navigator.pop(context);
              widget.client.sendDcMsg({DcMsg.Key: DcMsg.Kill, "proc": pid});
              _fetchProcesses();
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: AppColors.voidBlack,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(l10n),
            _buildSystemStats(l10n),
            const SizedBox(height: 16),
            Expanded(
              child: _isLoading && _processes.isEmpty
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.neonCyan,
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _processes.length,
                      itemBuilder: (context, index) =>
                          _buildProcessRow(_processes[index], l10n),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.neonCyan),
            onPressed: () => Navigator.pop(context),
          ),
          if (_isSearching)
            Expanded(
              child: TextField(
                controller: _searchController,
                autofocus: true,
                onChanged: _onSearchChanged,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: l10n.filterProcesses.toUpperCase(),
                  hintStyle: const TextStyle(
                    color: Colors.white24,
                    fontSize: 12,
                  ),
                  border: InputBorder.none,
                ),
              ),
            )
          else
            Expanded(
              child: Text(
                l10n.processes.toUpperCase(),
                style: GoogleFonts.nanumMyeongjo(
                  color: AppColors.neonCyan,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
            ),
          IconButton(
            icon: Icon(
              _isSearching ? Icons.close : Icons.search,
              color: AppColors.neonCyan,
              size: 20,
            ),
            onPressed: () => setState(() {
              _isSearching = !_isSearching;
              if (!_isSearching) {
                _searchQuery = "";
                _searchController.clear();
                _fetchProcesses();
              }
            }),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort, color: AppColors.neonCyan, size: 20),
            onSelected: (val) {
              setState(() => _sortBy = val);
              _fetchProcesses();
            },
            color: const Color(0xFF0F0F0F),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: "cpu",
                child: Text(
                  l10n.cpu.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              PopupMenuItem(
                value: "memory",
                child: Text(
                  l10n.ram.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              PopupMenuItem(
                value: "name",
                child: Text(
                  l10n.sortByName.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(
              Icons.refresh,
              color: AppColors.neonCyan,
              size: 20,
            ),
            onPressed: _fetchProcesses,
          ),
        ],
      ),
    );
  }

  Widget _buildSystemStats(AppLocalizations l10n) {
    final cpu = (_stats?['cpu_load'] as num?)?.toDouble() ?? 0.0;
    final usedMem = (_stats?['used_mem'] as num?)?.toDouble() ?? 0.0;
    final totalMem = (_stats?['total_mem'] as num?)?.toDouble() ?? 1.0;
    final memPerc = (usedMem / totalMem) * 100;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          _buildStatBar(
            "SYSTEM_LOAD",
            "${cpu.toStringAsFixed(1)}%",
            cpu / 100,
            AppColors.neonCyan,
          ),
          const SizedBox(height: 16),
          _buildStatBar(
            "MEMORY_UTILIZATION",
            "${memPerc.toStringAsFixed(1)}%",
            memPerc / 100,
            AppColors.neonPink,
          ),
        ],
      ),
    );
  }

  Widget _buildStatBar(
    String label,
    String value,
    double progress,
    Color color,
  ) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w900,
                color: Colors.white24,
                letterSpacing: 1.5,
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontFamily: 'JetBrainsMonoNerdFont',
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Stack(
          children: [
            Container(
              height: 4,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 500),
              height: 4,
              width:
                  MediaQuery.of(context).size.width *
                  (progress.clamp(0.0, 1.0)),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.5),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildProcessRow(dynamic proc, AppLocalizations l10n) {
    final pid = proc['pid'].toString();
    final name = proc['name'].toString();
    final isExpanded = _expandedPid == pid;
    final cpu = (proc['cpu'] as num).toDouble();
    final mem = FileUtils.formatSize((proc['memory'] as num).toInt());

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: CyberCard(
        borderColor: isExpanded
            ? AppColors.textGrey.withValues(alpha: 0.2)
            : Colors.white.withValues(alpha: 0.02),
        child: InkWell(
          onTap: () => setState(() => _expandedPid = isExpanded ? null : pid),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              _buildBadge("P: $pid", Colors.white10),
                              const SizedBox(width: 8),
                              _buildBadge(
                                "C: ${cpu.toStringAsFixed(1)}%",
                                AppColors.cyberYellow.withValues(alpha: 0.15),
                                textColor: AppColors.cyberYellow,
                              ),
                              const SizedBox(width: 8),
                              _buildBadge(
                                "M: $mem",
                                AppColors.matrixGreen.withValues(alpha: 0.15),
                                textColor: AppColors.matrixGreen,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.close,
                      color: isExpanded ? AppColors.errorRed : Colors.white10,
                      size: 20,
                    ),
                  ],
                ),
                if (isExpanded) ...[
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      _buildDetailItem(
                        l10n.status.toUpperCase(),
                        proc['status']?.toString() ?? "RUNNING",
                        valueColor: AppColors.matrixGreen,
                      ),
                      const SizedBox(width: 48),
                      _buildDetailItem("USER", proc['user'].toString()),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    l10n.cmdPath.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textGrey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.05),
                      ),
                    ),
                    child: Text(
                      proc['cmd'] ?? "N/A",
                      style: const TextStyle(
                        fontFamily: 'JetBrainsMonoNerdFont',
                        fontSize: 11,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: CyberButton(
                      text: l10n.killProcess.toUpperCase(),
                      variant: CyberButtonVariant.destructive,
                      onPressed: () => _confirmKill(pid, name),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBadge(String label, Color bgColor, {Color? textColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'JetBrainsMonoNerdFont',
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: textColor ?? AppColors.textGrey,
        ),
      ),
    );
  }

  Widget _buildDetailItem(String label, String value, {Color? valueColor}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w900,
            color: AppColors.textGrey,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: valueColor ?? Colors.white,
          ),
        ),
      ],
    );
  }
}
