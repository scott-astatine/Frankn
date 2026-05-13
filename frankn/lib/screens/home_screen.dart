import 'package:flutter/material.dart';
import 'package:frankn/generated/l10n/app_localizations.dart';
import 'package:frankn/screens/frankn_dashboard.dart';
import 'package:frankn/screens/settings_screen.dart';
import 'package:frankn/services/rtc_thin_client.dart';
import 'package:frankn/utils/utils.dart';
import 'package:frankn/widgets/host_list_panel.dart';
import 'package:frankn/widgets/status_badge.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:frankn/widgets/system_tray_modal.dart';

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
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.appName,
            style: GoogleFonts.songMyung(
              color: AppColors.neonCyan,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
              fontSize: 18,
            ),
          ),
          if (isAuthenticated) ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8.0),
              child: Text(":", style: TextStyle(color: Colors.white24)),
            ),
            Text(
              client.currentHostName ?? "",
              style: GoogleFonts.songMyung(
                color: AppColors.textWhite,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
                fontSize: 16,
              ),
            ),
            const SizedBox(width: 12),
            StreamBuilder<SignalConnectionState>(
              stream: client.connectionStateStream,
              initialData: client.sigState,
              builder: (context, snapshot) =>
                  StatusBadge(state: snapshot.data!),
            ),
          ],
        ],
      ),
      actions: [
        if (isAuthenticated) ...[
          IconButton(
            tooltip: 'System Tray',
            icon: const Icon(
              Icons.power_settings_new,
              color: AppColors.errorRed,
              size: 20,
            ),
            onPressed: () => _showSystemTray(context, client),
          ),
        ],
        IconButton(
          tooltip: 'Settings',
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
        const SizedBox(width: 8),
      ],
    );
  }

  void _showSystemTray(BuildContext context, RtcThinClient client) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => SystemTrayModal(
        client: client,
        onDisconnect: () {
          client.disconnectFromHost();
        },
      ),
    );
  }
}
