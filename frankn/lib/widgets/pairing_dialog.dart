import 'package:flutter/material.dart';
import 'package:frankn/services/settings_service.dart';
import 'package:frankn/utils/utils.dart';
import 'package:frankn/utils/cyber_button.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:frankn/generated/l10n/app_localizations.dart';

class PairingDialog extends StatefulWidget {
  const PairingDialog({super.key});

  @override
  State<PairingDialog> createState() => _PairingDialogState();
}

class _PairingDialogState extends State<PairingDialog> {
  final TextEditingController _idController = TextEditingController();
  final TextEditingController _aliasController = TextEditingController();
  bool _isScanning = false;

  void _onInitialize() async {
    final id = _idController.text.trim();
    final l10n = AppLocalizations.of(context)!;
    final alias = _aliasController.text.trim().isEmpty 
        ? l10n.lastConnectedHost // Fallback alias
        : _aliasController.text.trim();
    
    if (id.length >= 10) {
      await SettingsService().saveHost(id, alias);
      if (mounted) Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF0F0F0F),
          border: Border.all(color: AppColors.neonPink, width: 1.5),
          borderRadius: BorderRadius.circular(16),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.newNeuralLink.toUpperCase(), 
                style: const TextStyle(color: AppColors.neonPink, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 2)),
              const SizedBox(height: 24),
              
              Text(l10n.visualHash.toUpperCase(), style: const TextStyle(color: AppColors.textGrey, fontSize: 10, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              _buildScannerSection(l10n),
              
              const SizedBox(height: 24),
              _buildDivider(l10n),
              const SizedBox(height: 24),
              
              _buildInputField(l10n.hostId.toUpperCase(), "e.g. 550e8400-e29b...", _idController),
              const SizedBox(height: 16),
              _buildInputField(l10n.aliasOptional.toUpperCase(), "e.g. WORK-RIG", _aliasController),
              
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(l10n.abort.toUpperCase(), style: const TextStyle(color: AppColors.textGrey, fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                  const SizedBox(width: 16),
                  CyberButton(
                    text: l10n.initialize.toUpperCase(),
                    variant: CyberButtonVariant.secondary,
                    onPressed: _onInitialize,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScannerSection(AppLocalizations l10n) {
    return Container(
      height: 140,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (_isScanning)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: MobileScanner(
                onDetect: (capture) {
                  final List<Barcode> barcodes = capture.barcodes;
                  if (barcodes.isNotEmpty) {
                    final code = barcodes.first.rawValue;
                    if (code != null && code.contains('|')) {
                      final parts = code.split('|');
                      setState(() {
                        _idController.text = parts[0];
                        _aliasController.text = parts[1];
                        _isScanning = false;
                      });
                    }
                  }
                },
              ),
            )
          else
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.qr_code_scanner, color: Colors.white24, size: 32),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => setState(() => _isScanning = true),
                  child: Text(l10n.tapToScan.toUpperCase(), 
                    style: const TextStyle(color: AppColors.textGrey, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1)),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildDivider(AppLocalizations l10n) {
    return Row(
      children: [
        Expanded(child: Container(height: 1, color: Colors.white.withValues(alpha: 0.05))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(l10n.orManual.toUpperCase(), style: const TextStyle(color: Colors.white10, fontSize: 9, fontWeight: FontWeight.w900)),
        ),
        Expanded(child: Container(height: 1, color: Colors.white.withValues(alpha: 0.05))),
      ],
    );
  }

  Widget _buildInputField(String label, String hint, TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: AppColors.textGrey, fontSize: 10, fontWeight: FontWeight.bold)),
        TextField(
          controller: controller,
          style: const TextStyle(fontFamily: 'JetBrainsMonoNerdFont', fontSize: 13),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.white10),
            enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white10)),
            focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.neonPink)),
          ),
        ),
      ],
    );
  }
}
