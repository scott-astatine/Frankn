import 'dart:async';
import 'package:flutter/material.dart';
import 'package:frankn/services/rtc_thin_client.dart';
import 'package:frankn/services/settings_service.dart';
import 'package:frankn/utils/utils.dart';
import 'package:frankn/utils/dc_msg_util.dart';
import 'package:frankn/utils/cyber_card.dart';
import 'package:frankn/screens/dohee_chat_screen.dart';
import 'package:frankn/widgets/cyber_alert_dialog.dart';
import 'package:frankn/generated/l10n/app_localizations.dart';

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

    _responseSub = widget.client.genDcMsgStream.listen((msg) {
      if (!mounted) return;
      if (msg is HostMsgResponse) {
        final data = msg.data;
        if (data != null && data is Map && data['models'] != null) {
          setState(() {
            _models = data['models'];
          });
          _responseSub?.cancel();
        } else if (msg.error != null) {
          setState(() {
            _error = msg.error;
          });
          _responseSub?.cancel();
        }
      } else if (msg is HostMsgUnknown && msg.raw.containsKey('models')) {
          setState(() {
            _models = msg.raw['models'];
          });
          _responseSub?.cancel();
      }
    });

    widget.client.sendDcMsg(const DcMsgListModels());
  }

  @override
  void dispose() {
    _responseSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return CyberAlertDialog(
      title: l10n.neuralModelVault,
      content: SizedBox(width: double.maxFinite, child: _buildContent(l10n)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            l10n.cancel,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }

  Widget _buildContent(AppLocalizations l10n) {
    if (_error != null) {
      return Text(
        _error!,
        style: const TextStyle(color: AppColors.accentError, fontSize: 12),
      );
    }

    if (_models == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AppColors.accentSecondary),
            const SizedBox(height: 16),
            Text(
              l10n.scanningVault,
              style: const TextStyle(color: AppColors.accentSecondary, fontSize: 10),
            ),
          ],
        ),
      );
    }

    if (_models!.isEmpty) {
      return Text(
        l10n.noModelsFound,
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
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
            borderColor: AppColors.accentSecondary.withValues(alpha: 0.3),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 4,
              ),
              leading: const Icon(Icons.memory, color: AppColors.accentSecondary),
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
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 10),
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
