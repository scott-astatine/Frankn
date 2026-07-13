import 'dart:async';
import 'package:flutter/material.dart';
import 'package:frankn/services/rtc_thin_client.dart';
import 'package:frankn/services/settings_service.dart';
import 'package:frankn/utils/utils.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:frankn/generated/l10n/app_localizations.dart';
import 'package:frankn/utils/dc_msg_util.dart';
import 'package:frankn/widgets/glassy_header.dart';

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
  final String _activeSince = "-5m";
  final int _activeLines = 200;
  Timer? _pollTimer;
  final TextEditingController _serviceController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchLogs();

    widget.client.genDcMsgStream.listen((msg) {
      if (!mounted) return;

      Map<String, dynamic>? data;
      if (msg is HostMsgResponse && msg.data is Map) {
        data = msg.data as Map<String, dynamic>;
      } else if (msg is HostMsgUnknown) {
        data = msg.raw;
      }

      if (data != null &&
          (data.containsKey('stdout') || data.containsKey('stderr'))) {
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
    widget.client.sendDcMsg(
      DcMsgSystemLog(
        unit: _activeUnit,
        priority: _activePriority,
        grep: _searchKeyword,
        since: _activeSince,
        lines: _activeLines,
      ),
    );
  }

  TextSpan _parseLogContent(String rawContent) {
    final lines = rawContent.split('\n');
    final List<TextSpan> spans = [];

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      Color color = AppColors.textPrimary;

      final lower = line.toLowerCase();
      if (lower.contains('err') ||
          lower.contains('fail') ||
          lower.contains('crit') ||
          lower.contains('emerg') ||
          lower.contains('alert') ||
          lower.contains('fatal')) {
        color = AppColors.accentError;
      } else if (lower.contains('warn')) {
        color = AppColors.accentWarning;
      } else if (lower.contains('info') || lower.contains('success')) {
        color = AppColors.textPrimary;
      } else if (lower.contains('debug')) {
        color = AppColors.textSecondary;
      }

      spans.add(
        TextSpan(
          text: "$line\n",
          style: TextStyle(color: color),
        ),
      );
    }

    return TextSpan(
      children: spans,
      style: const TextStyle(fontFamily: 'JetBrainsMonoNerdFont'),
    );
  }



  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: NestedScrollView(
        headerSliverBuilder: (BuildContext context, bool innerBoxIsScrolled) {
          return <Widget>[
            SliverAppBar(
              floating: true,
              snap: true,
              pinned: false,
              primary: false,
              backgroundColor: Colors.transparent,
              elevation: 0,
              automaticallyImplyLeading: false,
              titleSpacing: 0,
              toolbarHeight: 64,
              title: GlassyHeader(
                innerBoxIsScrolled: innerBoxIsScrolled,
                child: _buildHeader(l10n),
              ),
            ),
          ];
        },
        body: Builder(
          builder: (context) {
            return Column(
              children: [
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
            );
          },
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
            icon: const Icon(Icons.arrow_back, color: AppColors.accentPrimary),
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
                l10n.sysLog,
                style: GoogleFonts.nanumMyeongjo(
                  color: AppColors.accentPrimary,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
            ),
          IconButton(
            icon: Icon(
              _isSearching ? Icons.close : Icons.search,
              color: AppColors.accentPrimary,
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
              color: AppColors.accentPrimary,
              size: 20,
            ),
            onPressed: _fetchLogs,
          ),
        ],
      ),
    );
  }


}
