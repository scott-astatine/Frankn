import 'dart:async';
import 'package:flutter/material.dart';
import 'package:frankn/services/rtc_thin_client.dart';
import 'package:frankn/utils/utils.dart';
import 'package:frankn/utils/cyber_card.dart';

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
    _sub = widget.client.genDcMsgStream.listen((resp) {
      if (!mounted) return;
      final data = resp['type'] == 'response' ? resp['data'] : resp;
      if (data != null && data is Map && data.containsKey('devices')) {
        setState(() {
          _devices = List<dynamic>.from(data['devices'] ?? []);
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
    widget.client.sendDcMsg({DcMsg.Key: DcMsg.ListBluetoothDevices});
  }

  @override
  void dispose() {
    _sub?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  void _connect(String mac) {
    widget.client.sendDcMsg({DcMsg.Key: DcMsg.ConnectBluetooth, "mac": mac});
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.transparent,
      contentPadding: EdgeInsets.zero,
      content: CyberCard(
        borderColor: AppColors.neonPink.withValues(alpha: 0.3),
        child: Container(
          width: 300,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.bluetooth, color: AppColors.neonPink),
                  const SizedBox(width: 12),
                  const Text(
                    "BLUETOOTH DEVICES",
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
                    child: CircularProgressIndicator(color: AppColors.neonPink),
                  ),
                )
              else if (_devices.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24.0),
                    child: Text(
                      "NO DEVICES FOUND",
                      style: TextStyle(color: AppColors.textGrey, fontSize: 12),
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
                          color: isConnected
                              ? AppColors.neonPink
                              : Colors.white38,
                        ),
                        title: Text(
                          dev['name'] ?? 'Unknown',
                          style: TextStyle(
                            color: isConnected
                                ? AppColors.neonPink
                                : Colors.white,
                            fontSize: 13,
                            fontWeight: isConnected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                        subtitle: isConnected
                            ? const Text(
                                "Connected",
                                style: TextStyle(
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
}

