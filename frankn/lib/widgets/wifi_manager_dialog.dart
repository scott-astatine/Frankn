import 'dart:async';

import 'package:flutter/material.dart';
import 'package:frankn/generated/l10n/app_localizations.dart';
import 'package:frankn/services/rtc_thin_client.dart';
import 'package:frankn/utils/utils.dart';
import 'package:frankn/utils/dc_msg_util.dart';
import 'package:frankn/widgets/cyber_alert_dialog.dart';

void showWifiManagerDialog(BuildContext context, RtcThinClient client) {
  showDialog(
    context: context,
    builder: (context) => WifiManagerDialog(client: client),
  );
}

class WifiManagerDialog extends StatefulWidget {
  final RtcThinClient client;
  const WifiManagerDialog({super.key, required this.client});

  @override
  State<WifiManagerDialog> createState() => _WifiManagerDialogState();
}

class _WifiManagerDialogState extends State<WifiManagerDialog> {
  List<dynamic> _networks = [];
  bool _isLoading = true;
  StreamSubscription? _sub;
  Timer? _pollTimer;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return CyberAlertDialog(
      title: l10n.wifiNetworks,
      borderColor: AppColors.neonCyan,
      titleColor: Colors.white,
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24.0),
                  child: CircularProgressIndicator(color: AppColors.neonCyan),
                ),
              )
            else if (_networks.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Text(
                    l10n.noNetworksFound,
                    style:
                        const TextStyle(color: AppColors.textGrey, fontSize: 12),
                  ),
                ),
              )
            else
              SizedBox(
                height: 300,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _networks.length,
                  itemBuilder: (context, index) {
                    final net = _networks[index];
                    final bool inUse = net['in_use'] == true;

                    return ListTile(
                      leading: Icon(
                        inUse ? Icons.wifi : Icons.wifi_outlined,
                        color: inUse ? AppColors.neonCyan : Colors.white38,
                      ),
                      title: Text(
                        net['ssid'] ?? 'Unknown',
                        style: TextStyle(
                          color: inUse ? AppColors.neonCyan : Colors.white,
                          fontSize: 13,
                          fontWeight:
                              inUse ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      subtitle: inUse
                          ? Text(
                              l10n.connected,
                              style: const TextStyle(
                                color: AppColors.neonCyan,
                                fontSize: 10,
                              ),
                            )
                          : null,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (net['security'] != "--" &&
                              net['security'] != "" &&
                              net['security'] != "NONE")
                            const Icon(
                              Icons.lock,
                              color: AppColors.textGrey,
                              size: 14,
                            ),
                          const SizedBox(width: 8),
                          Text(
                            "${net['signal']}%",
                            style: const TextStyle(
                              color: AppColors.textGrey,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                      onTap: () =>
                          _connect(net['ssid'], net['security'] ?? ""),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            l10n.close,
            style: const TextStyle(color: AppColors.textGrey),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _sub = widget.client.genDcMsgStream.listen((msg) {
      if (!mounted) return;
      
      Map<String, dynamic>? data;
      if (msg is HostMsgResponse && msg.data is Map) {
          data = msg.data as Map<String, dynamic>;
      } else if (msg is HostMsgUnknown) {
          data = msg.raw;
      }

      if (data != null && data.containsKey('networks')) {
        setState(() {
          _networks = List<dynamic>.from(data!['networks'] ?? []);
          _isLoading = false;
        });
      }
    });

    _fetchNetworks();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _fetchNetworks(),
    );
  }

  void _connect(String ssid, String security) {
    if (security == "--" || security == "NONE" || security == "") {
      widget.client.sendDcMsg(DcMsgConnectWifi(
        ssid: ssid,
        password: null,
      ));
      Navigator.pop(context);
    } else {
      String pwd = "";
      final l10n = AppLocalizations.of(context)!;
      showDialog(
        context: context,
        builder: (ctx) => CyberAlertDialog(
          title: l10n.connectToSsid(ssid),
          borderColor: AppColors.neonCyan,
          titleColor: Colors.white,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: l10n.password,
                  hintStyle: const TextStyle(color: Colors.white24),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                  ),
                  focusedBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: AppColors.neonCyan),
                  ),
                ),
                onChanged: (v) => pwd = v,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                l10n.cancel,
                style: const TextStyle(color: AppColors.textGrey),
              ),
            ),
            TextButton(
              onPressed: () {
                widget.client.sendDcMsg(DcMsgConnectWifi(
                  ssid: ssid,
                  password: pwd,
                ));
                Navigator.pop(ctx); // Close password dialog
                Navigator.pop(context); // Close wifi dialog
              },
              child: Text(
                l10n.confirm,
                style: const TextStyle(color: AppColors.neonCyan),
              ),
            ),          ],
        ),
      );
    }
  }

  void _fetchNetworks() {
    widget.client.sendDcMsg(const DcMsgListWifiNetworks());
  }
}
