import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:frankn/services/rtc_thin_client.dart';
import 'package:frankn/services/settings_service.dart';
import 'package:frankn/utils/utils.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:frankn/generated/l10n/app_localizations.dart';
import 'package:frankn/utils/dc_msg_util.dart';

class SyslogScreen extends StatefulWidget {
  final RtcThinClient client;
  const SyslogScreen({super.key, required this.client});

  @override
  State<SyslogScreen> createState() => _SyslogScreenState();
}

class _SyslogScreenState extends State<SyslogScreen> {
  String _logContent = "Fetching...";
  bool _isSearching = false;
  String? _activePriority;
  String? _activeUnit;
  String? _searchKeyword;
  String _activeSince = "-5m";
  int _activeLines = 200;
  bool _isLive = false;
  Timer? _pollTimer;
  final TextEditingController _serviceController = TextEditingController();

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _fetchLogs();

    widget.client.genDcMsgStream.listen((msg) {
      if (!mounted) return;
      
      Map<String, dynamic>? data;
      if (msg is HostMsgResponse && msg.data is Map) {
          data = msg.data as Map<String, dynamic>;
      } else if (msg is HostMsgUnknown) {
          data = msg.raw;
      }

      if (data != null && (data.containsKey('stdout') || data.containsKey('stderr'))) {
        setState(() {
          _logContent = "";
          if (data!['stderr'] != null && data['stderr'].toString().isNotEmpty) {
            _logContent += "=== STDERR ===\n${data['stderr']}\n\n";
          }
          if (data['stdout'] != null) {
            _logContent += "${data['stdout']}";
          }
          if (_logContent.isEmpty) {
            _logContent = "No logs found.";
          }
        });
      }
    });
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _serviceController.dispose();
    _pollTimer?.cancel();
    super.dispose();
  }

  void _fetchLogs({bool isPoll = false}) {
    if (!mounted) return;
    if (!isPoll) {
      setState(() {
        _logContent = "Fetching...";
      });
    }
    widget.client.sendDcMsg(DcMsgSystemLog(
      unit: _activeUnit,
      priority: _activePriority,
      grep: _searchKeyword,
      since: _activeSince,
      lines: _activeLines,
    ));
  }

  TextSpan _parseLogContent(String rawContent) {
    final lines = rawContent.split('\n');
    final List<TextSpan> spans = [];

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      Color color = AppColors.textWhite;
      
      final lower = line.toLowerCase();
      if (lower.contains('err') ||
          lower.contains('fail') ||
          lower.contains('crit') ||
          lower.contains('emerg') ||
          lower.contains('exception') ||
          lower.contains('fatal') ||
          lower.contains('stderr')) {
        color = AppColors.errorRed;
      } else if (lower.contains('warn') || lower.contains('attention')) {
        color = AppColors.cyberYellow;
      } else if (lower.contains('debug') || lower.contains('dbg') || lower.contains('trace')) {
        color = AppColors.textGrey;
      } else if (lower.contains('info') || lower.contains('stdout') || lower.contains('success')) {
        color = AppColors.neonCyan;
      }

      spans.add(TextSpan(
        text: "$line\n",
        style: TextStyle(color: color),
      ));
    }

    return TextSpan(children: spans);
  }

  void _copyLogsToClipboard() {
    Clipboard.setData(ClipboardData(text: _logContent));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.voidBlack,
        content: const Text(
          "LOGS COPIED TO CLI-CLIPBOARD",
          style: TextStyle(
            fontFamily: 'JetBrainsMonoNerdFont',
            color: AppColors.neonCyan,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: AppColors.neonCyan, width: 1.5),
          borderRadius: BorderRadius.circular(4),
        ),
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
            _buildPriorityChips(),
            _buildServiceChips(),
            _buildControlsDock(),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: SingleChildScrollView(
                  child: SelectableText.rich(
                    _parseLogContent(_logContent),
                    style: TextStyle(
                      fontFamily: 'JetBrainsMonoNerdFont',
                      fontWeight: FontWeight.w600,
                      fontSize: SettingsService().terminalFontSize,
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

  Widget _buildServiceChips() {
    final services = {
      null: 'ALL SERVICES',
      'frankn-host': 'FRANKN-HOST',
      'sshd': 'SSH',
      'NetworkManager': 'NETWORK',
      'docker': 'DOCKER',
      'systemd': 'SYSTEMD',
    };

    return Container(
      height: 32,
      margin: const EdgeInsets.only(bottom: 8, left: 16, right: 16),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: services.entries.map((entry) {
          final isSelected = _activeUnit == entry.key;
          final color = isSelected ? AppColors.neonPink : Colors.white24;
          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: InkWell(
              onTap: () {
                setState(() {
                  _activeUnit = entry.key;
                });
                _fetchLogs();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  border: Border.all(color: color, width: 1.5),
                  color: isSelected ? AppColors.neonPink.withValues(alpha: 0.1) : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Center(
                  child: Text(
                    entry.value,
                    style: TextStyle(
                      fontFamily: 'JetBrainsMonoNerdFont',
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? AppColors.neonPink : AppColors.textGrey,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPriorityChips() {
    final priorities = {
      null: 'ALL',
      'err': 'ERROR',
      'warning': 'WARN',
      'info': 'INFO',
      'debug': 'DEBUG',
    };

    return Container(
      height: 32,
      margin: const EdgeInsets.only(bottom: 8, left: 16, right: 16),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: priorities.entries.map((entry) {
          final isSelected = _activePriority == entry.key;
          final color = isSelected ? AppColors.neonCyan : Colors.white24;
          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: InkWell(
              onTap: () {
                setState(() {
                  _activePriority = entry.key;
                });
                _fetchLogs();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  border: Border.all(color: color, width: 1.5),
                  color: isSelected ? AppColors.neonCyan.withValues(alpha: 0.1) : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Center(
                  child: Text(
                    entry.value,
                    style: TextStyle(
                      fontFamily: 'JetBrainsMonoNerdFont',
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? AppColors.neonCyan : AppColors.textGrey,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
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
                controller: _serviceController,
                autofocus: true,
                onSubmitted: (val) {
                  setState(() {
                    _isSearching = false;
                    _searchKeyword = val.trim().isEmpty ? null : val.trim();
                  });
                  _fetchLogs();
                },
                style: TextStyle(
                  color: Colors.white,
                  fontSize: SettingsService().terminalFontSize,
                  fontFamily: 'JetBrainsMonoNerdFont',
                ),
                decoration: const InputDecoration(
                  hintText: "SEARCH KEYWORD (e.g. failed) or EMPTY",
                  hintStyle: TextStyle(color: Colors.white24, fontSize: 12),
                  border: InputBorder.none,
                ),
              ),
            )
          else
            Expanded(
              child: Text(
                l10n.sysLog.toUpperCase(),
                style: GoogleFonts.nanumMyeongjo(
                  color: AppColors.neonCyan,
                  fontWeight: FontWeight.w900,
                  fontSize: 22,
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
                _serviceController.clear();
                _searchKeyword = null;
                _fetchLogs();
              }
            }),
          ),
          IconButton(
            icon: const Icon(
              Icons.refresh,
              color: AppColors.neonCyan,
              size: 20,
            ),
            onPressed: _fetchLogs,
          ),
        ],
      ),
    );
  }

  Widget _buildControlsDock() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      margin: const EdgeInsets.only(bottom: 8, left: 16, right: 16),
      decoration: BoxDecoration(
        color: AppColors.voidBlack,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: AppColors.neonCyan.withValues(alpha: 0.15),
          width: 1,
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // Timeframe Label & Options
            const Text(
              "TIME: ",
              style: TextStyle(
                fontFamily: 'JetBrainsMonoNerdFont',
                color: Colors.white30,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 4),
            _buildMiniChip(
              label: "5M",
              isSelected: _activeSince == "-5m",
              onTap: () => setState(() {
                _activeSince = "-5m";
                _fetchLogs();
              }),
            ),
            _buildMiniChip(
              label: "1H",
              isSelected: _activeSince == "-1h",
              onTap: () => setState(() {
                _activeSince = "-1h";
                _fetchLogs();
              }),
            ),
            _buildMiniChip(
              label: "1D",
              isSelected: _activeSince == "-1d",
              onTap: () => setState(() {
                _activeSince = "-1d";
                _fetchLogs();
              }),
            ),
            const SizedBox(width: 12),
            // Lines Label & Options
            const Text(
              "LIMIT: ",
              style: TextStyle(
                fontFamily: 'JetBrainsMonoNerdFont',
                color: Colors.white30,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 4),
            _buildMiniChip(
              label: "50",
              isSelected: _activeLines == 50,
              onTap: () => setState(() {
                _activeLines = 50;
                _fetchLogs();
              }),
            ),
            _buildMiniChip(
              label: "200",
              isSelected: _activeLines == 200,
              onTap: () => setState(() {
                _activeLines = 200;
                _fetchLogs();
              }),
            ),
            _buildMiniChip(
              label: "500",
              isSelected: _activeLines == 500,
              onTap: () => setState(() {
                _activeLines = 500;
                _fetchLogs();
              }),
            ),
            const SizedBox(width: 16),
            // Live toggle
            _buildLiveToggle(),
            const SizedBox(width: 16),
            // Copy Action
            InkWell(
              onTap: _copyLogsToClipboard,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.copy_all_rounded, color: AppColors.neonCyan, size: 14),
                  SizedBox(width: 4),
                  Text(
                    "COPY",
                    style: TextStyle(
                      fontFamily: 'JetBrainsMonoNerdFont',
                      fontSize: 9,
                      color: AppColors.neonCyan,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 6.0),
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(
              color: isSelected ? AppColors.neonCyan.withValues(alpha: 0.5) : Colors.transparent,
              width: 1,
            ),
            color: isSelected ? AppColors.neonCyan.withValues(alpha: 0.05) : Colors.transparent,
            borderRadius: BorderRadius.circular(2),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'JetBrainsMonoNerdFont',
              fontSize: 9,
              color: isSelected ? AppColors.neonCyan : Colors.white38,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLiveToggle() {
    return InkWell(
      onTap: () {
        setState(() {
          _isLive = !_isLive;
          if (_isLive) {
            _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
              _fetchLogs(isPoll: true);
            });
          } else {
            _pollTimer?.cancel();
            _pollTimer = null;
          }
        });
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _isLive ? AppColors.errorRed : Colors.white24,
              boxShadow: _isLive
                  ? [
                      BoxShadow(
                        color: AppColors.errorRed.withValues(alpha: 0.5),
                        blurRadius: 4,
                        spreadRadius: 1,
                      )
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            "LIVE TAIL",
            style: TextStyle(
              fontFamily: 'JetBrainsMonoNerdFont',
              fontSize: 9,
              color: _isLive ? AppColors.errorRed : Colors.white38,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
