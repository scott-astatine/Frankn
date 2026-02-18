import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:frankn/services/settings_service.dart';
import 'package:frankn/utils/utils.dart';
import 'package:frankn/utils/cyber_button.dart';

class PairingDialog extends StatefulWidget {
  const PairingDialog({super.key});

  @override
  State<PairingDialog> createState() => _PairingDialogState();
}

class _PairingDialogState extends State<PairingDialog> {
  final _idController = TextEditingController();
  final _nameController = TextEditingController(text: "New Host");
  bool _isScanning = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.panelGrey,
      shape: const BeveledRectangleBorder(
        side: BorderSide(color: AppColors.neonCyan, width: 1),
      ),
      title: const Text(
        "NEURAL PAIRING",
        style: TextStyle(
          color: AppColors.neonCyan,
          fontSize: 16,
          fontWeight: FontWeight.bold,
          letterSpacing: 2,
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isScanning)
              SizedBox(
                height: 250,
                width: 250,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: MobileScanner(
                    onDetect: (capture) {
                      final List<Barcode> barcodes = capture.barcodes;
                      for (final barcode in barcodes) {
                        if (barcode.rawValue != null) {
                          final data = barcode.rawValue!;
                          if (data.contains('|')) {
                            final parts = data.split('|');
                            setState(() {
                              _idController.text = parts[0];
                              if (parts.length > 1) {
                                _nameController.text = parts[1];
                              }
                              _isScanning = false;
                            });
                          } else {
                            setState(() {
                              _idController.text = data;
                              _isScanning = false;
                            });
                          }
                        }
                      }
                    },
                  ),
                ),
              )
            else ...[
              TextField(
                controller: _idController,
                style: const TextStyle(color: Colors.white, fontFamily: 'Courier'),
                decoration: const InputDecoration(
                  labelText: "HOST ID (12 DIGITS)",
                  labelStyle: TextStyle(color: AppColors.textGrey, fontSize: 10),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: AppColors.neonCyan),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nameController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: "ALIAS",
                  labelStyle: TextStyle(color: AppColors.textGrey, fontSize: 10),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: AppColors.textGrey),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              CyberButton(
                text: "SCAN QR CODE",
                onPressed: () => setState(() => _isScanning = true),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("ABORT", style: TextStyle(color: AppColors.errorRed)),
        ),
        if (!_isScanning)
          CyberButton(
            text: "SAVE LINK",
            onPressed: () async {
              if (_idController.text.length >= 12) {
                final name = _nameController.text.trim().isEmpty 
                    ? "Frankn Host" 
                    : _nameController.text.trim();
                await SettingsService().saveHost(
                  _idController.text,
                  name,
                );
                if (context.mounted) Navigator.pop(context, true);
              }
            },
          ),
      ],
    );
  }
}
