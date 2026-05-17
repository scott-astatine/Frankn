import 'dart:async';

import 'package:flutter/material.dart';
import 'package:frankn/services/rtc_thin_client.dart';
import 'package:frankn/utils/cyber_card.dart';
import 'package:frankn/utils/utils.dart';

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
    return AlertDialog(
      backgroundColor: Colors.transparent,
      contentPadding: EdgeInsets.zero,
      content: CyberCard(
        borderColor: AppColors.neonCyan.withValues(alpha: 0.3),
        child: Container(
          width: 300,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.wifi, color: AppColors.neonCyan),
                  const SizedBox(width: 12),
                  const Text(
                    "WI-FI NETWORKS",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              if (_isLoading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24.0),
                    child: CircularProgressIndicator(color: AppColors.neonCyan),
                  ),
                )
              else if (_networks.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24.0),
                    child: Text(
                      "NO NETWORKS FOUND",
                      style: TextStyle(color: AppColors.textGrey, fontSize: 12),
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
                            fontWeight: inUse
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                        subtitle: inUse
                            ? const Text(
                                "Connected",
                                style: TextStyle(
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
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    "CLOSE",
                    style: TextStyle(color: AppColors.textGrey),
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
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _sub = widget.client.genDcMsgStream.listen((resp) {
      if (!mounted) return;
      final data = resp['type'] == 'response' ? resp['data'] : resp;
      if (data != null && data is Map && data.containsKey('networks')) {
        setState(() {
          _networks = List<dynamic>.from(data['networks'] ?? []);
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
      widget.client.sendDcMsg({
        DcMsg.Key: DcMsg.ConnectWifi,
        "ssid": ssid,
        "password": null,
      });
      Navigator.pop(context);
    } else {
      String pwd = "";
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.transparent,
          contentPadding: EdgeInsets.zero,
          content: CyberCard(
            borderColor: AppColors.neonCyan.withValues(alpha: 0.3),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "CONNECT TO $ssid",
                    style: const TextStyle(
                      color: AppColors.neonCyan,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    obscureText: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: "Password",
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
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text(
                          "CANCEL",
                          style: TextStyle(color: AppColors.textGrey),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          widget.client.sendDcMsg({
                            DcMsg.Key: DcMsg.ConnectWifi,
                            "ssid": ssid,
                            "password": pwd,
                          });
                          Navigator.pop(ctx); // Close password dialog
                          Navigator.pop(context); // Close wifi dialog
                        },
                        child: const Text(
                          "CONNECT",
                          style: TextStyle(color: AppColors.neonCyan),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
  }

  void _fetchNetworks() {
    widget.client.sendDcMsg({DcMsg.Key: DcMsg.ListWifiNetworks});
  }
}
