import 'dart:async';
import 'package:flutter/material.dart';
import 'package:frankn/services/rtc_thin_client.dart';
import 'package:frankn/services/settings_service.dart';
import 'package:frankn/utils/utils.dart';
import 'package:frankn/utils/cyber_card.dart';
import 'package:frankn/utils/cyber_button.dart';
import 'package:frankn/widgets/pairing_dialog.dart';
import 'package:frankn/screens/log_terminal_screen.dart';
import 'package:frankn/generated/l10n/app_localizations.dart';

class HostListPanel extends StatefulWidget {
  final RtcThinClient client;
  const HostListPanel({super.key, required this.client});

  @override
  State<HostListPanel> createState() => _HostListPanelState();
}

class _HostListPanelState extends State<HostListPanel> {
  StreamSubscription? _peerSub;
  StreamSubscription? _hostSub;
  StreamSubscription? _logSub;
  late final List<String> _logs;

  @override
  void initState() {
    super.initState();
    _logs = List.from(widget.client.logHistory);

    _peerSub = widget.client.peerStatusStream.listen((_) {
      if (mounted) setState(() {});
    });
    _hostSub = widget.client.hostListStream.listen((_) {
      if (mounted) setState(() {});
    });
    _logSub = widget.client.logStream.listen((log) {
      if (mounted) {
        setState(() {
          _logs.insert(0, log);
          if (_logs.length > 50) _logs.removeLast();
        });
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.client.requestHostList();
    });
  }

  @override
  void dispose() {
    _peerSub?.cancel();
    _hostSub?.cancel();
    _logSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final savedHosts = SettingsService().savedHosts;
    final l10n = AppLocalizations.of(context)!;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionHeader(l10n.neuralLinks, Icons.link),
                const SizedBox(height: 16),
                if (savedHosts.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Text(
                        l10n.noPersistentLinks.toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white10,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  )
                else
                  ...savedHosts.map(
                    (h) => _buildHostCard(
                      context,
                      h['id']!,
                      h['name']!,
                      isSaved: true,
                      isOnline: widget.client.onlineHostIds.contains(h['id']),
                    ),
                  ),
                const SizedBox(height: 32),
                _buildSectionHeader(l10n.publicDiscovery, Icons.radar),
                const SizedBox(height: 16),
                _buildDiscoveryContent(savedHosts, l10n),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: _buildLiveLog(l10n),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Colors.white24, size: 14),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white24,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _buildLiveLog(AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.only(top: 16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                l10n.liveLog.toUpperCase(),
                style: const TextStyle(
                  color: AppColors.neonCyan,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(
                  Icons.fullscreen_exit,
                  size: 16,
                  color: Colors.white24,
                ),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => LogTerminalScreen(client: widget.client),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF09090B),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            height: MediaQuery.of(context).size.height * 0.10,
            child: _logs.isEmpty
                ? Text(
                    "> [IDLE] Listening for neural signals...",
                    style: TextStyle(
                      fontFamily: 'JetBrainsMonoNerdFont',
                      fontSize: SettingsService().terminalFontSize,
                      color: Colors.white38,
                    ),
                  )
                : ListView.builder(
                    reverse: true,
                    itemCount: _logs.length,
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          "> ${_logs[index]}",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'JetBrainsMonoNerdFont',
                            fontSize: SettingsService().terminalFontSize,
                            color: AppColors.matrixGreen.withValues(alpha: 0.7),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiscoveryContent(
    List<Map<String, String>> savedHosts,
    AppLocalizations l10n,
  ) {
    final hosts = widget.client.currentHosts;
    final filteredHosts = hosts
        .where((h) => !savedHosts.any((s) => s['id'] == h['host_id']))
        .toList();

    return Column(
      children: [
        if (filteredHosts.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Text(
                l10n.noAdditionalTargets.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white10,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
            ),
          )
        else
          ...filteredHosts.map(
            (h) => _buildHostCard(
              context,
              h['host_id'],
              h['display_name'],
              isOnline: true,
            ),
          ),
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

  Widget _buildHostCard(
    BuildContext context,
    String id,
    String name, {
    bool isSaved = false,
    bool isOnline = false,
  }) {
    final Color accentColor = isSaved ? AppColors.neonPink : AppColors.neonCyan;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: CyberCard(
        borderColor: isOnline
            ? accentColor.withValues(alpha: 0.2)
            : Colors.white.withValues(alpha: 0.05),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Container(
                width: 4,
                height: 60,
                decoration: BoxDecoration(
                  color: isOnline ? accentColor : Colors.white10,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    bottomLeft: Radius.circular(16),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Icon(
                Icons.monitor_outlined,
                color: isOnline ? accentColor : Colors.white10,
                size: 28,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        color: isOnline ? Colors.white : Colors.white24,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        letterSpacing: 1,
                      ),
                    ),
                    Text(
                      "ID: $id",
                      style: const TextStyle(
                        color: Colors.white10,
                        fontSize: 9,
                        fontFamily: 'JetBrainsMonoNerdFont',
                        fontWeight: FontWeight.bold,
                      ),
                    ),
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
                    icon: const Icon(
                      Icons.link_off,
                      color: Colors.white10,
                      size: 20,
                    ),
                    onPressed: isSaved
                        ? () async {
                            await SettingsService().forgetHost(id);
                            setState(() {});
                          }
                        : null,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPasswordDialog(
    BuildContext context,
    String hostId,
    String hostName,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    bool isLoading = false;
    String? errorMessage;
    StreamSubscription? errorSub;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          errorSub ??= widget.client.authErrorStream.listen((err) {
            if (mounted) {
              if (err == 'SUCCESS') {
                errorSub?.cancel();
                if (context.mounted) Navigator.pop(context);
                return;
              }
              setState(() {
                isLoading = false;
                errorMessage = err;
                controller.clear();
              });
            }
          });

          return AlertDialog(
            backgroundColor: const Color(0xFF0F0F0F),
            shape: const BeveledRectangleBorder(
              side: BorderSide(color: AppColors.neonCyan),
              borderRadius: BorderRadius.all(Radius.circular(9.0)),
            ),
            title: Text(
              l10n.uplinkSecurity.toUpperCase(),
              style: const TextStyle(
                color: AppColors.neonCyan,
                fontSize: 14,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(8),
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: AppColors.errorRed.withValues(alpha: 0.1),
                      border: Border.all(color: AppColors.errorRed),
                    ),
                    child: Text(
                      errorMessage!.toUpperCase(),
                      style: const TextStyle(
                        color: AppColors.errorRed,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                if (isLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: CircularProgressIndicator(color: AppColors.neonCyan),
                  )
                else
                  TextField(
                    controller: controller,
                    obscureText: true,
                    autofocus: true,
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'JetBrainsMonoNerdFont',
                    ),
                    onSubmitted: (val) {
                      if (val.isEmpty) return;
                      setState(() {
                        isLoading = true;
                        errorMessage = null;
                      });
                      widget.client.connectToHost(
                        hostId,
                        password: val,
                        hostName: hostName,
                      );
                    },
                    decoration: InputDecoration(
                      hintText: l10n.enterPasscode.toUpperCase(),
                      hintStyle: const TextStyle(
                        color: AppColors.textGrey,
                        fontSize: 12,
                      ),
                      enabledBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(color: AppColors.neonCyan),
                      ),
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  errorSub?.cancel();
                  Navigator.pop(context);
                },
                child: Text(
                  l10n.cancel.toUpperCase(),
                  style: const TextStyle(color: AppColors.textGrey),
                ),
              ),
              if (!isLoading)
                TextButton(
                  onPressed: () {
                    if (controller.text.isEmpty) return;
                    setState(() {
                      isLoading = true;
                      errorMessage = null;
                    });
                    widget.client.connectToHost(
                      hostId,
                      password: controller.text,
                      hostName: hostName,
                    );
                  },
                  child: Text(
                    l10n.establish.toUpperCase(),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.neonCyan,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
