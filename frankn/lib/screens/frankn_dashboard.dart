import 'dart:async';
import 'package:flutter/material.dart';
import 'package:frankn/services/rtc_thin_client.dart';
import 'package:frankn/utils/utils.dart';
import 'package:frankn/utils/cyber_card.dart';
import 'package:frankn/widgets/quick_functions.dart';
import 'package:frankn/generated/l10n/app_localizations.dart';
import 'package:frankn/screens/log_terminal_screen.dart';

import 'package:frankn/utils/dc_msg_util.dart';

class FranknDashboard extends StatefulWidget {
  final RtcThinClient client;
  const FranknDashboard({super.key, required this.client});

  @override
  State<FranknDashboard> createState() => _FranknDashboardState();
}

class _FranknDashboardState extends State<FranknDashboard> {
  final List<String> _logs = [];
  double _cpu = 0.0;
  double _ram = 0.0;
  int _ping = 0;
  bool _hasTelemetry = false;

  Timer? _pingTimer;
  int? _lastPingTime;

  @override
  void initState() {
    super.initState();

    // 1. Listen for connection logs
    widget.client.logStream.listen((log) {
      if (mounted) {
        setState(() {
          _logs.insert(0, log);
          if (_logs.length > 50) _logs.removeLast();
        });
      }
    });

    // 2. Listen for host responses (Telemetry + Pongs)
    widget.client.genDcMsgStream.listen((msg) {
      if (!mounted) return;

      // Handle Telemetry Broadcast
      if (msg is HostMsgTelemetry) {
        setState(() {
          _cpu = msg.cpuLoad;
          _ram = msg.usedMem / (1024 * 1024 * 1024);
          _hasTelemetry = true;
        });
      }
      // Handle Ping Response (RTT calculation)
      else if (msg is HostMsgResponse) {
        final data = msg.data;
        if (data is Map && data['response'] == 'Pong') {
          if (_lastPingTime != null) {
            setState(() {
              _ping = DateTime.now().millisecondsSinceEpoch - _lastPingTime!;
              _lastPingTime = null;
            });
          }
        }
      }
    });

    // 3. Start periodic Ping heartbeat (every 5s)
    _pingTimer = Timer.periodic(const Duration(seconds: 5), (_) => _sendPing());
    _sendPing();
  }

  void _sendPing() {
    if (widget.client.currentHostState == HostConnectionState.authenticated) {
      _lastPingTime = DateTime.now().millisecondsSinceEpoch;
      widget.client.sendDcMsg(const DcMsgPing());
    }
  }

  @override
  void dispose() {
    _pingTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          const SizedBox(height: 8),
          _buildTelemetryHUD(),
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              child: QuickFunction(client: widget.client),
            ),
          ),
          _buildLiveLog(),
        ],
      ),
    );
  }

  Widget _buildTelemetryHUD() {
    final l10n = AppLocalizations.of(context)!;
    return CyberCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildStatItem(
              l10n.cpu,
              _hasTelemetry
                  ? "${_cpu.toStringAsFixed(1)}%"
                  : l10n.syncing.toUpperCase(),
              AppColors.neonCyan,
            ),
            _buildHUDDivider(),
            _buildStatItem(
              l10n.ram,
              _hasTelemetry
                  ? "${_ram.toStringAsFixed(1)} GB"
                  : l10n.syncing.toUpperCase(),
              Colors.white,
            ),
            _buildHUDDivider(),
            _buildStatItem(
              l10n.ping,
              _ping > 0 ? "${_ping}ms" : l10n.syncing.toUpperCase(),
              AppColors.matrixGreen,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHUDDivider() => Container(
    width: 1,
    height: 32,
    color: Colors.white.withValues(alpha: 0.05),
  );

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 10,
            color: AppColors.textGrey,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            color: color,
            fontFamily: 'JetBrainsMonoNerdFont',
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  Widget _buildLiveLog() {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.only(bottom: 12, top: 10),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                l10n.liveLog.toUpperCase(),
                style: const TextStyle(
                  color: AppColors.neonCyan,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(
                  Icons.fullscreen_exit,
                  size: 16,
                  color: Colors.white24,
                ),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => LogTerminalScreen(client: widget.client),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _logs.isEmpty
                ? "> [IDLE] Listening for neural signals..."
                : "> ${_logs.first}",
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'JetBrainsMonoNerdFont',
              fontSize: 10,
              color: Colors.white38,
            ),
          ),
        ],
      ),
    );
  }
}
