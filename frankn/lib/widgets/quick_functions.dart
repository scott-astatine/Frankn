import 'package:flutter/material.dart';
import 'package:frankn/services/rtc_thin_client.dart';
import 'package:frankn/utils/cyber_card.dart';
import 'package:frankn/utils/utils.dart';
import 'package:frankn/screens/syslog_screen.dart';
import 'package:frankn/screens/file_browser_screen.dart';
import 'package:frankn/screens/process_manager_screen.dart';
import 'package:frankn/screens/ssh_screen.dart';
import 'package:frankn/generated/l10n/app_localizations.dart';
import 'package:frankn/widgets/neural_deck_player.dart';

class QuickFunction extends StatefulWidget {
  final RtcThinClient client;
  const QuickFunction({super.key, required this.client});

  @override
  State<QuickFunction> createState() => _QuickFunctionState();
}

class _QuickFunctionState extends State<QuickFunction> {
  String _mediaStatus = "Paused";
  String _mediaMetadata = "No Media Playing";
  String _mediaArtist = "Idle";
  double _mediaPosition = 0.0;
  double _mediaLength = 1.0;
  String _playerName = "IDLE.INSTANCE";
  String? _artData;

  @override
  void initState() {
    super.initState();

    widget.client.mediaStatusStream.listen((status) {
      if (mounted) setState(() => _mediaStatus = status);
    });

    widget.client.commandResponseStream.listen((resp) {
      if (!mounted) return;
      final data = resp['type'] == 'response' ? resp['data'] : resp;
      if (data == null || data is! Map) return;

      setState(() {
        if (data.containsKey('metadata')) {
          final rawMetadata = data['metadata']?.toString() ?? "No Media";
          if (rawMetadata.contains(" - ")) {
            final parts = rawMetadata.split(" - ");
            _mediaMetadata = parts[0];
            _mediaArtist = parts.sublist(1).join(" - ");
          } else {
            _mediaMetadata = rawMetadata;
            _mediaArtist = "Unknown Artist";
          }
        }
        if (data.containsKey('player_name')) {
          _playerName =
              data['player_name']
                  ?.toString()
                  .replaceAll("org.mpris.MediaPlayer2.", "")
                  .toUpperCase() ??
              "IDLE.INSTANCE";
          if (_mediaArtist == "Unknown Artist") {
            _mediaArtist = _playerName.split('.').last;
          }
        }
        if (data.containsKey('art_data')) {
          _artData = data['art_data'];
        }
        if (data['position'] != null) {
          _mediaPosition = (data['position'] as num).toDouble();
        }
        if (data['length'] != null) {
          _mediaLength = (data['length'] as num).toDouble();
          if (_mediaLength <= 0) _mediaLength = 1.0;
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.neuralDeck.toUpperCase(),
          style: const TextStyle(
            color: Colors.white24,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 12),
        NeuralDeckPlayer(
          client: widget.client,
          mediaStatus: _mediaStatus,
          mediaMetadata: _mediaMetadata,
          mediaArtist: _mediaArtist,
          mediaPosition: _mediaPosition,
          mediaLength: _mediaLength,
          playerName: _playerName,
          artData: _artData,
        ),
        const SizedBox(height: 32),
        Text(
          l10n.systemOperations.toUpperCase(),
          style: const TextStyle(
            color: Colors.white24,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 12),
        _buildOperationsGrid(l10n),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildOperationsGrid(AppLocalizations l10n) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      childAspectRatio: 1.5,
      children: [
        _buildOpCard(
          l10n.fileBrowser,
          Icons.folder_outlined,
          AppColors.cyberYellow,
          () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => FileBrowserScreen(client: widget.client),
              ),
            );
          },
        ),
        _buildOpCard(
          l10n.terminal,
          Icons.terminal_outlined,
          AppColors.neonCyan,
          () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SShScreen(client: widget.client),
              ),
            );
          },
        ),
        _buildOpCard(l10n.processes, Icons.show_chart, AppColors.textGrey, () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ProcessManagerScreen(client: widget.client),
            ),
          );
        }),
        _buildOpCard(
          l10n.sysLog,
          Icons.article_outlined,
          AppColors.matrixGreen,
          () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SyslogScreen(client: widget.client),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildOpCard(
    String label,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: CyberCard(
          borderColor: Colors.white.withValues(alpha: 0.05),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, color: color, size: 26),
                    const SizedBox(height: 16),
                    Text(
                      label,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
