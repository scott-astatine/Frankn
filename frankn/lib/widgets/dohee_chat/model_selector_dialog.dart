import 'dart:async';
import 'package:flutter/material.dart';
import 'package:frankn/services/rtc_thin_client.dart';
import 'package:frankn/services/settings_service.dart';
import 'package:frankn/utils/utils.dart';
import 'package:frankn/utils/cyber_card.dart';
import 'package:frankn/screens/dohee_chat_screen.dart';

class ModelSelectorDialog extends StatefulWidget {
  final RtcThinClient client;
  final bool isSettingsMode;

  const ModelSelectorDialog({
    super.key,
    required this.client,
    this.isSettingsMode = false,
  });

  @override
  State<ModelSelectorDialog> createState() => _ModelSelectorDialogState();
}

class _ModelSelectorDialogState extends State<ModelSelectorDialog> {
  StreamSubscription? _responseSub;
  List<dynamic>? _models;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchModels();
  }

  void _fetchModels() {
    setState(() {
      _models = null;
      _error = null;
    });

    _responseSub = widget.client.commandResponseStream.listen((resp) {
      if (!mounted) return;
      final type = resp['type'];
      if (type == 'response') {
        final data = resp['data'];
        if (data != null && data['models'] != null) {
          setState(() {
            _models = data['models'];
          });
          _responseSub?.cancel();
        } else if (resp['status'] != null &&
            resp['status'] is Map &&
            resp['status']['Error'] != null) {
          setState(() {
            _error = resp['status']['Error'];
          });
          _responseSub?.cancel();
        }
      }
    });

    widget.client.sendDcMsg({DcMsg.Key: 'list_models'});
  }

  @override
  void dispose() {
    _responseSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF0F0F0F),
      shape: const BeveledRectangleBorder(
        side: BorderSide(color: AppColors.neonPink),
        borderRadius: BorderRadius.all(Radius.circular(9.0)),
      ),
      title: const Text(
        "NEURAL MODEL VAULT",
        style: TextStyle(
          color: AppColors.neonPink,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      ),
      content: SizedBox(width: double.maxFinite, child: _buildContent()),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(
            "CANCEL",
            style: TextStyle(color: AppColors.textGrey),
          ),
        ),
      ],
    );
  }

  Widget _buildContent() {
    if (_error != null) {
      return Text(
        _error!,
        style: const TextStyle(color: AppColors.errorRed, fontSize: 12),
      );
    }

    if (_models == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColors.neonPink),
            SizedBox(height: 16),
            Text(
              "SCANNING VAULT...",
              style: TextStyle(color: AppColors.neonPink, fontSize: 10),
            ),
          ],
        ),
      );
    }

    if (_models!.isEmpty) {
      return const Text(
        "No .gguf models found in host vault directory.",
        style: TextStyle(color: AppColors.textGrey, fontSize: 12),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      itemCount: _models!.length,
      itemBuilder: (context, index) {
        final model = _models![index];
        final name = model['name'];
        final size = FileUtils.formatSize(model['size'] as int);

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: CyberCard(
            borderColor: AppColors.neonPink.withValues(alpha: 0.3),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 4,
              ),
              leading: const Icon(Icons.memory, color: AppColors.neonPink),
              title: Text(
                name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                size,
                style: const TextStyle(color: AppColors.textGrey, fontSize: 10),
              ),
              onTap: () {
                Navigator.pop(context, name); // Return selected name
                SettingsService().setLlmDefaultModel(name);

                if (!widget.isSettingsMode) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatScreen(
                        client: widget.client,
                        modelPath:
                            name, // We only send the name, host resolves full path
                      ),
                    ),
                  );
                }
              },
            ),
          ),
        );
      },
    );
  }
}
