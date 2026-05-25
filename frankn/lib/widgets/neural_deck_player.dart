import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:frankn/services/rtc_thin_client.dart';
import 'package:frankn/utils/utils.dart';
import 'package:frankn/utils/dc_msg_util.dart';
import 'package:frankn/widgets/volume_mixer_dialog.dart';
import 'package:frankn/widgets/player_selector_dialog.dart';

import 'package:frankn/generated/l10n/app_localizations.dart';
import 'dart:async';

class NeuralDeckPlayer extends StatefulWidget {
  final RtcThinClient client;

  const NeuralDeckPlayer({super.key, required this.client});

  @override
  State<NeuralDeckPlayer> createState() => _NeuralDeckPlayerState();
}

class _NeuralDeckPlayerState extends State<NeuralDeckPlayer> {
  bool _mediaIsPlaying = false;
  String? _mediaMetadata;
  String? _mediaArtist;
  double _mediaPosition = 0.0;
  double _mediaLength = 1.0;
  String? _playerName;
  String? _artData;

  StreamSubscription? _mediaSub;
  bool _isHoveringCard = false;
  bool _isPlayPressed = false;
  bool _isDraggingScrubber = false;

  @override
  void initState() {
    super.initState();
    widget.client.sendDcMsg(const DcMsgGetMediaStatus());
    _mediaSub = widget.client.genDcMsgStream.listen((msg) {
      if (!mounted) return;
      if (msg is! HostMsgMediaUpdate) return;
      final mediamsg = msg;
      final l10n = AppLocalizations.of(context)!;
      setState(() {
        final rawMetadata = mediamsg.metadata;
        if (rawMetadata.contains(" - ")) {
          final parts = rawMetadata.split(" - ");
          _mediaMetadata = parts[0];
          _mediaArtist = parts.sublist(1).join(" - ");
        } else {
          _mediaMetadata = rawMetadata;
          _mediaArtist = l10n.unknownArtist;
        }
        _playerName = mediamsg.playerName;
        if (_mediaArtist == l10n.unknownArtist) {
          _mediaArtist = _playerName?.split('.').last;
        }
        _artData = mediamsg.artData;
        _mediaPosition = mediamsg.position;
        _mediaLength = mediamsg.length;
        _mediaIsPlaying = mediamsg.playing;
        if (_mediaLength <= 0) _mediaLength = 1.0;
      });
    });
  }

