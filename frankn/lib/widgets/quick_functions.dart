import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:frankn/services/rtc/rtc.dart';
import 'package:frankn/utils/cyber_card.dart';
import 'package:frankn/utils/utils.dart';
import 'package:frankn/screens/syslog_screen.dart';
import 'package:frankn/screens/file_browser_screen.dart';
import 'package:frankn/screens/process_manager_screen.dart';
import 'package:frankn/screens/ssh_screen.dart';
import 'package:frankn/widgets/volume_mixer_dialog.dart';
import 'package:frankn/generated/l10n/app_localizations.dart';

class QuickFunction extends StatefulWidget {
  final RtcClient client;
  const QuickFunction({super.key, required this.client});

  @override
  State<QuickFunction> createState() => _QuickFunctionState();
}

class _QuickFunctionState extends State<QuickFunction> {
  String _mediaStatus = "Paused";
  String _mediaMetadata = "No Media Sync";
  String _mediaArtist = "Idle";
  double _mediaPosition = 0.0;
  double _mediaLength = 1.0;
  String _playerName = "IDLE.INSTANCE";
  String? _artData;

  @override
  void initState() {
    super.initState();
    
    widget.client.mediaStatusStream.listen((status) {
      if (mounted) setState(() => _mediaStatus = status);
    });

    widget.client.commandResponseStream.listen((resp) {
      if (!mounted) return;
      final data = resp['type'] == 'response' ? resp['data'] : resp;
      if (data == null || data is! Map) return;
      
      setState(() {
        if (data.containsKey('metadata')) {
          final rawMetadata = data['metadata']?.toString() ?? "No Media";
          if (rawMetadata.contains(" - ")) {
            final parts = rawMetadata.split(" - ");
            _mediaMetadata = parts[0];
            _mediaArtist = parts.sublist(1).join(" - ");
          } else {
            _mediaMetadata = rawMetadata;
            _mediaArtist = "Unknown Artist";
          }
        }
        if (data.containsKey('player_name')) {
          _playerName = data['player_name']?.toString().replaceAll("org.mpris.MediaPlayer2.", "").toUpperCase() ?? "IDLE.INSTANCE";
          if (_mediaArtist == "Unknown Artist") {
             _mediaArtist = _playerName.split('.').last;
          }
        }
        if (data.containsKey('art_data')) {
          _artData = data['art_data'];
        }
        if (data['position'] != null) {
          _mediaPosition = (data['position'] as num).toDouble();
        }
        if (data['length'] != null) {
          _mediaLength = (data['length'] as num).toDouble();
          if (_mediaLength <= 0) _mediaLength = 1.0;
        }
      });
    });
  }

  void _seekRelative(int seconds) {
    double target = _mediaPosition + (seconds * 1000000);
    if (target < 0) target = 0;
    if (target > _mediaLength) target = _mediaLength;
    
    widget.client.sendDcMsg({
      DcMsg.Key: DcMsg.Seek,
      "position": target.toInt(),
    });
  }

  String _formatDuration(double microseconds) {
    final duration = Duration(microseconds: microseconds.toInt());
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    String twoDigits(int n) => n.toString().padLeft(2, "0");

    if (hours > 0) {
      return "${twoDigits(hours)}:${twoDigits(minutes)}:${twoDigits(seconds)}";
    } else {
      return "${twoDigits(minutes)}:${twoDigits(seconds)}";
    }
  }

