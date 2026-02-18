import 'package:flutter/material.dart';
import 'package:frankn/services/rtc/rtc.dart' as rtc;
import 'package:frankn/services/settings_service.dart';
import 'package:frankn/utils/utils.dart';
import 'package:frankn/widgets/pairing_dialog.dart';

class HostListPanel extends StatefulWidget {
  final rtc.RtcClient client;
  const HostListPanel({super.key, required this.client});

  @override
  State<HostListPanel> createState() => _HostListPanelState();
}

class _HostListPanelState extends State<HostListPanel> {
  @override
  Widget build(BuildContext context) {
    final savedHosts = SettingsService().savedHosts;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(
          "NEURAL LINKS",
          Icons.link,
          onAction: _showPairingDialog,
          actionIcon: Icons.add_link,
        ),
        if (savedHosts.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              "NO PERSISTENT LINKS FOUND",
              style: TextStyle(color: AppColors.textGrey, fontSize: 9, letterSpacing: 1),
            ),
          )
        else
          ...savedHosts.map((h) => _buildHostCard(
                context,
                h['id']!,
                h['name']!,
                isSaved: true,
              )),
        const SizedBox(height: 16),
        _buildHeader(
          "PUBLIC DISCOVERY",
          Icons.radar,
          onAction: () => widget.client.requestHostList(),
          actionIcon: Icons.refresh,
        ),
        Expanded(
          child: StreamBuilder<List<dynamic>>(
            stream: widget.client.hostListStream,
            initialData: widget.client.currentHosts,
            builder: (context, snapshot) {
              final hosts = snapshot.data!;
              // Filter out hosts that are already in our saved list to avoid redundancy
              final filteredHosts = hosts.where((h) => !savedHosts.any((s) => s['id'] == h['host_id'])).toList();

              return RefreshIndicator(
                color: AppColors.neonCyan,
                backgroundColor: AppColors.panelGrey,
                onRefresh: () async {
                  widget.client.requestHostList();
                  await Future.delayed(const Duration(milliseconds: 500));
                },
                child: filteredHosts.isEmpty && savedHosts.isNotEmpty
                    ? const Center(
                        child: Text(
                          "NO ADDITIONAL TARGETS",
                          style: TextStyle(color: AppColors.textGrey, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      )
                    : (filteredHosts.isEmpty && savedHosts.isEmpty)
                        ? _buildEmptyState()
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            itemCount: filteredHosts.length,
                            itemBuilder: (context, index) {
                              final host = Map.castFrom(filteredHosts[index]);
                              final id = host['host_id'] ?? "Unknown ID";
                              final name = host['display_name'] ?? "Unknown Host";
                              return _buildHostCard(context, id, name);
                            },
                          ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(String title, IconData icon, {VoidCallback? onAction, IconData? actionIcon}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Icon(icon, color: AppColors.neonCyan, size: 16),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              color: AppColors.neonCyan.withValues(alpha: 0.7),
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          const Spacer(),
          if (onAction != null)
            IconButton(
              icon: Icon(actionIcon ?? Icons.add, color: AppColors.neonCyan, size: 18),
              onPressed: onAction,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
        ],
      ),
    );
  }

  void _showPairingDialog() async {
    final result = await showDialog(
      context: context,
      builder: (context) => const PairingDialog(),
    );
    if (result == true) {
      setState(() {});
    }
  }

  Widget _buildEmptyState() {
    return ListView(
      children: [
        const SizedBox(height: 100),
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.language, color: AppColors.textGrey, size: 48),
              const SizedBox(height: 16),
              Text(
                "NO TARGETS DETECTED",
                style: TextStyle(
                  color: AppColors.textGrey.withValues(alpha: 0.5),
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "PULL DOWN TO RE-SCAN",
                style: TextStyle(
                  color: AppColors.neonCyan,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHostCard(BuildContext context, String id, String name, {bool isSaved = false}) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      decoration: BoxDecoration(
        color: AppColors.panelGrey.withValues(alpha: 0.4),
        border: Border.all(
          color: isSaved ? AppColors.neonPink.withValues(alpha: 0.3) : AppColors.neonCyan.withValues(alpha: 0.2),
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        dense: true,
        leading: Icon(
          Icons.computer,
          color: isSaved ? AppColors.neonPink : AppColors.neonCyan,
          size: 20,
        ),
        title: Text(
          name.toUpperCase(),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 13,
            letterSpacing: 1,
          ),
        ),
        subtitle: Text(
          "ID: $id",
          style: const TextStyle(
            fontFamily: 'Courier',
            fontSize: 9,
            color: AppColors.textGrey,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSaved)
              IconButton(
                icon: const Icon(Icons.link_off, color: AppColors.textGrey, size: 18),
                onPressed: () async {
                  await SettingsService().forgetHost(id);
                  setState(() {});
                },
              ),
            _buildConnectButton(context, id, name),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectButton(BuildContext context, String hostId, String hostName) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.neonCyan.withValues(alpha: 0.1),
        foregroundColor: AppColors.neonCyan,
        side: const BorderSide(color: AppColors.neonCyan, width: 1),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
        minimumSize: const Size(60, 28),
        shape: const BeveledRectangleBorder(),
      ),
      onPressed: () => _showPasswordDialog(context, hostId, hostName),
      child: const Text(
        "LINK",
        style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold),
      ),
    );
  }

  void _showPasswordDialog(BuildContext context, String hostId, String hostName) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.panelGrey,
        shape: const BeveledRectangleBorder(
          side: BorderSide(color: AppColors.neonCyan),
        ),
        title: const Text(
          "UPLINK SECURITY",
          style: TextStyle(
            color: AppColors.neonCyan,
            fontSize: 14,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
        content: TextField(
          controller: controller,
          obscureText: true,
          style: const TextStyle(color: Colors.white),
          onSubmitted: (_) {
            Navigator.pop(context);
            widget.client.connectToHost(hostId, password: controller.text, hostName: hostName);
          },
          decoration: const InputDecoration(
            hintText: "ENTER PASSCODE",
            hintStyle: TextStyle(color: AppColors.textGrey, fontSize: 12),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.neonCyan),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CANCEL", style: TextStyle(color: AppColors.textGrey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.neonCyan,
              foregroundColor: Colors.black,
            ),
            onPressed: () {
              Navigator.pop(context);
              widget.client.connectToHost(hostId, password: controller.text, hostName: hostName);
            },
            child: const Text("ESTABLISH", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}