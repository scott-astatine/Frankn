import 'package:flutter/material.dart';
import 'package:frankn/services/settings_service.dart';
import 'package:frankn/utils/utils.dart';
import 'package:frankn/utils/cyber_button.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'package:frankn/generated/l10n/app_localizations.dart';

class PairingDialog extends StatefulWidget {
  const PairingDialog({super.key});

  @override
  State<PairingDialog> createState() => _PairingDialogState();
}

class _PairingDialogState extends State<PairingDialog> {
  final TextEditingController _idController = TextEditingController();
  final TextEditingController _aliasController = TextEditingController();
  final MobileScannerController _scannerController = MobileScannerController();
  bool _isScanning = false;

  @override
  void dispose() {
    _idController.dispose();
    _aliasController.dispose();
    _scannerController.dispose();
    super.dispose();
  }

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

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      final capture = await _scannerController.analyzeImage(image.path);
      if (capture != null && capture.barcodes.isNotEmpty) {
        final code = capture.barcodes.first.rawValue;
        if (code != null && code.contains('|')) {
          final parts = code.split('|');
          setState(() {
            _idController.text = parts[0];
            _aliasController.text = parts[1];
            _isScanning = false;
          });
        }
      }
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
          color: AppColors.voidBlack,
          border: Border.all(color: AppColors.neonCyan.withValues(alpha: 0.5), width: 1.5),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: AppColors.neonCyan.withValues(alpha: 0.1),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.newNeuralLink.toUpperCase(),
                style: const TextStyle(
                  color: AppColors.neonCyan,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 24),

              Text(
                l10n.visualHash.toUpperCase(),
                style: const TextStyle(
                  color: AppColors.textGrey,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              _buildScannerSection(l10n),

              const SizedBox(height: 24),
              _buildDivider(l10n),
              const SizedBox(height: 24),

              _buildInputField(
                l10n.hostId.toUpperCase(),
                "e.g. 550e8400-e29b...",
                _idController,
              ),
              const SizedBox(height: 16),
              _buildInputField(
                l10n.aliasOptional.toUpperCase(),
                "e.g. WORK-RIG",
                _aliasController,
              ),

              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      l10n.abort.toUpperCase(),
                      style: const TextStyle(
                        color: AppColors.textGrey,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
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
      height: 180,
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.panelGrey,
        borderRadius: BorderRadius.circular(28), // Round squarish
        border: Border.all(color: AppColors.neonCyan.withValues(alpha: 0.2), width: 1.5),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (_isScanning)
            ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: MobileScanner(
                controller: _scannerController,
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
                const Icon(
                  Icons.qr_code_scanner,
                  color: AppColors.neonCyan,
                  size: 40,
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => setState(() => _isScanning = true),
                  child: Text(
                    l10n.tapToScan.toUpperCase(),
                    style: const TextStyle(
                      color: AppColors.textWhite,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _pickImage,
                  icon: const Icon(Icons.image_outlined, size: 16, color: AppColors.textGrey),
                  label: const Text(
                    "IMPORT FROM IMAGE",
                    style: TextStyle(
                      color: AppColors.textGrey,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                )
              ],
            ),
          
          if (_isScanning)
            Positioned(
              top: 10,
              right: 10,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white70),
                onPressed: () => setState(() => _isScanning = false),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDivider(AppLocalizations l10n) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 1,
            color: Colors.white.withValues(alpha: 0.1),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            l10n.orManual.toUpperCase(),
            style: const TextStyle(
              color: Colors.white30,
              fontSize: 9,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        Expanded(
          child: Container(
            height: 1,
            color: Colors.white.withValues(alpha: 0.1),
          ),
        ),
      ],
    );
  }

  Widget _buildInputField(
    String label,
    String hint,
    TextEditingController controller,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.neonCyan,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
        TextField(
          controller: controller,
          style: const TextStyle(
            fontFamily: 'JetBrainsMonoNerdFont',
            fontSize: 13,
            color: AppColors.textWhite,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.white24),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.neonCyan.withValues(alpha: 0.3)),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.neonCyan),
            ),
          ),
        ),
      ],
    );
  }
}