  @override
  void dispose() {
    _mediaSub?.cancel();
    super.dispose();
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

  void _seekRelative(int seconds) {
    double target = _mediaPosition + (seconds * 1000000);
    if (target < 0) target = 0;
    if (target > _mediaLength) target = _mediaLength;

    widget.client.sendDcMsg(DcMsgSeek(position: target.toInt()));
  }

  Widget _buildArtImage(String artImgPath, {BoxFit fit = BoxFit.contain}) {
    if (artImgPath.isEmpty) {
      return const SizedBox.shrink();
    }
    if (artImgPath.startsWith('http')) {
      return Image.network(
        artImgPath,
        fit: fit,
        errorBuilder: (context, error, stackTrace) =>
            const Icon(Icons.broken_image),
      );
    } else if (artImgPath.startsWith('file://')) {
      return Image.file(
        File(artImgPath.replaceFirst('file://', '')),
        fit: fit,
        errorBuilder: (context, error, stackTrace) =>
            const Icon(Icons.broken_image),
      );
    } else {
      try {
        return Image.memory(
          base64Decode(artImgPath),
          fit: fit,
          errorBuilder: (context, error, stackTrace) =>
              const Icon(Icons.broken_image),
        );
      } catch (_) {
        return const Icon(Icons.broken_image);
      }
    }
  }

  Widget _playBtn() {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPlayPressed = true),
      onTapUp: (_) {
        setState(() => _isPlayPressed = false);
        widget.client.sendDcMsg(const DcMsgTogglePlayPause());
      },
      onTapCancel: () => setState(() => _isPlayPressed = false),
      child: AnimatedScale(
        scale: _isPlayPressed ? 0.8 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutBack,
        child: ClipOval(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: AppColors.neonPink.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.neonPink.withValues(alpha: 0.2),
                  width: 1,
                ),
                boxShadow: _mediaIsPlaying
                    ? [
                        BoxShadow(
                          color: AppColors.neonPink.withValues(alpha: 0.1),
                          blurRadius: 15,
                          spreadRadius: 2,
                        ),
                      ]
                    : [],
              ),
              child: Icon(
                _mediaIsPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                color: Colors.white,
                size: 60,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final mediaMetadata = _mediaMetadata ?? l10n.noMediaPlaying;
    final mediaArtist = _mediaArtist ?? l10n.idle;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHoveringCard = true),
      onExit: (_) => setState(() => _isHoveringCard = false),
      child: Container(
        height: 230,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          // border: Border.all(
          //   color: AppColors.neonPink.withValues(alpha: 0.2),
          //   width: 1.0,
          // ),
          boxShadow: const [
            BoxShadow(
              color: Colors.black54,
              blurRadius: 20,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            children: [
              // Base Layer: Blurred Album Art (Animated Hover Zoom)
              Positioned.fill(
                child: AnimatedScale(
                  scale: _isHoveringCard ? 1.05 : 1.1,
                  duration: const Duration(milliseconds: 700),
                  curve: Curves.easeOut,
                  child: _buildArtImage(_artData ?? '', fit: BoxFit.cover),
                ),
              ),

              // Blur Layer
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 8),
                  child: const SizedBox.expand(),
                ),
              ),

              // Gradient Overlay
              Positioned.fill(
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.black87, Colors.transparent],
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                    ),
                  ),
                ),
              ),

              // Main Content
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Thumbnail & Track Info
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            margin: EdgeInsetsGeometry.all(4),
                            width: 78,
                            height: 78,
                            color: Colors.white.withValues(alpha: 0.05),
                            child: _artData != null
                                ? _buildArtImage(_artData!, fit: BoxFit.cover)
                                : Center(
                                    child: Icon(
                                      Icons.music_note,
                                      color: AppColors.neonPink.withValues(
                                        alpha: 0.5,
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                mediaMetadata,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                  shadows: [
                                    Shadow(
                                      color: Colors.black87,
                                      blurRadius: 4,
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                mediaArtist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.textGrey,
                                  fontSize: 14,
                                  shadows: [
                                    Shadow(
                                      color: Colors.black87,
                                      blurRadius: 4,
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Glassy Progress Bar
                    _buildProgressSection(),

                    const SizedBox(height: 12),

                    // Playback Controls
                    Padding(
                      padding: const EdgeInsets.only(left: 14, right: 14),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Player selector & seek 10sec btn...
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AnimatedIconButton(
                                icon: Icons.monitor_outlined,
                                color: AppColors.neonPink,
                                size: 18,
                                onTap: () => showPlayerSelectorDialog(
                                  context,
                                  widget.client,
                                ),
                              ),
                              const SizedBox(width: 20),
                              // Seek back
                              AnimatedIconButton(
                                icon: Icons.replay_10_rounded,
                                size: 24,
                                color: Colors.white70,
                                onTap: () => _seekRelative(-10),
                              ),
                            ],
                          ),

                          // Play toggle btn
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AnimatedIconButton(
                                icon: Icons.skip_previous_rounded,
                                size: 28,
                                color: Colors.white,
                                onTap: () => widget.client.sendDcMsg(
                                  const DcMsgPlayPreviousTrack(),
                                ),
                              ),
                              const SizedBox(width: 16),
                              _playBtn(),
                              const SizedBox(width: 16),
                              AnimatedIconButton(
                                icon: Icons.skip_next,
                                size: 28,
                                color: Colors.white,
                                onTap: () => widget.client.sendDcMsg(
                                  const DcMsgPlayNextTrack(),
                                ),
                              ),
                            ],
                          ),

                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Seek forward
                              AnimatedIconButton(
                                icon: Icons.forward_10_rounded,
                                size: 24,
                                color: Colors.white70,
                                onTap: () => _seekRelative(10),
                              ),
                              const SizedBox(width: 20),
                              AnimatedIconButton(
                                icon: Icons.tune_rounded,
                                size: 18,
                                color: Colors.white70,
                                onTap: () => showDialog(
                                  context: context,
                                  builder: (context) =>
                                      VolumeMixerDialog(client: widget.client),
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProgressSection() {
    double progress = _mediaLength > 0
        ? (_mediaPosition / _mediaLength).clamp(0.0, 1.0)
        : 0.0;
    // Map 0.0..1.0 to -1.0..1.0 for Align
    double alignX = (progress * 2) - 1.0;

    return Padding(
      padding: const EdgeInsets.only(left: 10, right: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final double barWidth = constraints.maxWidth;

              void handleScrub(double localX) {
                final double percent = (localX / barWidth).clamp(0.0, 1.0);
                setState(() {
                  _mediaPosition = percent * _mediaLength;
                });
              }

              void commitSeek() {
                widget.client.sendDcMsg(DcMsgSeek(position: _mediaPosition.toInt()));
              }

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) {
                  setState(() => _isDraggingScrubber = true);
                  handleScrub(details.localPosition.dx);
                  commitSeek();
                },
                onTapUp: (_) => setState(() => _isDraggingScrubber = false),
                onHorizontalDragStart: (_) =>
                    setState(() => _isDraggingScrubber = true),
                onHorizontalDragUpdate: (details) {
                  handleScrub(details.localPosition.dx);
                },
                onHorizontalDragEnd: (_) {
                  setState(() => _isDraggingScrubber = false);
                  commitSeek();
                },
                onHorizontalDragCancel: () =>
                    setState(() => _isDraggingScrubber = false),
                child: Stack(
                  alignment: Alignment.centerLeft,
                  clipBehavior: Clip.none,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                        child: Container(
                          height: 6,
                          width: double.infinity,
                          color: Colors.white.withValues(alpha: 0.1),
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: progress,
                            child: Container(
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [AppColors.neonPink, Colors.pinkAccent],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: Align(
                        alignment: Alignment(alignX, 0),
                        child: AnimatedOpacity(
                          opacity: _isDraggingScrubber ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 200),
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(color: Colors.black54, blurRadius: 4),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(_mediaPosition),
                style: const TextStyle(
                  fontFamily: 'JetBrainsMonoNerdFont',
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                _formatDuration(_mediaLength),
                style: TextStyle(
                  fontFamily: 'JetBrainsMonoNerdFont',
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class AnimatedIconButton extends StatefulWidget {
  final IconData icon;
  final double size;
  final Color color;
  final VoidCallback onTap;

  const AnimatedIconButton({
    super.key,
    required this.icon,
    required this.size,
    required this.color,
    required this.onTap,
  });

  @override
  State<AnimatedIconButton> createState() => _AnimatedIconButtonState();
}

class _AnimatedIconButtonState extends State<AnimatedIconButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) {
          setState(() => _isPressed = false);
          widget.onTap();
        },
        onTapCancel: () => setState(() => _isPressed = false),
        child: AnimatedScale(
          scale: _isPressed ? 0.85 : 1.0,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutBack,
          child: Icon(widget.icon, size: widget.size, color: widget.color),
        ),
      ),
    );
  }
}
