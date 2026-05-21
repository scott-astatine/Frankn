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
    super.dispose();
  }

  void _fetchLogs() {
    setState(() {
      _logContent = "Fetching...";
    });
    widget.client.sendDcMsg(DcMsgSystemLog(
      args: _serviceController.text.isEmpty ? null : _serviceController.text,
    ));
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
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    _logContent,
                    style: TextStyle(
                      fontFamily: 'JetBrainsMonoNerdFont',
                      fontWeight: FontWeight.w600,
                      color: AppColors.matrixGreen,
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
                onSubmitted: (_) {
                  setState(() => _isSearching = false);
                  _fetchLogs();
                },
                style: TextStyle(
                  color: Colors.white,
                  fontSize: SettingsService().terminalFontSize,
                  fontFamily: 'JetBrainsMonoNerdFont',
                ),
                decoration: const InputDecoration(
                  hintText: "SERVICE (e.g. sshd) or EMPTY",
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
}
