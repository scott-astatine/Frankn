import 'package:flutter/material.dart';
import 'package:frankn/services/rtc_thin_client.dart';
import 'package:frankn/services/settings_service.dart';
import 'package:frankn/utils/utils.dart';
import 'package:frankn/generated/l10n/app_localizations.dart';
import 'package:frankn/widgets/glassy_header.dart';

class LogTerminalScreen extends StatefulWidget {
  final RtcThinClient client;
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
          if (_logs.length > 5000) _logs.removeLast();
        });
      }
    });
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
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: ListView.builder(
                      itemCount: _logs.length,
                      itemBuilder: (context, index) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "> ",
                                style: TextStyle(
                                  color: AppColors.accentPrimary,
                                  fontFamily: 'JetBrainsMonoNerdFont',
                                  fontSize: SettingsService().terminalFontSize,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  _logs.reversed.toList()[index],
                                  style: TextStyle(
                                    fontFamily: 'JetBrainsMonoNerdFont',
                                    color: AppColors.accentSuccess,
                                    fontSize:
                                        SettingsService().terminalFontSize,
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
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(AppLocalizations l10n) {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.accentPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        Text(
          l10n.liveLog.toUpperCase(),
          style: const TextStyle(
            color: AppColors.accentPrimary,
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
    );
  }
}
