import 'dart:async';
import 'package:flutter/material.dart';
import 'package:frankn/services/rtc_thin_client.dart';
import 'package:frankn/utils/utils.dart';
import 'package:frankn/utils/dc_msg_util.dart';
import 'package:frankn/utils/cyber_card.dart';

void showPlayerSelectorDialog(BuildContext context, RtcThinClient client) {
  showDialog(
    context: context,
    builder: (context) => _PlayerSelectorDialog(client: client),
  );
}

class _PlayerSelectorDialog extends StatefulWidget {
  final RtcThinClient client;
  const _PlayerSelectorDialog({required this.client});

  @override
  State<_PlayerSelectorDialog> createState() => _PlayerSelectorDialogState();
}

class _PlayerSelectorDialogState extends State<_PlayerSelectorDialog> {
  List<String> _players = [];
  String? _activePlayer;
  bool _isLoading = true;
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.client.genDcMsgStream.listen((msg) {
      if (!mounted) return;
      if (msg is HostMsgResponse) {
        final data = msg.data;
        if (data != null && data is Map && data.containsKey('players')) {
          setState(() {
            _players = List<String>.from(data['players'] ?? []);
            _activePlayer = data['active_player']?.toString();
            _isLoading = false;
          });
        }
      } else if (msg is HostMsgUnknown && msg.raw.containsKey('players')) {
          setState(() {
            _players = List<String>.from(msg.raw['players'] ?? []);
            _activePlayer = msg.raw['active_player']?.toString();
            _isLoading = false;
          });
      }
    });

    widget.client.sendDcMsg(const DcMsgListPlayers());
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _selectPlayer(String playerName) {
    widget.client.sendDcMsg(DcMsgSetActivePlayer(
      playerName: playerName,
    ));
    // Give it a moment to take effect, then request sync
    Future.delayed(const Duration(milliseconds: 300), () {
      widget.client.sendDcMsg(const DcMsgGetMediaStatus());
    });
    Navigator.pop(context);
  }

  String _cleanName(String raw) {
    return raw.replaceAll("org.mpris.MediaPlayer2.", "").toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.transparent,
      contentPadding: EdgeInsets.zero,
      content: CyberCard(
        borderColor: AppColors.accentSecondary.withValues(alpha: 0.3),
        child: Container(
          width: 300,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.monitor_outlined, color: AppColors.accentSecondary),
                  const SizedBox(width: 12),
                  const Text(
                    "SELECT PLAYER",
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
                    child: CircularProgressIndicator(color: AppColors.accentSecondary),
                  ),
                )
              else if (_players.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24.0),
                    child: Text(
                      "NO PLAYERS FOUND",
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ),
                )
              else
                ..._players.map((p) {
                  final isActive = p == _activePlayer;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: InkWell(
                      onTap: () => _selectPlayer(p),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: isActive
                              ? AppColors.accentSecondary.withValues(alpha: 0.1)
                              : Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isActive
                                ? AppColors.accentSecondary.withValues(alpha: 0.5)
                                : Colors.transparent,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _cleanName(p),
                              style: TextStyle(
                                color: isActive
                                    ? AppColors.accentSecondary
                                    : Colors.white,
                                fontWeight: isActive
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                fontSize: 13,
                              ),
                            ),
                            if (isActive)
                              const Icon(
                                Icons.check,
                                color: AppColors.accentSecondary,
                                size: 16,
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    "CANCEL",
                    style: TextStyle(color: AppColors.textSecondary),
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

