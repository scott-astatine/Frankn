import 'dart:async';
import 'package:flutter/material.dart';
import 'package:frankn/generated/l10n/app_localizations.dart';
import 'package:frankn/services/rtc_thin_client.dart';
import 'package:frankn/utils/utils.dart';
import 'package:frankn/utils/dc_msg_util.dart';
import 'package:frankn/widgets/cyber_alert_dialog.dart';

void showBluetoothManagerDialog(BuildContext context, RtcThinClient client) {
  showDialog(
    context: context,
    builder: (context) => BluetoothManagerDialog(client: client),
  );
}

class BluetoothManagerDialog extends StatefulWidget {
  final RtcThinClient client;
  const BluetoothManagerDialog({super.key, required this.client});

  @override
  State<BluetoothManagerDialog> createState() => _BluetoothManagerDialogState();
}

class _BluetoothManagerDialogState extends State<BluetoothManagerDialog> {
  List<dynamic> _devices = [];
  bool _isLoading = true;
  StreamSubscription? _sub;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _sub = widget.client.genDcMsgStream.listen((msg) {
      if (!mounted) return;
      if (msg is HostMsgResponse) {
        final data = msg.data;
        if (data != null && data is Map && data.containsKey('devices')) {
          setState(() {
            _devices = List<dynamic>.from(data['devices'] ?? []);
            _isLoading = false;
          });
        }
      } else if (msg is HostMsgUnknown && msg.raw.containsKey('devices')) {
          setState(() {
            _devices = List<dynamic>.from(msg.raw['devices'] ?? []);
            _isLoading = false;
          });
      }
    });

    _fetchDevices();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _fetchDevices(),
    );
  }

  void _fetchDevices() {
    widget.client.sendDcMsg(const DcMsgListBluetoothDevices());
  }

  @override
  void dispose() {
    _sub?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  void _connect(String mac) {
    widget.client.sendDcMsg(DcMsgConnectBluetooth(mac: mac));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return CyberAlertDialog(
      title: l10n.bluetoothDevices,
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
                  child: CircularProgressIndicator(color: AppColors.neonPink),
                ),
              )
            else if (_devices.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Text(
                    l10n.noDevicesFound,
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
                  itemCount: _devices.length,
                  itemBuilder: (context, index) {
                    final dev = _devices[index];
                    final bool isConnected = dev['connected'] == true;
                    return ListTile(
                      leading: Icon(
                        isConnected
                            ? Icons.bluetooth_connected
                            : Icons.bluetooth,
                        color:
                            isConnected ? AppColors.neonPink : Colors.white38,
                      ),
                      title: Text(
                        dev['name'] ?? 'Unknown',
                        style: TextStyle(
                          color: isConnected ? AppColors.neonPink : Colors.white,
                          fontSize: 13,
                          fontWeight:
                              isConnected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      subtitle: isConnected
                          ? Text(
                              l10n.connected,
                              style: const TextStyle(
                                color: AppColors.neonPink,
                                fontSize: 10,
                              ),
                            )
                          : Text(
                              dev['mac'] ?? '',
                              style: const TextStyle(
                                color: AppColors.textGrey,
                                fontSize: 10,
                              ),
                            ),
                      onTap: () => _connect(dev['mac'] ?? ""),
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
}

