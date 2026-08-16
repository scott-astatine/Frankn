import 'dart:async';
import 'package:flutter/material.dart';
import 'package:frankn/services/rtc_thin_client.dart';
import 'package:frankn/services/settings_service.dart';
import 'package:frankn/utils/utils.dart';
import 'package:frankn/utils/cyber_card.dart';
import 'package:frankn/utils/cyber_button.dart';
import 'package:frankn/widgets/host_pairing_dialog.dart';
import 'package:frankn/widgets/cyber_alert_dialog.dart';
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
                _buildSectionHeader(
                  l10n.neuralLinks,
                  Icons.link,
                  action: _HeaderRefreshButton(
                    onPressed: () {
                      widget.client.requestHostList();
                      widget.client.subscribeHosts();
                    },
                  ),
                ),
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
                _buildSectionHeader(
                  l10n.publicDiscovery,
                  Icons.radar,
                  action: _HeaderRefreshButton(
                    onPressed: () {
                      widget.client.requestHostList();
                    },
                  ),
                ),
                const SizedBox(height: 16),
                _buildDiscoveryContent(savedHosts, l10n),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: _buildLiveLog(l10n),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, {Widget? action}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
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
        ),
        if (action != null) action,
      ],
    );
  }

  Widget _buildLiveLog(AppLocalizations l10n) {
    return Container(
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
                  color: AppColors.accentPrimary,
                  fontSize: 12,
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
                            color: AppColors.accentSuccess.withValues(alpha: 0.7),
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
                builder: (context) => const HostPairingDialog(),
              );
              if (result == true) {
                widget.client.subscribeHosts();
                setState(() {});
              }
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
    final Color accentColor = isSaved ? AppColors.accentSecondary : AppColors.accentPrimary;

    final cardWidget = Padding(
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
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: isOnline ? accentColor : Colors.white10,
                            shape: BoxShape.circle,
                            boxShadow: isOnline
                                ? [
                                    BoxShadow(
                                      color: accentColor.withValues(alpha: 0.5),
                                      blurRadius: 4,
                                      spreadRadius: 1,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isOnline ? "ONLINE" : "OFFLINE",
                          style: TextStyle(
                            color: isOnline ? accentColor.withValues(alpha: 0.8) : Colors.white12,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
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
                    onPressed: () => _authDialog(context, id, name),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    if (!isSaved) return cardWidget;

    return Dismissible(
      key: Key('host_card_$id'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) async {
        await SettingsService().forgetHost(id);
        widget.client.subscribeHosts();
        setState(() {});
      },
      background: Container(),
      secondaryBackground: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        alignment: Alignment.centerRight,
        decoration: BoxDecoration(
          color: AppColors.accentError.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.accentError.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.delete_outline,
              color: AppColors.accentError,
              size: 20,
            ),
            SizedBox(width: 8),
            Text(
              "FORGET",
              style: TextStyle(
                color: AppColors.accentError,
                fontWeight: FontWeight.w900,
                fontSize: 10,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
      child: cardWidget,
    );
  }

  void _authDialog(BuildContext context, String hostId, String hostName) {
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

          return CyberAlertDialog(
            title: l10n.uplinkSecurity.toUpperCase(),
            borderColor: AppColors.accentPrimary,
            titleColor: AppColors.accentPrimary,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(8),
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: AppColors.accentError.withValues(alpha: 0.1),
                      border: Border.all(color: AppColors.accentError),
                    ),
                    child: Text(
                      errorMessage!.toUpperCase(),
                      style: const TextStyle(
                        color: AppColors.accentError,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                if (isLoading)
                  Center(
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: CircularProgressIndicator(
                        color: AppColors.accentPrimary,
                      ),
                    ),
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
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                      enabledBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(color: AppColors.accentPrimary),
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
                  style: const TextStyle(color: AppColors.textSecondary),
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
                      color: AppColors.accentPrimary,
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

class _HeaderRefreshButton extends StatefulWidget {
  final VoidCallback onPressed;
  const _HeaderRefreshButton({required this.onPressed});

  @override
  State<_HeaderRefreshButton> createState() => _HeaderRefreshButtonState();
}

class _HeaderRefreshButtonState extends State<_HeaderRefreshButton> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: Tween(begin: 0.0, end: 1.0).animate(_controller),
      child: IconButton(
        icon: const Icon(Icons.refresh, size: 14, color: AppColors.accentPrimary),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        onPressed: () {
          _controller.forward(from: 0.0);
          widget.onPressed();
        },
      ),
    );
  }
}
