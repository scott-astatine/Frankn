import 'package:flutter/material.dart';
import 'package:frankn/services/rtc/rtc.dart';
import 'package:frankn/utils/utils.dart';
import 'package:frankn/widgets/log_terminal.dart';

class LogTerminalScreen extends StatefulWidget {
  final RtcClient client;
  final List<String> initialLogs;

  const LogTerminalScreen({
    super.key,
    required this.client,
    required this.initialLogs,
  });

  @override
  State<LogTerminalScreen> createState() => _LogTerminalScreenState();
}

class _LogTerminalScreenState extends State<LogTerminalScreen> {
  late List<String> _logs;

  @override
  void initState() {
    super.initState();
    _logs = List.from(widget.initialLogs);
    widget.client.logStream.listen((log) {
      if (mounted) {
        setState(() {
          _logs.insert(0, "> $log");
          if (_logs.length > 500) {
            _logs.removeLast();
          }
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.voidBlack,
      appBar: AppBar(
        title: const Text("LOGS"),
        backgroundColor: AppColors.voidBlack,
        iconTheme: const IconThemeData(color: AppColors.neonCyan),
      ),
      body: LogTerminal(
        logs: _logs,
        onToggleExpand: () => Navigator.pop(context), // Close fullscreen
        onMinimize: () => Navigator.pop(context),
        onFullscreen: () {}, // Already fullscreen
        isExpanded: true,
      ),
    );
  }
}
