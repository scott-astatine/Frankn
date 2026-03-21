import 'dart:async';
import 'package:flutter/material.dart';
import 'package:frankn/services/rtc/rtc.dart' as rtc;
import 'package:frankn/services/settings_service.dart';
import 'package:frankn/utils/utils.dart';
import 'package:frankn/utils/cyber_card.dart';
import 'package:frankn/utils/cyber_button.dart';
import 'package:frankn/widgets/pairing_dialog.dart';
import 'package:frankn/generated/l10n/app_localizations.dart';

class HostListPanel extends StatefulWidget {
  final rtc.RtcClient client;
  const HostListPanel({super.key, required this.client});

  @override
  State<HostListPanel> createState() => _HostListPanelState();
}

class _HostListPanelState extends State<HostListPanel> {
  StreamSubscription? _peerSub;
  StreamSubscription? _hostSub;

  @override
  void initState() {
    super.initState();
    _peerSub = widget.client.peerStatusStream.listen((_) {
      if (mounted) setState(() {});
    });
    _hostSub = widget.client.hostListStream.listen((_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.client.requestHostList();
    });
  }

  @override
  void dispose() {
    _peerSub?.cancel();
    _hostSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final savedHosts = SettingsService().savedHosts;
    final l10n = AppLocalizations.of(context)!;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(l10n.neuralLinks.toUpperCase(), Icons.link),
          const SizedBox(height: 16),
          if (savedHosts.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(l10n.noPersistentLinks.toUpperCase(), 
                  style: const TextStyle(color: Colors.white10, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
              ),
            )
          else
            ...savedHosts.map((h) => _buildHostCard(
                  context,
                  h['id']!,
                  h['name']!,
                  isSaved: true,
                  isOnline: widget.client.onlineHostIds.contains(h['id']),
                )),
          const SizedBox(height: 32),
          _buildSectionHeader(l10n.publicDiscovery.toUpperCase(), Icons.radar),
          const SizedBox(height: 16),
          _buildDiscoveryContent(savedHosts, l10n),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Colors.white24, size: 14),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(color: Colors.white24, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
      ],
    );
  }

  Widget _buildDiscoveryContent(List<Map<String, String>> savedHosts, AppLocalizations l10n) {
    final hosts = widget.client.currentHosts;
    final filteredHosts = hosts.where((h) => !savedHosts.any((s) => s['id'] == h['host_id'])).toList();

    return Column(
      children: [
        if (filteredHosts.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Text(l10n.noAdditionalTargets.toUpperCase(), 
                style: const TextStyle(color: Colors.white10, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2)),
            ),
          )
        else
          ...filteredHosts.map((h) => _buildHostCard(
            context, 
            h['host_id'], 
            h['display_name'],
            isOnline: true,
          )),
        const SizedBox(height: 24),
        Center(
          child: CyberButton(
            text: "+ ${l10n.addManualTarget.toUpperCase()}",
            isSmall: true,
            onPressed: () async {
              final result = await showDialog(
                context: context,
                builder: (context) => const PairingDialog(),
              );
              if (result == true) setState(() {});
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHostCard(BuildContext context, String id, String name, {bool isSaved = false, bool isOnline = false}) {
    final Color accentColor = isSaved ? AppColors.neonPink : AppColors.neonCyan;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: CyberCard(
        borderColor: isOnline ? accentColor.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Container(
                width: 4,
                height: 60,
                decoration: BoxDecoration(
                  color: isOnline ? accentColor : Colors.white10,
                  borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), bottomLeft: Radius.circular(16)),
                ),
              ),
              const SizedBox(width: 16),
              Icon(Icons.monitor_outlined, color: isOnline ? accentColor : Colors.white10, size: 28),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name.toUpperCase(), 
                      style: TextStyle(color: isOnline ? Colors.white : Colors.white24, fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 1)),
                    Text("ID: $id", 
                      style: const TextStyle(color: Colors.white10, fontSize: 9, fontFamily: 'JetBrainsMonoNerdFont', fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              if (isOnline)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: CyberButton(
                    text: "LINK",
                    isSmall: true,
                    onPressed: () => _showPasswordDialog(context, id, name),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: IconButton(
                    icon: const Icon(Icons.link_off, color: Colors.white10, size: 20),
                    onPressed: isSaved ? () async {
                      await SettingsService().forgetHost(id);
                      setState(() {});
                    } : null,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPasswordDialog(BuildContext context, String hostId, String hostName) {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0F0F0F),
        shape: const BeveledRectangleBorder(side: BorderSide(color: AppColors.neonCyan)),
        title: Text(l10n.uplinkSecurity.toUpperCase(), style: const TextStyle(color: AppColors.neonCyan, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 2)),
        content: TextField(
          controller: controller,
          obscureText: true,
          style: const TextStyle(color: Colors.white),
          onSubmitted: (_) {
            Navigator.pop(context);
            widget.client.connectToHost(hostId, password: controller.text, hostName: hostName);
          },
          decoration: InputDecoration(
            hintText: l10n.enterPasscode.toUpperCase(),
            hintStyle: const TextStyle(color: AppColors.textGrey, fontSize: 12),
            enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.neonCyan)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel.toUpperCase(), style: const TextStyle(color: AppColors.textGrey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.neonCyan, foregroundColor: Colors.black),
            onPressed: () {
              Navigator.pop(context);
              widget.client.connectToHost(hostId, password: controller.text, hostName: hostName);
            },
            child: Text(l10n.establish.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}