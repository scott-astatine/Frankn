import 'package:flutter/material.dart';
import 'package:frankn/generated/l10n/app_localizations.dart';
import 'package:frankn/screens/dohee_chat_screen.dart';
import 'package:frankn/screens/file_browser_screen.dart';
import 'package:frankn/screens/process_manager_screen.dart';
import 'package:frankn/screens/ssh_screen.dart';
import 'package:frankn/screens/syslog_screen.dart';
import 'package:frankn/screens/camera_screen.dart';
import 'package:frankn/screens/trackpad_screen.dart';
import 'package:frankn/services/settings_service.dart';
import 'package:frankn/services/rtc_thin_client.dart';
import 'package:frankn/services/client_rtc/rtc.dart';
import 'package:frankn/utils/utils.dart';
import 'package:frankn/widgets/animated_op_btn.dart';
import 'package:frankn/widgets/dohee_chat/model_selector_dialog.dart';
import 'package:frankn/widgets/neural_deck_player.dart';

class QuickFunction extends StatelessWidget {
  final RtcThinClient client;
  const QuickFunction({super.key, required this.client});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.neuralDeck,
          style: const TextStyle(
            color: Colors.white24,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 12),
        NeuralDeckPlayer(client: client),
        const SizedBox(height: 32),
        Text(
          l10n.systemOperations,
          style: const TextStyle(
            color: Colors.white24,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 12),
        _buildOperationsGrid(context, l10n),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildOperationsGrid(BuildContext context, AppLocalizations l10n) {
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
          AppColors.accentWarning,
          () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => FileBrowserScreen(client: client),
              ),
            );
          },
        ),
        _opBtn(
          l10n.terminal,
          Icons.terminal_outlined,
          AppColors.accentSuccess,
          () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => SShScreen(client: client)),
            );
          },
        ),
        _opBtn(l10n.trackpad, Icons.mouse, AppColors.textSecondary, () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => TrackpadScreen(client: client)),
          );
        }),
        _opBtn(l10n.doheeChat, Icons.auto_awesome, AppColors.accentDanger, () {
          _showNeuralChatDialog(context, client);
        }),
        _opBtn(l10n.processes, Icons.show_chart, AppColors.textSecondary, () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ProcessManagerScreen(client: client),
            ),
          );
        }),
        _opBtn(l10n.sysLog, Icons.article_outlined, AppColors.accentSuccess, () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => SyslogScreen(client: client)),
          );
        }),
        _opBtn('Camera', Icons.videocam_outlined, Colors.cyanAccent, () {
          final cameraEntries = RtcClient().capabilityInventory.byCapability('camera');
          final initialProviderId = cameraEntries.firstOrNull?.provider.providerId;
          final initialNodeName = cameraEntries.firstOrNull?.provider.displayName;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CameraScreen(
                nodeName: initialNodeName,
                nodeId: initialProviderId,
                capabilityId: "camera",
              ),
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
