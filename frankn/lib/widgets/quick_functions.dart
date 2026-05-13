import 'package:flutter/material.dart';
import 'package:frankn/generated/l10n/app_localizations.dart';
import 'package:frankn/screens/dohee_chat_screen.dart';
import 'package:frankn/screens/file_browser_screen.dart';
import 'package:frankn/screens/process_manager_screen.dart';
import 'package:frankn/screens/ssh_screen.dart';
import 'package:frankn/screens/syslog_screen.dart';
import 'package:frankn/screens/trackpad_screen.dart';
import 'package:frankn/services/settings_service.dart';
import 'package:frankn/services/rtc_thin_client.dart';
import 'package:frankn/utils/utils.dart';
import 'package:frankn/widgets/animated_op_btn.dart';
import 'package:frankn/widgets/dohee_chat/model_selector_dialog.dart';
import 'package:frankn/widgets/neural_deck_player.dart';

class QuickFunction extends StatefulWidget {
  final RtcThinClient client;
  const QuickFunction({super.key, required this.client});

  @override
  State<QuickFunction> createState() => _QuickFunctionState();
}

class _QuickFunctionState extends State<QuickFunction> {
  bool _mediaIsPlaying = false;
  String _mediaMetadata = "No Media Playing";
  String _mediaArtist = "Idle";
  double _mediaPosition = 0.0;
  double _mediaLength = 1.0;
  String _playerName = "IDLE.INSTANCE";
  String? _artData;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    widget.client.log("Logggggin media update from quick functions...");
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
          mediaIsPlaying: _mediaIsPlaying,
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

  @override
  void initState() {
    super.initState();
    widget.client.sendDcMsg({DcMsg.Key: DcMsg.GetMediaStatus});
    widget.client.sendDcMsg({DcMsg.Key: DcMsg.GetMediaStatus});
    widget.client.commandResponseStream.listen((resp) {
      if (!mounted) return;
      final mediamsg = resp['type'] == MediaDCMessage.MediaUpdate
          ? MediaUpdate.fromJson(resp)
          : null;
      if (mediamsg == null) return;

      setState(() {
        final rawMetadata = mediamsg.metadata;
        if (rawMetadata.contains(" - ")) {
          final parts = rawMetadata.split(" - ");
          _mediaMetadata = parts[0];
          _mediaArtist = parts.sublist(1).join(" - ");
        } else {
          _mediaMetadata = rawMetadata;
          _mediaArtist = "Unknown Artist";
        }
        _playerName = mediamsg.playerName;
        if (_mediaArtist == "Unknown Artist") {
          _mediaArtist = _playerName.split('.').last;
        }
        _artData = mediamsg.artData;
        _mediaPosition = mediamsg.position;
        _mediaLength = mediamsg.length;
        _mediaIsPlaying = mediamsg.playing;
        if (_mediaLength <= 0) _mediaLength = 1.0;
      });
    });
  }

  Widget _buildOperationsGrid(AppLocalizations l10n) {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      childAspectRatio: 1.5,
      children: [
        _opBtn(
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
        _opBtn(l10n.terminal, Icons.terminal_outlined, AppColors.neonCyan, () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => SShScreen(client: widget.client)),
          );
        }),
        _opBtn("Trackpad", Icons.mouse, AppColors.neonCyan, () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => TrackpadScreen(client: widget.client),
            ),
          );
        }),
        _opBtn("Dohee Chat", Icons.auto_awesome, AppColors.neonPink, () {
          _showNeuralChatDialog(context, widget.client);
        }),
        _opBtn(l10n.processes, Icons.show_chart, AppColors.textGrey, () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ProcessManagerScreen(client: widget.client),
            ),
          );
        }),
        _opBtn(l10n.sysLog, Icons.article_outlined, AppColors.matrixGreen, () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SyslogScreen(client: widget.client),
            ),
          );
        }),
      ],
    );
  }

  Widget _opBtn(String label, IconData icon, Color color, VoidCallback onTap) {
    return AnimatedOpBtn(label: label, icon: icon, color: color, onTap: onTap);
  }

  void _showNeuralChatDialog(BuildContext context, RtcThinClient client) {
    final defaultModel = SettingsService().llmDefaultModel;
    if (defaultModel.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(client: client, modelPath: defaultModel),
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (context) => ModelSelectorDialog(client: client),
      );
    }
  }
}
