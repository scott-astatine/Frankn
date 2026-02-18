import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:frankn/services/rtc/rtc.dart';
import 'package:frankn/utils/utils.dart';

class SyslogScreen extends StatefulWidget {
  final RtcClient client;
  const SyslogScreen({super.key, required this.client});

  @override
  State<SyslogScreen> createState() => _SyslogScreenState();
}

class _SyslogScreenState extends State<SyslogScreen> {
  String _logContent = "Fetching logs...";
  bool _isLoading = true;
  final TextEditingController _serviceController = TextEditingController();

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _fetchLogs();

    // Listen for response
    widget.client.commandResponseStream.listen((resp) {
      if (mounted) {
        final Map<String, dynamic> data;
        if (resp['type'] == 'response' && resp.containsKey('data')) {
          data = resp['data'] as Map<String, dynamic>;
        } else {
          data = resp;
        }

        if (data.containsKey('stdout') || data.containsKey('stderr')) {
          setState(() {
            _logContent = "";
            if (data['stderr'] != null &&
                data['stderr'].toString().isNotEmpty) {
              _logContent += "=== STDERR ===\n${data['stderr']}\n\n";
            }
            if (data['stdout'] != null) {
              _logContent += "${data['stdout']}";
            }
            if (_logContent.isEmpty) {
              _logContent = "No logs found.";
            }
            _isLoading = false;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _fetchLogs() {
    setState(() {
      _isLoading = true;
      _logContent = "Fetching...";
    });
    widget.client.sendDcMsg({
      DcMsg.Key: DcMsg.SystemLog,
      "args": _serviceController.text.isEmpty ? null : _serviceController.text,
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isKeyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;

    return Scaffold(
      backgroundColor: AppColors.voidBlack,
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                _buildSearchHeader(),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                    width: double.infinity,
                    child: SingleChildScrollView(
                      child: SelectableText(
                        _logContent,
                        style: const TextStyle(
                          fontFamily: 'Courier',
                          fontWeight: FontWeight.w600,
                          color: AppColors.matrixGreen,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (!isKeyboardVisible)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildTinyStatusBar(),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppColors.panelGrey.withValues(alpha: 0.3),
      child: TextField(
        controller: _serviceController,
        style: const TextStyle(
          color: AppColors.neonCyan,
          fontFamily: 'Courier',
          fontSize: 13,
          fontWeight: FontWeight.bold,
        ),
        decoration: InputDecoration(
          hintText: "SERVICE (e.g. sshd) or EMPTY",
          hintStyle: TextStyle(
            color: AppColors.textGrey.withValues(alpha: 0.5),
            fontSize: 12,
          ),
          prefixIcon: const Icon(
            Icons.search,
            color: AppColors.neonCyan,
            size: 18,
          ),
          isDense: true,
          border: InputBorder.none,
        ),
        onSubmitted: (_) => _fetchLogs(),
      ),
    );
  }

  Widget _buildTinyStatusBar() {
    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: AppColors.deepSpace.withValues(alpha: 0.9),
        border: const Border(
          top: BorderSide(color: AppColors.neonCyan, width: 0.5),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const Icon(
              Icons.chevron_left,
              color: AppColors.neonCyan,
              size: 18,
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            "SYSTEM_LOG",
            style: TextStyle(
              color: AppColors.textGrey,
              fontSize: 10,
              fontFamily: 'Courier',
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          const Spacer(),
          if (_isLoading)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.neonCyan,
              ),
            )
          else
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: const Icon(
                Icons.refresh,
                color: AppColors.neonCyan,
                size: 16,
              ),
              onPressed: _fetchLogs,
            ),
        ],
      ),
    );
  }
}
