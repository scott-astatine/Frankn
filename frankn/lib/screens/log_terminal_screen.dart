import 'package:flutter/material.dart';
import 'package:frankn/services/rtc/rtc.dart';
import 'package:frankn/utils/utils.dart';
import 'package:frankn/generated/l10n/app_localizations.dart';

class LogTerminalScreen extends StatefulWidget {
  final RtcClient client;
  const LogTerminalScreen({super.key, required this.client});

  @override
  State<LogTerminalScreen> createState() => _LogTerminalScreenState();
}

class _LogTerminalScreenState extends State<LogTerminalScreen> {
  late final List<String> _logs;

  @override
  void initState() {
    super.initState();
    // Initialize with full history
    _logs = List.from(widget.client.logHistory);
    
    widget.client.logStream.listen((log) {
      if (mounted) {
        setState(() {
          _logs.insert(0, log);
          if (_logs.length > 1000) _logs.removeLast();
        });
      }
    });
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
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: ListView.builder(
                  itemCount: _logs.length,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("> ", style: TextStyle(color: AppColors.neonCyan, fontFamily: 'JetBrainsMonoNerdFont', fontSize: 12, fontWeight: FontWeight.bold)),
                          Expanded(
                            child: Text(
                              _logs[index],
                              style: const TextStyle(
                                fontFamily: 'JetBrainsMonoNerdFont',
                                color: AppColors.matrixGreen,
                                fontSize: 12,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.neonCyan),
            onPressed: () => Navigator.pop(context),
          ),
          Text(
            l10n.liveLog.toUpperCase(),
            style: const TextStyle(
              color: AppColors.neonCyan,
              fontWeight: FontWeight.w900,
              fontSize: 16,
              letterSpacing: 2,
            ),
          ),
          const Spacer(),
          const Padding(
            padding: EdgeInsets.only(right: 16),
            child: Icon(Icons.terminal, color: Colors.white10, size: 20),
          ),
        ],
      ),
    );
  }
}
