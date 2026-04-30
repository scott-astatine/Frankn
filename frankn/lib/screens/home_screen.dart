import 'package:flutter/material.dart';
import 'package:frankn/services/settings_service.dart';
import 'package:frankn/screens/dohee_chat_screen.dart';
import 'package:frankn/generated/l10n/app_localizations.dart';
import 'package:frankn/screens/frankn_dashboard.dart';
import 'package:frankn/widgets/dohee_chat/model_selector_dialog.dart';
import 'package:frankn/screens/settings_screen.dart';
import 'package:frankn/services/rtc_thin_client.dart';
import 'package:frankn/utils/cyber_button.dart';
import 'package:frankn/utils/cyber_card.dart';
import 'package:frankn/utils/utils.dart';
import 'package:frankn/widgets/host_list_panel.dart';
import 'package:frankn/widgets/status_badge.dart';
import 'package:google_fonts/google_fonts.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final client = RtcThinClient();

    return StreamBuilder<HostConnectionState>(
      stream: client.hostStateStream,
      initialData: client.currentHostState,
      builder: (context, snapshot) {
        final isAuthenticated =
            snapshot.data == HostConnectionState.authenticated;

        return Scaffold(
          backgroundColor: AppColors.voidBlack,
          appBar: _buildAppBar(context, client, isAuthenticated),
          body: isAuthenticated
              ? FranknDashboard(client: client)
              : HostListPanel(client: client),
        );
      },
    );
  }

  void _showNeuralChatDialog(BuildContext context, RtcThinClient client) {
    final defaultModel = SettingsService().llmDefaultModel;
    if (defaultModel.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            client: client,
            modelPath: defaultModel,
          ),
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (context) => ModelSelectorDialog(client: client),
      );
    }
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    RtcThinClient client,
    bool isAuthenticated,
  ) {
    final l10n = AppLocalizations.of(context)!;
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      title: Row(
        children: [
          isAuthenticated
              ? IconButton(
                  onPressed: () => _showNeuralChatDialog(context, client),
                  icon: Icon(Icons.auto_awesome),
                )
              : SizedBox(),
          Text(
            l10n.appName,
            style: GoogleFonts.songMyung(
              color: AppColors.neonCyan,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
              fontSize: 16,
            ),
          ),
          const Text(":", style: TextStyle(color: Colors.white24)),
          if (isAuthenticated) ...[
            Text(
              client.currentHostName ?? "",
              style: GoogleFonts.songMyung(
                color: AppColors.textWhite,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
                fontSize: 14,
              ),
            ),
          ],
        ],
      ),
      actions: [
        if (isAuthenticated) ...[
          IconButton(
            icon: const Icon(
              Icons.power_settings_new,
              color: AppColors.errorRed,
              size: 22,
            ),
            onPressed: () => _showAdminOverride(context, client),
          ),
          IconButton(
            icon: const Icon(
              Icons.settings_outlined,
              color: AppColors.textGrey,
              size: 20,
            ),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
          StreamBuilder<SignalConnectionState>(
            stream: client.connectionStateStream,
            initialData: client.sigState,
            builder: (context, snapshot) => Padding(
              padding: const EdgeInsets.only(right: 16, left: 8),
              child: Center(child: StatusBadge(state: snapshot.data!)),
            ),
          ),
        ] else
          IconButton(
            icon: const Icon(
              Icons.settings_outlined,
              color: AppColors.textGrey,
              size: 20,
            ),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
      ],
    );
  }

  Widget _buildGridButton(
    IconData? icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: CyberCard(
            borderColor: color.withValues(alpha: 0.2),
            child: Container(
              height: 100,
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) Icon(icon, color: color, size: 24),
                  if (icon != null) const SizedBox(height: 12),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: color == AppColors.textGrey
                          ? Colors.white70
                          : color,
                      fontWeight: FontWeight.w900,
                      fontSize: 10,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white24,
        fontSize: 10,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.5,
      ),
    );
  }

  void _confirmDestructiveAction(
    BuildContext context,
    RtcThinClient client,
    String title,
    String cmd,
    Map<String, dynamic>? args,
  ) {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0F0F0F),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.errorRed),
        ),
        title: Text(
          "${l10n.criticalIntent.toUpperCase()} // ${title.toUpperCase()}",
          style: const TextStyle(
            color: AppColors.errorRed,
            fontSize: 14,
            fontWeight: FontWeight.w900,
          ),
        ),
        content: Text(
          l10n.executeRemoteCommand(title),
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              l10n.abort.toUpperCase(),
              style: const TextStyle(color: AppColors.textGrey),
            ),
          ),
          CyberButton(
            text: l10n.confirm.toUpperCase(),
            variant: CyberButtonVariant.destructive,
            isSmall: true,
            onPressed: () {
              Navigator.pop(context); // Dialog
              Navigator.pop(context); // BottomSheet
              client.sendDcMsg({DcMsg.Key: cmd, ...?args});
            },
          ),
        ],
      ),
    );
  }

  void _showAdminOverride(BuildContext context, RtcThinClient client) {
    final l10n = AppLocalizations.of(context)!;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
        decoration: const BoxDecoration(
          color: Color(0xFF0F0F0F),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(32),
            topRight: Radius.circular(32),
          ),
          border: Border(
            top: BorderSide(color: AppColors.errorRed, width: 1.5),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.gpp_maybe_outlined,
                      color: AppColors.errorRed,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      l10n.adminOverride.toUpperCase(),
                      style: const TextStyle(
                        color: AppColors.errorRed,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white38),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 32),
            _buildSectionLabel(l10n.serviceManagement.toUpperCase()),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildGridButton(
                  Icons.sync,
                  l10n.restartSvc.toUpperCase(),
                  AppColors.cyberYellow,
                  () => client.sendDcMsg({DcMsg.Key: DcMsg.RestartHostServer}),
                ),
                const SizedBox(width: 16),
                _buildGridButton(
                  Icons.cloud_download_outlined,
                  l10n.sysUpdate.toUpperCase(),
                  AppColors.cyberYellow,
                  () => client.sendDcMsg({DcMsg.Key: DcMsg.Update}),
                ),
              ],
            ),
            const SizedBox(height: 32),
            _buildSectionLabel(l10n.powerState.toUpperCase()),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildGridButton(
                  Icons.lock_outline,
                  l10n.lockHost.toUpperCase(),
                  AppColors.neonCyan,
                  () => client.sendDcMsg({DcMsg.Key: DcMsg.LockScreen}),
                ),
                const SizedBox(width: 16),
                _buildGridButton(
                  Icons.lock_open,
                  l10n.unlockHost.toUpperCase(),
                  AppColors.neonCyan,
                  () => client.sendDcMsg({DcMsg.Key: DcMsg.UnlockScreen}),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _buildGridButton(
                  Icons.restart_alt,
                  l10n.reboot.toUpperCase(),
                  AppColors.textGrey,
                  () => _confirmDestructiveAction(
                    context,
                    client,
                    l10n.reboot,
                    DcMsg.Reboot,
                    null,
                  ),
                ),
                const SizedBox(width: 16),
                _buildGridButton(
                  Icons.power_settings_new,
                  l10n.shutdown.toUpperCase(),
                  AppColors.errorRed,
                  () => _confirmDestructiveAction(
                    context,
                    client,
                    l10n.shutdown,
                    DcMsg.Shutdown,
                    {"args": "now"},
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildGridButton(
                  Icons.link_off,
                  l10n.disconnectLink.toUpperCase(),
                  AppColors.neonPink,
                  () {
                    client.sendDcMsg({DcMsg.Key: DcMsg.Disconnect});
                    client.disconnectFromHost();
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
