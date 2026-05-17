import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:frankn/generated/l10n/app_localizations.dart';
import 'package:frankn/services/rtc_thin_client.dart';
import 'package:frankn/utils/cyber_card.dart';
import 'package:frankn/utils/utils.dart';
import 'package:frankn/widgets/bluetooth_manager_dialog.dart';
import 'package:frankn/widgets/wifi_manager_dialog.dart';

class SystemTrayModal extends StatefulWidget {
  final RtcThinClient client;
  final VoidCallback onDisconnect;

  const SystemTrayModal({
    super.key,
    required this.client,
    required this.onDisconnect,
  });

  @override
  State<SystemTrayModal> createState() => _SystemTrayModalState();
}

class _SystemTrayModalState extends State<SystemTrayModal> {
  double _volume = 0.5;
  bool _wifiEnabled = false;
  bool _btEnabled = false;
  StreamSubscription? _sub;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final screenHeight = MediaQuery.of(context).size.height;

    return ClipRRect(
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(32),
        topRight: Radius.circular(32),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          constraints: BoxConstraints(maxHeight: screenHeight * 0.8),
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          decoration: BoxDecoration(
            color: AppColors.voidBlack.withValues(alpha: 0.10),
            border: Border(
              top: BorderSide(
                color: AppColors.errorRed.withValues(alpha: 0.4),
                width: 1.5,
              ),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
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
                          fontSize: 14,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.close,
                      color: Colors.white38,
                      size: 20,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Network & Audio Section
                      _buildSectionLabel("CONNECTIVITY & AUDIO"),
                      Row(
                        children: [
                          _buildCompactActionButton(
                            Icons.wifi_rounded,
                            "WI-FI",
                            _wifiEnabled ? AppColors.neonCyan : Colors.white24,
                            () => showWifiManagerDialog(context, widget.client),
                          ),
                          const SizedBox(width: 12),
                          _buildCompactActionButton(
                            Icons.bluetooth_rounded,
                            "BLUETOOTH",
                            _btEnabled ? AppColors.neonPink : Colors.white24,
                            () => showBluetoothManagerDialog(
                              context,
                              widget.client,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Volume Slider
                      CyberCard(
                        borderColor: Colors.white.withValues(alpha: 0.05),
                        bgColor: Colors.white.withValues(alpha: 0.02),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.volume_up,
                                color: AppColors.neonCyan,
                                size: 20,
                              ),
                              Expanded(
                                child: SliderTheme(
                                  data: SliderThemeData(
                                    activeTrackColor: AppColors.neonCyan,
                                    inactiveTrackColor: Colors.white10,
                                    thumbColor: Colors.white,
                                    trackHeight: 2,
                                    thumbShape: const RoundSliderThumbShape(
                                      enabledThumbRadius: 6,
                                    ),
                                    overlayShape: const RoundSliderOverlayShape(
                                      overlayRadius: 14,
                                    ),
                                  ),
                                  child: Slider(
                                    value: _volume.clamp(0.0, 1.5),
                                    max: 1.5,
                                    onChanged: _setVolume,
                                  ),
                                ),
                              ),
                              Text(
                                "${(_volume * 100).round()}%",
                                style: const TextStyle(
                                  color: AppColors.neonCyan,
                                  fontSize: 10,
                                  fontFamily: 'JetBrainsMonoNerdFont',
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 32),
                      _buildSectionLabel("SYSTEM OPERATIONS"),
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 2.4,
                        children: [
                          _buildGridButton(
                            Icons.lock_outline,
                            l10n.lockHost,
                            AppColors.neonCyan,
                            () => widget.client.sendDcMsg({
                              DcMsg.Key: DcMsg.LockScreen,
                            }),
                          ),
                          _buildGridButton(
                            Icons.lock_open,
                            l10n.unlockHost,
                            AppColors.neonCyan,
                            () => widget.client.sendDcMsg({
                              DcMsg.Key: DcMsg.UnlockScreen,
                            }),
                          ),
                          _buildGridButton(
                            Icons.sync,
                            l10n.restartSvc,
                            AppColors.cyberYellow,
                            () => widget.client.sendDcMsg({
                              DcMsg.Key: DcMsg.RestartHostServer,
                            }),
                          ),
                          _buildGridButton(
                            Icons.cloud_download_outlined,
                            l10n.sysUpdate,
                            AppColors.cyberYellow,
                            () => widget.client.sendDcMsg({
                              DcMsg.Key: DcMsg.Update,
                            }),
                          ),
                          _buildGridButton(
                            Icons.restart_alt,
                            l10n.reboot,
                            AppColors.textGrey,
                            () => _confirmDestructiveAction(
                              context,
                              l10n.reboot,
                              DcMsg.Reboot,
                              null,
                            ),
                          ),
                          _buildGridButton(
                            Icons.power_settings_new,
                            l10n.shutdown,
                            AppColors.errorRed,
                            () => _confirmDestructiveAction(
                              context,
                              l10n.shutdown,
                              DcMsg.Shutdown,
                              {"args": "now"},
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),
                      // Disconnect Link
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            widget.client.sendDcMsg({
                              DcMsg.Key: DcMsg.Disconnect,
                            });
                            widget.onDisconnect();
                            Navigator.pop(context);
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: CyberCard(
                            borderColor: AppColors.neonPink.withValues(
                              alpha: 0.3,
                            ),
                            bgColor: AppColors.neonPink.withValues(alpha: 0.05),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.link_off,
                                    color: AppColors.neonPink,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    l10n.disconnectLink.toUpperCase(),
                                    style: const TextStyle(
                                      color: AppColors.neonPink,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 11,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _sub = widget.client.genDcMsgStream.listen(_handleResponse);
    widget.client.sendDcMsg({DcMsg.Key: DcMsg.GetAudioDevices});
    widget.client.sendDcMsg({DcMsg.Key: DcMsg.GetNetworkStatus});
    widget.client.sendDcMsg({DcMsg.Key: DcMsg.GetMediaStatus});
  }

  Widget _buildCompactActionButton(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: CyberCard(
            borderColor: color.withValues(alpha: 0.2),
            bgColor: color.withValues(alpha: 0.05),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: color, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(
                      color: color.withValues(alpha: 0.8),
                      fontWeight: FontWeight.w900,
                      fontSize: 10,
                      letterSpacing: 1,
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

  Widget _buildGridButton(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: CyberCard(
          borderColor: color.withValues(alpha: 0.15),
          bgColor: color.withValues(alpha: 0.03),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(width: 6),
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  color: color.withValues(alpha: 0.9),
                  fontWeight: FontWeight.w900,
                  fontSize: 9,
                  letterSpacing: 0.5,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white24,
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 2,
        ),
      ),
    );
  }

  void _confirmDestructiveAction(
    BuildContext context,
    String title,
    String command,
    Map<String, dynamic>? args,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0F0F0F),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.errorRed),
        ),
        title: Text(
          "CRITICAL // $title",
          style: const TextStyle(
            color: AppColors.errorRed,
            fontSize: 14,
            fontWeight: FontWeight.w900,
          ),
        ),
        content: const Text(
          "Are you sure you want to proceed with this remote command?",
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              "ABORT",
              style: TextStyle(color: AppColors.textGrey),
            ),
          ),
          TextButton(
            onPressed: () {
              final Map<String, dynamic> msg = {DcMsg.Key: command};
              if (args != null) msg.addAll(args);
              widget.client.sendDcMsg(msg);
              Navigator.pop(context); // close dialog
              Navigator.pop(context); // close modal
            },
            child: const Text(
              "CONFIRM",
              style: TextStyle(
                color: AppColors.errorRed,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _handleResponse(dynamic resp) {
    if (!mounted) return;
    widget.client.log("AdMINmSG: $resp");

    final data =
        resp['type'] == DcMsg.HostResponse ||
            resp['type'] == MediaDCMessage.MediaUpdate
        ? resp['data']
        : resp;
    if (data == null || data is! Map) return;

    if (data.containsKey('volume')) {
      setState(() {
        _volume = (data['volume'] as num).toDouble();
      });
    }

    if (data.containsKey('devices')) {
      final devices = data['devices'] as List;
      for (var d in devices) {
        if (d['is_default'] == true || d['is_active'] == true) {
          setState(() {
            final rawVol = (d['vol'] ?? d['volume'] ?? 50.0) as num;
            _volume = rawVol > 1.5
                ? rawVol.toDouble() / 100.0
                : rawVol.toDouble();
          });
          break;
        }
      }
    } else if (data.containsKey('wifi_enabled')) {
      setState(() {
        _wifiEnabled = data['wifi_enabled'] == true;
        _btEnabled = data['bluetooth_enabled'] == true;
      });
    }
  }

  void _setVolume(double val) {
    setState(() => _volume = val);
    widget.client.sendDcMsg({DcMsg.Key: DcMsg.SetVolume, "level": val});
  }
}