  Widget _buildArtImage(String data, {BoxFit fit = BoxFit.contain}) {
    if (data.startsWith('http')) {
      return Image.network(data, fit: fit, errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image));
    } else {
      try {
        return Image.memory(base64Decode(data), fit: fit, errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image));
      } catch (_) {
        return const Icon(Icons.broken_image);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.neuralDeck.toUpperCase(), style: const TextStyle(color: Colors.white24, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2)),
        const SizedBox(height: 12),
        _buildRichMediaCard(),
        const SizedBox(height: 32),
        Text(l10n.systemOperations.toUpperCase(), style: const TextStyle(color: Colors.white24, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2)),
        const SizedBox(height: 12),
        _buildOperationsGrid(l10n),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildRichMediaCard() {
    final bool isPlaying = _mediaStatus.toLowerCase().contains("playing");

    return CyberCard(
      borderColor: AppColors.neonPink.withValues(alpha: 0.3),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            if (_artData != null)
              Positioned.fill(
                child: Opacity(
                  opacity: 0.15,
                  child: _buildArtImage(_artData!, fit: BoxFit.cover),
                ),
              ),
            if (_artData != null)
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(color: Colors.transparent),
                ),
              ),

            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 72, height: 72,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05), 
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                        ),
                        child: _artData != null 
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: _buildArtImage(_artData!, fit: BoxFit.cover),
                            )
                          : const Center(child: Text("DEM", style: TextStyle(color: AppColors.neonPink, fontWeight: FontWeight.w900, fontSize: 20))),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_mediaMetadata, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                            const SizedBox(height: 4),
                            Text(_mediaArtist, style: const TextStyle(color: AppColors.textGrey, fontSize: 13)),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(Icons.monitor, size: 14, color: AppColors.neonPink),
                                const SizedBox(width: 8),
                                Text(_playerName, style: const TextStyle(fontFamily: 'JetBrainsMonoNerdFont', fontSize: 10, color: AppColors.neonPink, fontWeight: FontWeight.bold, letterSpacing: 1)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _buildProgressSection(),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.replay_10, size: 24, color: Colors.white24), 
                        onPressed: () => _seekRelative(-10),
                      ),
                      IconButton(
                        icon: const Icon(Icons.skip_previous, size: 28), 
                        onPressed: () => widget.client.sendDcMsg({DcMsg.Key: DcMsg.PlayPreviousTrack}),
                      ),
                      GestureDetector(
                        onTap: () => widget.client.sendDcMsg({DcMsg.Key: DcMsg.TogglePlayPause}),
                        child: Container(
                          width: 56, height: 56,
                          decoration: BoxDecoration(color: AppColors.neonPink.withValues(alpha: 0.2), shape: BoxShape.circle),
                          child: Icon(isPlaying ? Icons.pause : Icons.play_arrow, color: AppColors.neonPink, size: 32),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.skip_next, size: 28), 
                        onPressed: () => widget.client.sendDcMsg({DcMsg.Key: DcMsg.PlayNextTrack}),
                      ),
                      IconButton(
                        icon: const Icon(Icons.forward_10, size: 24, color: Colors.white24), 
                        onPressed: () => _seekRelative(10),
                      ),
                      IconButton(
                        icon: const Icon(Icons.tune, size: 22, color: Colors.white24), 
                        onPressed: () => showDialog(
                          context: context, 
                          builder: (context) => VolumeMixerDialog(client: widget.client),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressSection() {
    return Column(
      children: [
        LinearProgressIndicator(
          value: (_mediaPosition / _mediaLength).clamp(0.0, 1.0),
          backgroundColor: Colors.white.withValues(alpha: 0.05),
          valueColor: const AlwaysStoppedAnimation(AppColors.neonPink),
          minHeight: 4,
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(_formatDuration(_mediaPosition), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
            Text(_formatDuration(_mediaLength), style: const TextStyle(color: AppColors.textGrey, fontSize: 11, fontWeight: FontWeight.bold)),
          ],
        ),
      ],
    );
  }

  Widget _buildOperationsGrid(AppLocalizations l10n) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      childAspectRatio: 1.5,
      children: [
        _buildOpCard(l10n.fileBrowser, Icons.folder_outlined, AppColors.cyberYellow, () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => FileBrowserScreen(client: widget.client)));
        }),
        _buildOpCard(l10n.terminal, Icons.terminal_outlined, AppColors.neonCyan, () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => SShScreen(client: widget.client)));
        }, hasGraph: true, highlightColor: AppColors.neonCyan),
        _buildOpCard(l10n.processes, Icons.show_chart, AppColors.textGrey, () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => ProcessManagerScreen(client: widget.client)));
        }),
        _buildOpCard(l10n.sysLog, Icons.article_outlined, AppColors.matrixGreen, () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => SyslogScreen(client: widget.client)));
        }),
      ],
    );
  }

  Widget _buildOpCard(String label, IconData icon, Color color, VoidCallback onTap, {bool hasGraph = false, Color? highlightColor}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: CyberCard(
          borderColor: highlightColor?.withValues(alpha: 0.4) ?? Colors.white.withValues(alpha: 0.05),
          child: Stack(
            children: [
              if (hasGraph) Positioned.fill(child: CustomPaint(painter: _MiniGraphPainter(color: color))),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, color: color, size: 26),
                    const SizedBox(height: 16),
                    Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniGraphPainter extends CustomPainter {
  final Color color;
  _MiniGraphPainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color.withValues(alpha: 0.1)..style = PaintingStyle.stroke..strokeWidth = 2.0;
    final path = Path();
    path.moveTo(0, size.height * 0.9);
    path.lineTo(size.width * 0.3, size.height * 0.85);
    path.lineTo(size.width * 0.5, size.height * 0.92);
    path.lineTo(size.width * 0.7, size.height * 0.8);
    path.lineTo(size.width, size.height * 0.75);
    canvas.drawPath(path, paint);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
